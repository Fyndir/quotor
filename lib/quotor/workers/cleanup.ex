defmodule Quotor.Workers.Cleanup do
  @moduledoc """
  Tâche planifiée : purge des montages anonymes anciens, des dossiers de
  travail temporaires et du cache local des fichiers venant du stockage objet.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Quotor.Media

  @impl Oban.Worker
  def perform(_job) do
    montages = Quotor.Montages.purge_anonymous(7)
    tmp = purge_older_than(Path.join(Media.root(), "tmp"), :timer.hours(24), :entries)
    cache = purge_older_than(Path.join(Media.root(), "cache"), :timer.hours(72), :files)

    Logger.info(
      "nettoyage : #{montages} montage(s), #{tmp} dossier(s) temporaire(s), #{cache} fichier(s) en cache supprimés"
    )

    :ok
  end

  # :entries — supprime les entrées de premier niveau trop anciennes (dossiers de travail)
  # :files — supprime, récursivement, les fichiers trop anciens (cache)
  defp purge_older_than(dir, max_age_ms, mode) do
    now = System.os_time(:second)
    old? = fn path -> older?(path, now, max_age_ms) end

    paths =
      case mode do
        :entries ->
          case File.ls(dir) do
            {:ok, entries} -> Enum.map(entries, &Path.join(dir, &1))
            _ -> []
          end

        :files ->
          dir |> Path.join("**") |> Path.wildcard() |> Enum.filter(&File.regular?/1)
      end

    paths
    |> Enum.filter(old?)
    |> Enum.map(&File.rm_rf/1)
    |> length()
  end

  defp older?(path, now, max_age_ms) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> (now - mtime) * 1000 > max_age_ms
      _ -> false
    end
  end
end
