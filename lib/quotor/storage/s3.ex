defmodule Quotor.Storage.S3 do
  @moduledoc """
  Stockage objet compatible S3 : Cloudflare R2, AWS S3, Scaleway, MinIO…

  Requêtes signées AWS SigV4 (via `Req`), URLs en « path style »
  (`<endpoint>/<bucket>/<clé>`), ce qui fonctionne avec R2 et la plupart des
  fournisseurs. Configuration (cf. `config/runtime.exs`) :

      config :quotor, :s3,
        bucket: "quotor",
        endpoint: "https://<compte>.r2.cloudflarestorage.com",
        region: "auto",
        access_key_id: "...",
        secret_access_key: "...",
        # facultatif : URL publique du bucket (domaine R2 ou CDN). Sans elle,
        # les fichiers sont servis par l'application (bucket privé).
        public_url: "https://media.example.com"
  """
  @behaviour Quotor.Storage

  require Logger

  # Au-delà, le fichier est envoyé en flux plutôt que chargé en mémoire.
  @stream_threshold 8 * 1024 * 1024

  defp config, do: Application.get_env(:quotor, :s3, [])

  @doc false
  def req(extra \\ []) do
    c = config()
    {bucket, extra} = Keyword.pop(extra, :bucket)

    [
      base_url:
        String.trim_trailing(c[:endpoint] || "", "/") <> "/" <> (bucket || c[:bucket] || ""),
      aws_sigv4: [
        service: :s3,
        region: c[:region] || "auto",
        access_key_id: c[:access_key_id],
        secret_access_key: c[:secret_access_key]
      ],
      retry: :transient,
      max_retries: 3,
      decode_body: false
    ]
    |> Req.new()
    |> Req.merge(Keyword.get(c, :req_options, []))
    |> Req.merge(extra)
  end

  defp object_url(key),
    do: "/" <> (key |> String.split("/") |> Enum.map_join("/", &URI.encode_www_form/1))

  @doc """
  Crée le bucket s'il n'existe pas (pratique avec un serveur S3 local ; sur R2
  on crée plutôt le bucket depuis le tableau de bord).
  """
  def ensure_bucket(bucket \\ nil) do
    c = config()
    bucket = bucket || c[:bucket]

    bucket_req =
      Req.new(
        base_url: String.trim_trailing(c[:endpoint] || "", "/"),
        aws_sigv4: [
          service: :s3,
          region: c[:region] || "auto",
          access_key_id: c[:access_key_id],
          secret_access_key: c[:secret_access_key]
        ],
        decode_body: false,
        retry: :transient
      )
      |> Req.merge(Keyword.get(c, :req_options, []))

    case Req.head(bucket_req, url: "/" <> bucket) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      _ ->
        case Req.put(bucket_req, url: "/" <> bucket, body: "") do
          {:ok, %Req.Response{status: status}} when status in [200, 409] -> :ok
          other -> {:error, "création du bucket impossible : #{inspect(other, limit: 5)}"}
        end
    end
  end

  @impl true
  def put(src, key, opts \\ []) do
    %File.Stat{size: size} = File.stat!(src)

    {body, headers} =
      if size > @stream_threshold,
        do: {File.stream!(src, 1_048_576), [{"content-length", Integer.to_string(size)}]},
        else: {File.read!(src), []}

    headers = [{"content-type", MIME.from_path(key)} | headers]

    case Req.put(req(Keyword.take(opts, [:bucket])),
           url: object_url(key),
           body: body,
           headers: headers
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        if Keyword.get(opts, :move, false), do: File.rm(src)
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "S3 PUT #{key} : HTTP #{status} #{String.slice(to_string(body), 0, 200)}"}

      {:error, exception} ->
        {:error, "S3 PUT #{key} : #{Exception.message(exception)}"}
    end
  end

  @impl true
  def get(key, dest), do: get(key, dest, [])

  @doc "Comme `get/2`, avec `bucket:` facultatif."
  def get(key, dest, opts) do
    File.mkdir_p!(Path.dirname(dest))
    part = dest <> ".part"

    result =
      Req.get(req(Keyword.take(opts, [:bucket])), url: object_url(key), into: File.stream!(part))

    case result do
      {:ok, %Req.Response{status: 200}} ->
        File.rename!(part, dest)
        :ok

      {:ok, %Req.Response{status: 404}} ->
        File.rm(part)
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        File.rm(part)
        {:error, "S3 GET #{key} : HTTP #{status}"}

      {:error, exception} ->
        File.rm(part)
        {:error, "S3 GET #{key} : #{Exception.message(exception)}"}
    end
  end

  @impl true
  def exists?(key) do
    match?({:ok, %Req.Response{status: 200}}, Req.head(req(), url: object_url(key)))
  end

  @impl true
  def delete(key), do: delete(key, [])

  @doc "Comme `delete/1`, avec `bucket:` facultatif."
  def delete(key, opts) do
    case Req.delete(req(Keyword.take(opts, [:bucket])), url: object_url(key)) do
      {:ok, %Req.Response{status: status}} when status in [200, 204, 404] ->
        :ok

      other ->
        Logger.warning("S3 DELETE #{key} en échec : #{inspect(other, limit: 5)}")
        :ok
    end
  end

  @impl true
  def delete_prefix(prefix) do
    prefix
    |> list()
    |> Task.async_stream(fn {key, _size} -> delete(key) end, max_concurrency: 8, timeout: 30_000)
    |> Stream.run()
  end

  @impl true
  def list(prefix), do: list(prefix, [])

  @doc "Comme `list/1`, avec `bucket:` facultatif."
  def list(prefix, opts), do: list_page(prefix, nil, [], Keyword.take(opts, [:bucket]))

  defp list_page(prefix, token, acc, opts) do
    params =
      [{"list-type", "2"}, {"prefix", prefix}] ++
        if(token, do: [{"continuation-token", token}], else: [])

    case Req.get(req(opts), url: "/", params: params) do
      {:ok, %Req.Response{status: 200, body: xml}} ->
        objects =
          Regex.scan(~r{<Contents>.*?<Key>(.*?)</Key>.*?<Size>(\d+)</Size>.*?</Contents>}s, xml)
          |> Enum.map(fn [_, key, size] -> {xml_unescape(key), String.to_integer(size)} end)

        acc = acc ++ objects

        case Regex.run(~r{<NextContinuationToken>(.*?)</NextContinuationToken>}s, xml) do
          [_, next] -> list_page(prefix, xml_unescape(next), acc, opts)
          nil -> acc
        end

      other ->
        Logger.warning("S3 LIST #{prefix} en échec : #{inspect(other, limit: 5)}")
        acc
    end
  end

  defp xml_unescape(s) do
    s
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  @impl true
  def public_url(key) do
    case config()[:public_url] do
      url when is_binary(url) and url != "" -> String.trim_trailing(url, "/") <> "/" <> key
      _ -> nil
    end
  end

  @doc """
  Récupère un objet pour le relayer au navigateur (bucket privé). Les fichiers
  servis (clips, vignettes, montages) sont petits : ils sont lus en entier.
  `headers` peut contenir `range` et `if-none-match`.
  """
  def fetch_for_proxy(key, headers) do
    case Req.get(req(), url: object_url(key), headers: headers) do
      {:ok, %Req.Response{} = resp} -> {:ok, resp}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
