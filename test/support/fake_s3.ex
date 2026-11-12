defmodule Quotor.FakeS3 do
  @moduledoc """
  Faux bucket S3 en mémoire pour les tests, branché sur `Quotor.Storage.S3`
  via `Req.Test`. Vérifie au passage que chaque requête est signée (SigV4) et
  adressée en « path style » (`/<bucket>/<clé>`).
  """

  import Plug.Conn

  @bucket "quotor-test"

  def bucket, do: @bucket

  @doc "Active le stockage S3 factice pour le test courant (non `async`)."
  def setup! do
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    previous = {Application.get_env(:quotor, :storage), Application.get_env(:quotor, :s3)}

    Application.put_env(:quotor, :storage, :s3)

    Application.put_env(:quotor, :s3,
      bucket: @bucket,
      endpoint: "https://s3.test",
      region: "auto",
      access_key_id: "test-key",
      secret_access_key: "test-secret",
      req_options: [plug: {Req.Test, Quotor.Storage.S3}, retry: false]
    )

    Req.Test.stub(Quotor.Storage.S3, &handle(&1, agent))

    ExUnit.Callbacks.on_exit(fn ->
      {storage, s3} = previous
      Application.put_env(:quotor, :storage, storage || :local)
      if s3, do: Application.put_env(:quotor, :s3, s3), else: Application.delete_env(:quotor, :s3)
    end)

    agent
  end

  @doc "Objets d'un bucket (par défaut le bucket des médias)."
  def objects(agent, bucket \\ @bucket), do: Agent.get(agent, &Map.get(&1, bucket, %{}))

  def handle(conn, agent) do
    [auth] = get_req_header(conn, "authorization")

    unless String.starts_with?(auth, "AWS4-HMAC-SHA256 Credential=test-key/") do
      raise "requête S3 non signée : #{auth}"
    end

    # tout bucket est accepté (médias, sauvegardes…), adressé en path style
    case {conn.method, String.split(conn.request_path, "/", parts: 3)} do
      {"GET", ["", bucket, ""]} ->
        list(conn, {agent, bucket})

      {method, ["", bucket, key]} when key != "" ->
        object(conn, method, URI.decode(key), {agent, bucket})

      _ ->
        send_resp(conn, 400, "mauvais bucket")
    end
  end

  defp object(conn, "PUT", key, {agent, bucket}) do
    {:ok, body, conn} = read_all(conn, "")
    [type | _] = get_req_header(conn, "content-type") ++ ["application/octet-stream"]

    Agent.update(
      agent,
      &Map.update(&1, bucket, %{key => {body, type}}, fn m -> Map.put(m, key, {body, type}) end)
    )

    send_resp(conn, 200, "")
  end

  defp object(conn, method, key, {agent, bucket}) when method in ["GET", "HEAD"] do
    case Map.get(objects(agent, bucket), key) do
      nil ->
        send_resp(conn, 404, "<Error><Code>NoSuchKey</Code></Error>")

      {body, type} ->
        conn = put_resp_header(conn, "content-type", type)

        case get_req_header(conn, "range") do
          ["bytes=" <> spec] ->
            [first, last] = String.split(spec, "-")
            first = String.to_integer(first)
            last = if last == "", do: byte_size(body) - 1, else: String.to_integer(last)

            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{byte_size(body)}")
            |> send_resp(206, binary_part(body, first, last - first + 1))

          _ ->
            send_resp(conn, 200, if(method == "HEAD", do: "", else: body))
        end
    end
  end

  defp object(conn, "DELETE", key, {agent, bucket}) do
    Agent.update(agent, &Map.update(&1, bucket, %{}, fn m -> Map.delete(m, key) end))
    send_resp(conn, 204, "")
  end

  defp list(conn, {agent, bucket}) do
    conn = fetch_query_params(conn)
    prefix = conn.query_params["prefix"] || ""

    contents =
      agent
      |> objects(bucket)
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, prefix) end)
      |> Enum.map_join(fn {key, {body, _}} ->
        "<Contents><Key>#{key}</Key><Size>#{byte_size(body)}</Size></Contents>"
      end)

    send_resp(conn, 200, "<ListBucketResult>#{contents}</ListBucketResult>")
  end

  defp read_all(conn, acc) do
    case read_body(conn) do
      {:ok, body, conn} -> {:ok, acc <> body, conn}
      {:more, body, conn} -> read_all(conn, acc <> body)
    end
  end
end
