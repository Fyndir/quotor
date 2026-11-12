defmodule Quotor.Release do
  @moduledoc """
  Tâches exécutées dans la release (sans Mix), par ex. depuis l'entrypoint
  Docker : `bin/quotor eval "Quotor.Release.setup()"`.
  """
  @app :quotor

  require Logger

  @doc "Migrations + administrateur + chaînes par défaut."
  def setup do
    migrate()
    seed()
    ensure_bucket()
  end

  defp ensure_bucket do
    if System.get_env("S3_CREATE_BUCKET") in ~w(true 1) do
      load_app()
      Application.ensure_all_started(:req)

      buckets =
        Enum.reject(
          [System.get_env("S3_BUCKET"), System.get_env("BACKUP_S3_BUCKET")],
          &(&1 in [nil, ""])
        )

      for bucket <- buckets do
        case Quotor.Storage.S3.ensure_bucket(bucket) do
          :ok -> Logger.info("bucket S3 #{bucket} prêt")
          {:error, reason} -> Logger.error(reason)
        end
      end
    end
  end

  @doc """
  Crée une sauvegarde immédiatement (base + médias selon la configuration) :

      bin/quotor eval "Quotor.Release.backup()"
  """
  def backup do
    start_for_backup()

    case Quotor.Backup.run() do
      {:ok, %{name: name}} -> IO.puts("sauvegarde créée : #{name}")
      {:error, reason} -> fail(reason)
    end
  end

  @doc """
  Liste les sauvegardes disponibles :

      bin/quotor eval "Quotor.Release.backups()"
  """
  def backups do
    start_for_backup()

    for b <- Quotor.Backup.list() do
      IO.puts("#{b.name}\t#{Quotor.Backup.format_size(b.size)}")
    end

    :ok
  end

  @doc """
  Restaure une sauvegarde (nom, ou chemin d'une archive locale). **Remplace**
  la base et réécrit les médias de l'archive :

      bin/quotor eval 'Quotor.Release.restore("quotor-20261113-020000.tar")'
      bin/quotor eval 'Quotor.Release.restore("/tmp/quotor-….tar", media: false)'
  """
  def restore(ref, opts \\ []) do
    start_for_backup()

    case Quotor.Backup.restore(ref, opts) do
      {:ok, %{media_files: n}} ->
        IO.puts("restauration terminée (#{n} média(s)) — redémarrez l'application")

      {:error, reason} ->
        fail(reason)
    end
  end

  defp start_for_backup do
    load_app()
    {:ok, _} = Application.ensure_all_started([:req, :jason])
  end

  defp fail(reason) do
    IO.puts(:stderr, "échec : #{reason}")
    System.halt(1)
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _ -> Quotor.Seeds.run() end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
