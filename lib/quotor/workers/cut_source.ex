defmodule Quotor.Workers.CutSource do
  @moduledoc "Découpe les clips (et vignettes) de toutes les quotes en attente d'une source."
  use Oban.Worker,
    queue: :media,
    max_attempts: 3,
    unique: [
      keys: [:source_id],
      period: 300,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_id" => id}}), do: Quotor.Ingest.cut(id)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(60)
end
