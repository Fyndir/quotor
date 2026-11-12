defmodule QuotorWeb.MediaController do
  @moduledoc """
  Sert les fichiers médias depuis `MEDIA_DIR`, avec prise en charge des
  requêtes `Range` (indispensable à la lecture vidéo sur Safari / iOS).
  """
  use QuotorWeb, :controller

  alias Quotor.Media

  @public_dirs ~w(clips thumbs montages)

  def show(conn, %{"path" => [dir | _] = segments}) when dir in @public_dirs do
    case Media.resolve(segments) do
      {:ok, path} -> send_media(conn, path)
      :error -> send_resp(conn, 404, "Not found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Not found")

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
