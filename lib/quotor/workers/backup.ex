defmodule Quotor.Workers.Backup do
  @moduledoc """
  Sauvegarde de la base et des médias (`Quotor.Backup`), planifiée chaque
  nuit (cron Oban) ou lancée depuis l'administration (`manual: true`).
  Les sauvegardes au-delà de la rétention sont ensuite supprimées.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Quotor.Backup

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if args["manual"] || Backup.enabled?() do
      with {:ok, _info} <- Backup.run() do
        Backup.prune()
        :ok
      end
    else
      {:cancel, "sauvegardes planifiées désactivées (BACKUP_ENABLED=false)"}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(60)

  @doc "Lance une sauvegarde en arrière-plan. `{:ok, :started | :already_running}`."
  def enqueue do
    case %{manual: true} |> new() |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true}} -> {:ok, :already_running}
      {:ok, _job} -> {:ok, :started}
      {:error, _} = error -> error
    end
  end

  @doc """
  État des tâches de sauvegarde : `running?` (en file ou en cours) et dernier
  échec (`{date, message}` ou `nil`).
  """
  def status do
    import Ecto.Query

    worker = inspect(__MODULE__)

    running? =
      Quotor.Repo.exists?(
        from j in Oban.Job,
          where: j.worker == ^worker and j.state in ["available", "executing", "retryable"]
      )

    last =
      Quotor.Repo.one(
        from j in Oban.Job,
          where: j.worker == ^worker and not is_nil(j.attempted_at),
          order_by: [desc: j.attempted_at],
          limit: 1
      )

    failure =
      case last do
        %Oban.Job{state: state, errors: [_ | _] = errors, attempted_at: at}
        when state in ["retryable", "discarded"] ->
          %{"error" => error} = List.last(errors)
          {at, error |> String.split("\n") |> hd() |> String.slice(0, 400)}

        _ ->
          nil
      end

    %{running?: running?, failure: failure}
  end
end
