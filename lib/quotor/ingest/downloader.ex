defmodule Quotor.Ingest.Downloader do
  @moduledoc """
  Comportement d'un téléchargeur de vidéos. L'implémentation par défaut est
  `Quotor.Ingest.YtDlp` ; les tests utilisent un faux téléchargeur.
  """

  @type fetched :: %{
          video_path: String.t(),
          subtitle_path: String.t() | nil,
          metadata: %{
            optional(:title) => String.t(),
            optional(:uploader) => String.t(),
            optional(:duration_s) => integer(),
            optional(:published_on) => Date.t()
          }
        }

  @callback fetch(url :: String.t(), workdir :: String.t()) ::
              {:ok, fetched()} | {:error, String.t()}

  @callback list_channel(url :: String.t(), limit :: pos_integer()) ::
              {:ok, [%{id: String.t(), title: String.t() | nil}]} | {:error, String.t()}

  def impl, do: Application.get_env(:quotor, :downloader, Quotor.Ingest.YtDlp)
end
