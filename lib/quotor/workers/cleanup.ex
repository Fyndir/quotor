defmodule Quotor.Workers.Cleanup do
  @moduledoc "Tâche planifiée : purge des montages anonymes anciens et des fichiers temporaires."
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    montages = Quotor.Montages.purge_anonymous(7)
    tmp = purge_tmp(:timer.hours(24))
    Logger.info("nettoyage : #{montages} montage(s), #{tmp} dossier(s) temporaire(s) supprimés")
    :ok
  end

  defp purge_tmp(max_age_ms) do
    dir = Quotor.Media.abs_path("tmp")
    now = System.os_time(:second)

    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(fn path ->
          case File.stat(path, time: :posix) do
            {:ok, %{mtime: mtime}} -> (now - mtime) * 1000 > max_age_ms
            _ -> false
          end
        end)
        |> Enum.map(&File.rm_rf/1)
        |> length()

      _ ->
        0
    end
  end
end
