defmodule QuotorWeb.DownloadController do
  @moduledoc """
  Téléchargement d'une vidéo (montage ou extrait) en pièce jointe, avec un nom
  de fichier lisible tiré de la phrase.

  Passe toujours par le site, même quand les vidéos sont servies directement
  par le bucket : l'attribut HTML `download` est ignoré par les navigateurs
  pour une URL d'un autre domaine (ils ouvriraient la vidéo au lieu de
  l'enregistrer). Depuis S3/R2, le fichier est relayé en flux.
  """
  use QuotorWeb, :controller

  alias Quotor.{Catalog, Media, Montages, Storage, Text}

  def montage(conn, %{"key" => key}) do
    case Montages.get_by_key(key) do
      %{file_path: path} = montage when is_binary(path) ->
        send_video(conn, path, filename(montage.query))

      _ ->
        not_found(conn)
    end
  end

  def quote(conn, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         %{clip_path: path} = quote when is_binary(path) <- Catalog.get_public_quote(id) do
      send_video(conn, path, filename(quote.text))
    else
      _ -> not_found(conn)
    end
  end

  @doc false
  # « Bonjour à tous ! » → quotor-bonjour-a-tous.mp4
  def filename(text) do
    slug =
      text
      |> Text.normalize()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 60)
      |> String.trim("-")

    if slug == "", do: "quotor.mp4", else: "quotor-#{slug}.mp4"
  end

  defp send_video(conn, key, filename) do
    conn =
      conn
      |> put_resp_content_type("video/mp4", nil)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))

    if Storage.local?(), do: send_local(conn, key), else: relay_s3(conn, key)
  end

  defp send_local(conn, key) do
    case Media.resolve(String.split(key, "/")) do
      {:ok, path} -> send_file(conn, 200, path)
      :error -> not_found(conn)
    end
  end

  defp relay_s3(conn, key) do
    # pas de nouvel essai automatique : le corps est envoyé au fil de l'eau
    req = Storage.S3.req(retry: false)
    url = "/" <> key

    case Req.head(req, url: url) do
      {:ok, %Req.Response{status: 200}} ->
        conn |> send_chunked(200) |> stream_body(req, url)

      _ ->
        not_found(conn)
    end
  end

  @doc false
  # Relaie le corps d'une réponse S3 morceau par morceau. La conn renvoyée par
  # chaque `chunk/2` est conservée (le dictionnaire de processus sert
  # d'accumulateur : la fonction `into:` de Req ne transporte que req/resp).
  def stream_body(conn, req, url) do
    ref = make_ref()
    Process.put(ref, conn)

    Req.get(req,
      url: url,
      into: fn {:data, data}, acc ->
        case chunk(Process.get(ref), data) do
          {:ok, conn} ->
            Process.put(ref, conn)
            {:cont, acc}

          {:error, _closed} ->
            {:halt, acc}
        end
      end
    )

    Process.delete(ref)
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> delete_resp_header("content-disposition")
    |> send_resp(404, "Vidéo introuvable")
  end
end
