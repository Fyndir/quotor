defmodule QuotorWeb.MediaController do
  @moduledoc """
  Sert les fichiers médias publics (clips, vignettes, montages), avec prise
  en charge des requêtes `Range` (indispensable à la lecture vidéo sur
  Safari / iOS).

    * stockage local : envoi du fichier depuis `MEDIA_DIR` ;
    * stockage S3 sans URL publique (bucket privé) : l'objet est relayé depuis
      le bucket. Avec une URL publique, les pages pointent directement vers le
      bucket et ce contrôleur n'est pas sollicité.
  """
  use QuotorWeb, :controller

  alias Quotor.{Media, Storage}

  @public_dirs ~w(clips thumbs montages)
  # (content-length est recalculé par le serveur)
  @relayed_headers ~w(content-type content-range accept-ranges etag last-modified)

  def show(conn, %{"path" => [dir | _] = segments}) when dir in @public_dirs do
    cond do
      Storage.local?() ->
        case Media.resolve(segments) do
          {:ok, path} -> send_media(conn, path)
          :error -> send_resp(conn, 404, "Not found")
        end

      Enum.any?(segments, &(&1 in ["", ".", ".."])) ->
        send_resp(conn, 404, "Not found")

      true ->
        relay(conn, Enum.join(segments, "/"))
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Not found")

  defp relay(conn, key) do
    headers =
      for name <- ["range", "if-none-match"],
          value <- get_req_header(conn, name),
          do: {name, value}

    case Storage.S3.fetch_for_proxy(key, headers) do
      {:ok, %Req.Response{status: status} = resp} when status in [200, 206, 304, 416] ->
        conn =
          Enum.reduce(@relayed_headers, conn, fn name, conn ->
            case Req.Response.get_header(resp, name) do
              [value | _] -> put_resp_header(conn, name, value)
              [] -> conn
            end
          end)

        conn
        |> put_resp_header("cache-control", "public, no-cache")
        |> send_resp(status, if(status == 304, do: "", else: resp.body))

      {:ok, %Req.Response{status: status}} when status in [403, 404] ->
        send_resp(conn, 404, "Not found")

      _ ->
        send_resp(conn, 502, "Stockage indisponible")
    end
  end

  defp send_media(conn, path) do
    %File.Stat{size: size, mtime: mtime} = File.stat!(path, time: :posix)

    # Un fichier régénéré au même chemin (nouvelle ingestion) change d'ETag :
    # le navigateur revalide à chaque lecture (réponse 304 très légère) au lieu
    # de rejouer une ancienne version gardée en cache.
    etag = ~s("#{Integer.to_string(mtime, 36)}-#{Integer.to_string(size, 36)}")

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "public, no-cache")

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type(MIME.from_path(path), nil)
      |> put_resp_header("accept-ranges", "bytes")
      |> send_range(path, size)
    end
  end

  defp send_range(conn, path, size) do
    case parse_range(get_req_header(conn, "range"), size) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :none ->
        send_file(conn, 200, path)

      :invalid ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  @doc false
  def parse_range(["bytes=" <> spec], size) do
    case String.split(spec, "-", parts: 2) do
      ["", suffix] ->
        with {n, ""} when n > 0 <- Integer.parse(suffix) do
          {:ok, max(size - n, 0), size - 1}
        else
          _ -> :invalid
        end

      [first, ""] ->
        with {f, ""} when f < size <- Integer.parse(first) do
          {:ok, f, size - 1}
        else
          _ -> :invalid
        end

      [first, last] ->
        with {f, ""} <- Integer.parse(first),
             {l, ""} <- Integer.parse(last),
             true <- f <= l and f < size do
          {:ok, f, min(l, size - 1)}
        else
          _ -> :invalid
        end
    end
  end

  def parse_range(_, _size), do: :none
end
