defmodule QuotorWeb.Admin.BackupController do
  @moduledoc """
  Téléchargement d'une archive de sauvegarde (administrateurs uniquement,
  cf. pipeline `:require_admin_user`). Depuis un bucket S3, l'archive est
  relayée en flux, sans passer par le disque.
  """
  use QuotorWeb, :controller

  require Logger

  alias Quotor.Backup

  def download(conn, %{"name" => name}) do
    if Backup.valid_name?(name) do
      Logger.info("admin : téléchargement de la sauvegarde #{name}")

      case Backup.destination() do
        {:local, _dir} -> send_local(conn, name)
        {:s3, bucket} -> relay_s3(conn, bucket, name)
      end
    else
      not_found(conn)
    end
  end

  defp send_local(conn, name) do
    path = Backup.local_path(name)

    if File.regular?(path) do
      conn
      |> put_resp_content_type("application/x-tar")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{name}"))
      |> send_file(200, path)
    else
      not_found(conn)
    end
  end

  defp relay_s3(conn, bucket, name) do
    # pas de nouvel essai automatique : le corps est déjà en partie envoyé
    req = Quotor.Storage.S3.req(bucket: bucket, retry: false)
    url = "/backups/" <> name

    case Req.head(req, url: url) do
      {:ok, %Req.Response{status: 200}} ->
        conn =
          conn
          |> put_resp_content_type("application/x-tar")
          |> put_resp_header("content-disposition", ~s(attachment; filename="#{name}"))
          |> send_chunked(200)

        Req.get(req,
          url: url,
          into: fn {:data, data}, acc ->
            case chunk(conn, data) do
              {:ok, _conn} -> {:cont, acc}
              {:error, _closed} -> {:halt, acc}
            end
          end
        )

        conn

      _ ->
        not_found(conn)
    end
  end

  defp not_found(conn) do
    conn |> put_resp_content_type("text/plain") |> send_resp(404, "Sauvegarde introuvable")
  end
end
