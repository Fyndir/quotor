defmodule Quotor.Workers.SyncChannels do
  @moduledoc """
  Tâche planifiée (cron) : récupère les nouvelles vidéos des chaînes suivies
  activées. Peut aussi être lancée pour une seule chaîne (`channel_id`).
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  alias Quotor.{Catalog, Ingest}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"channel_id" => id}}) do
    id |> Catalog.get_channel!() |> Ingest.sync_channel()
    :ok
  end

  def perform(%Oban.Job{}) do
    Enum.each(Catalog.list_enabled_channels(), &Ingest.sync_channel/1)
    :ok
  end
end
