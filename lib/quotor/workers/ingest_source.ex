defmodule Quotor.Workers.IngestSource do
  @moduledoc "Télécharge une vidéo et ses sous-titres puis crée ses quotes."
  use Oban.Worker,
    queue: :ingest,
    max_attempts: 3,
    unique: [
      keys: [:source_id],
      period: 300,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => id}}), do: Quotor.Ingest.process(id)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)
end
