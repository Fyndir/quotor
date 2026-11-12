defmodule Quotor.Backup do
  @moduledoc """
  Sauvegardes de Quotor : base PostgreSQL et fichiers médias.

  Une sauvegarde est une archive tar `quotor-AAAAMMJJ-HHMMSS.tar` contenant :

    * `manifest.json` — date, version, contenu ;
    * `db.dump` — `pg_dump` au format « custom » (compressé), sans les données
      de la file de tâches Oban ;
    * `clips/`, `thumbs/`, `montages/`, `sources/` — les médias, si inclus.

  Destination (cf. `config :quotor, :backup`) :

    * `s3_bucket` défini → bucket S3/R2 **privé**, distinct de celui des
      médias (qui peut être public) ;
    * sinon dossier local `dir` (par défaut `<MEDIA_DIR>/../backups`), à
      placer sur un volume distinct des données.

  Les médias sont inclus selon `media` : `:auto` (seulement s'ils sont sur
  disque local ; en S3/R2 ils sont déjà hors du serveur), `:always` (les
  télécharge depuis le bucket) ou `:never`.

  Restauration : `restore/2`, en ligne de commande dans la release
  (`bin/quotor eval 'Quotor.Release.restore("quotor-….tar")'`).
  """

  require Logger

  alias Quotor.{Media, Storage}
  alias Quotor.Storage.S3

  @media_dirs ~w(clips thumbs montages sources)
  @name_re ~r/\Aquotor-(\d{8})-(\d{6})\.tar\z/
  @prefix "backups/"

  ## Réglages

  defp settings, do: Application.get_env(:quotor, :backup, [])

  @doc "Sauvegarde planifiée activée ?"
  def enabled?, do: Keyword.get(settings(), :enabled, true)

  @doc "Nombre de sauvegardes conservées."
  def keep, do: max(Keyword.get(settings(), :keep, 7), 1)

  @doc "Destination : `{:s3, bucket}` ou `{:local, dossier}`."
  def destination do
    case settings()[:s3_bucket] do
      bucket when is_binary(bucket) and bucket != "" ->
        {:s3, bucket}

      _ ->
        {:local,
         Path.expand(settings()[:dir] || Path.join(Path.dirname(Media.root()), "backups"))}
    end
  end

  @doc "Libellé lisible de la destination."
  def destination_label do
    case destination() do
      {:s3, bucket} -> "bucket S3 « #{bucket} »"
      {:local, dir} -> "dossier #{dir}"
    end
  end

  @doc "Les médias sont-ils inclus dans les sauvegardes ?"
  def include_media? do
    case Keyword.get(settings(), :media, :auto) do
      :always -> true
      :never -> false
      :auto -> Storage.local?()
    end
  end

  @doc "Nom de sauvegarde valide ? (protège contre les chemins arbitraires)"
  def valid_name?(name) when is_binary(name), do: Regex.match?(@name_re, name)
  def valid_name?(_), do: false

  ## Création

  @doc """
  Crée une sauvegarde et l'envoie vers la destination. Renvoie
  `{:ok, %{name, size, media_files}}` ou `{:error, raison}`.
  """
  def run(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    name = "quotor-" <> Calendar.strftime(now, "%Y%m%d-%H%M%S") <> ".tar"
    media? = Keyword.get(opts, :media, include_media?())
    work = Media.tmp_dir!("backup-#{System.unique_integer([:positive])}")
    started = System.monotonic_time(:millisecond)

    try do
      with :ok <- dump_db(Path.join(work, "db.dump")),
           {:ok, media_root, media_files} <- stage_media(media?, work),
           :ok <- write_manifest(work, now, media_files),
           archive = Path.join(work, name),
           :ok <- tar_create(archive, work, media_root),
           %File.Stat{size: size} <- File.stat!(archive),
           :ok <- put(archive, name) do
        ms = System.monotonic_time(:millisecond) - started

        Logger.info(
          "sauvegarde #{name} créée (#{format_size(size)}, #{media_files} média(s), #{ms} ms) → #{destination_label()}"
        )

        {:ok, %{name: name, size: size, media_files: media_files}}
      else
        {:error, reason} = error ->
          Logger.error("sauvegarde #{name} en échec : #{reason}")
          error
      end
    after
      File.rm_rf(work)
    end
  end

  defp dump_db(path) do
    args =
      ~w(--format=custom --no-owner --no-privileges) ++
        ~w(--exclude-table-data=oban_jobs --exclude-table-data=oban_peers) ++
        ["--file", path]

    pg("pg_dump", args)
  end

  # Médias à archiver : sur disque local, on archive directement MEDIA_DIR ;
  # en S3, on télécharge d'abord les objets dans le dossier de travail.
  defp stage_media(false, _work), do: {:ok, nil, 0}

  defp stage_media(true, work) do
    if Storage.local?() do
      root = Media.root()
      count = Enum.sum(for d <- @media_dirs, do: count_files(Path.join(root, d)))
      {:ok, root, count}
    else
      dir = Path.join(work, "media")

      keys = Enum.flat_map(@media_dirs, fn d -> Storage.adapter().list(d <> "/") end)

      keys
      |> Task.async_stream(
        fn {key, _size} -> {key, Storage.adapter().get(key, Path.join(dir, key))} end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.reduce_while({:ok, dir, 0}, fn
        {:ok, {_key, :ok}}, {:ok, dir, n} -> {:cont, {:ok, dir, n + 1}}
        {:ok, {key, {:error, r}}}, _ -> {:halt, {:error, "média #{key} : #{inspect(r)}"}}
      end)
    end
  end

  defp count_files(dir) do
    dir |> Path.join("**") |> Path.wildcard(match_dot: true) |> Enum.count(&File.regular?/1)
  end

  defp write_manifest(work, now, media_files) do
    manifest = %{
      app: "quotor",
      version: to_string(Application.spec(:quotor, :vsn)),
      created_at: DateTime.to_iso8601(now),
      database: true,
      media_files: media_files,
      storage: if(Storage.local?(), do: "local", else: "s3")
    }

    File.write(Path.join(work, "manifest.json"), Jason.encode_to_iodata!(manifest, pretty: true))
  end

  defp tar_create(archive, work, media_root) do
    media_args =
      if media_root do
        dirs = Enum.filter(@media_dirs, &File.dir?(Path.join(media_root, &1)))
        if dirs == [], do: [], else: ["-C", media_root | dirs]
      else
        []
      end

    args = ["-cf", archive, "-C", work, "manifest.json", "db.dump" | media_args]

    case System.cmd("tar", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, "tar (#{code}) : #{String.trim(out)}"}
    end
  end

  ## Liste, rétention, suppression

  @doc "Sauvegardes existantes, de la plus récente à la plus ancienne."
  def list do
    entries =
      case destination() do
        {:s3, bucket} ->
          for {key, size} <- S3.list(@prefix, bucket: bucket),
              do: {String.replace_prefix(key, @prefix, ""), size}

        {:local, dir} ->
          case File.ls(dir) do
            {:ok, files} ->
              for f <- files,
                  {:ok, %File.Stat{type: :regular, size: size}} <- [File.stat(Path.join(dir, f))],
                  do: {f, size}

            _ ->
              []
          end
      end

    entries
    |> Enum.filter(fn {name, _} -> valid_name?(name) end)
    |> Enum.map(fn {name, size} -> %{name: name, size: size, at: name_datetime(name)} end)
    |> Enum.sort_by(& &1.name, :desc)
  end

  defp name_datetime(name) do
    [_, d, t] = Regex.run(@name_re, name)

    <<y::binary-4, mo::binary-2, da::binary-2>> = d
    <<h::binary-2, mi::binary-2, s::binary-2>> = t

    case NaiveDateTime.from_iso8601("#{y}-#{mo}-#{da}T#{h}:#{mi}:#{s}") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end

  @doc "Supprime les sauvegardes au-delà des `keep/0` plus récentes."
  def prune(keep \\ keep()) do
    old = list() |> Enum.drop(keep)
    Enum.each(old, &delete(&1.name))
    if old != [], do: Logger.info("sauvegardes : #{length(old)} ancienne(s) supprimée(s)")
    length(old)
  end

  @doc "Supprime une sauvegarde."
  def delete(name) do
    true = valid_name?(name)

    case destination() do
      {:s3, bucket} -> S3.delete(@prefix <> name, bucket: bucket)
      {:local, dir} -> File.rm(Path.join(dir, name))
    end
  end

  @doc "Chemin local d'une sauvegarde (destination locale uniquement)."
  def local_path(name) do
    true = valid_name?(name)
    {:local, dir} = destination()
    Path.join(dir, name)
  end

  defp put(archive, name) do
    case destination() do
      {:s3, bucket} ->
        S3.put(archive, @prefix <> name, bucket: bucket)

      {:local, dir} ->
        File.mkdir_p!(dir)
        dest = Path.join(dir, name)

        # copie puis renommage : jamais d'archive à moitié écrite sous le bon nom
        with :ok <- File.cp(archive, dest <> ".part") do
          File.rename(dest <> ".part", dest)
        end
    end
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, "envoi de l'archive : #{inspect(reason)}"}
    end
  end

  @doc """
  Télécharge une sauvegarde de la destination vers `dest`.
  """
  def fetch(name, dest) do
    true = valid_name?(name)

    case destination() do
      {:s3, bucket} ->
        S3.get(@prefix <> name, dest, bucket: bucket)

      {:local, _} ->
        case File.cp(local_path(name), dest) do
          {:error, :enoent} -> {:error, :not_found}
          other -> other
        end
    end
  end

  ## Restauration

  @doc """
  Restaure une sauvegarde : `ref` est un nom de sauvegarde (cherchée dans la
  destination) ou le chemin d'une archive locale.

  **Remplace** le contenu de la base (`pg_restore --clean`) et réécrit les
  médias présents dans l'archive. Options : `media: false` pour ne restaurer
  que la base, `database: false` pour ne restaurer que les médias.
  """
  def restore(ref, opts \\ []) do
    work = Media.tmp_dir!("restore-#{System.unique_integer([:positive])}")

    try do
      archive = Path.join(work, "archive.tar")

      with :ok <- obtain(ref, archive),
           :ok <- tar_extract(archive, Path.join(work, "x")),
           x = Path.join(work, "x"),
           :ok <- check_manifest(x),
           :ok <- maybe_restore_db(x, Keyword.get(opts, :database, true)),
           {:ok, n} <- maybe_restore_media(x, Keyword.get(opts, :media, true)) do
        Logger.info("sauvegarde #{Path.basename(ref)} restaurée (#{n} média(s))")
        {:ok, %{media_files: n}}
      else
        {:error, reason} = error ->
          Logger.error("restauration de #{ref} en échec : #{reason}")
          error
      end
    after
      File.rm_rf(work)
    end
  end

  defp obtain(ref, archive) do
    cond do
      File.regular?(ref) ->
        File.cp(ref, archive)

      valid_name?(ref) ->
        case fetch(ref, archive) do
          :ok -> :ok
          {:error, :not_found} -> {:error, "sauvegarde #{ref} introuvable"}
          {:error, reason} -> {:error, "téléchargement : #{inspect(reason)}"}
        end

      true ->
        {:error, "ni un fichier, ni un nom de sauvegarde : #{ref}"}
    end
  end

  defp tar_extract(archive, dir) do
    File.mkdir_p!(dir)

    case System.cmd("tar", ["-xf", archive, "-C", dir, "--no-same-owner"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, "tar (#{code}) : #{String.trim(out)}"}
    end
  end

  defp check_manifest(dir) do
    with {:ok, json} <- File.read(Path.join(dir, "manifest.json")),
         {:ok, %{"app" => "quotor"}} <- Jason.decode(json) do
      :ok
    else
      _ -> {:error, "archive invalide (manifest.json absent ou incorrect)"}
    end
  end

  defp maybe_restore_db(_dir, false), do: :ok

  defp maybe_restore_db(dir, true) do
    dump = Path.join(dir, "db.dump")

    if File.regular?(dump) do
      pg(
        "pg_restore",
        ~w(--clean --if-exists --no-owner --no-privileges --single-transaction --exit-on-error) ++
          ["--dbname", pg_database(), dump]
      )
    else
      {:error, "db.dump absent de l'archive"}
    end
  end

  defp maybe_restore_media(_dir, false), do: {:ok, 0}

  defp maybe_restore_media(dir, true) do
    files =
      for d <- @media_dirs,
          path <- Path.wildcard(Path.join([dir, d, "**"]), match_dot: true),
          File.regular?(path),
          do: {path, Path.relative_to(path, dir)}

    if Storage.local?() do
      Enum.each(files, fn {path, key} ->
        dest = Path.join(Media.root(), key)
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
      end)

      {:ok, length(files)}
    else
      files
      |> Task.async_stream(fn {path, key} -> {key, Storage.adapter().put(path, key, [])} end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.reduce_while({:ok, 0}, fn
        {:ok, {_key, :ok}}, {:ok, n} -> {:cont, {:ok, n + 1}}
        {:ok, {key, {:error, r}}}, _ -> {:halt, {:error, "média #{key} : #{inspect(r)}"}}
      end)
    end
  end

  ## PostgreSQL

  # Lance pg_dump / pg_restore avec les paramètres de connexion du Repo,
  # passés par variables d'environnement (le mot de passe n'apparaît pas
  # dans la liste des processus).
  defp pg(cmd, args) do
    case System.find_executable(cmd) do
      nil ->
        {:error, "#{cmd} introuvable (installer le client PostgreSQL)"}

      exe ->
        case System.cmd(exe, args, env: pg_env(), stderr_to_stdout: true) do
          {_, 0} ->
            :ok

          {out, code} ->
            {:error, "#{cmd} (#{code}) : #{out |> String.trim() |> String.slice(0, 500)}"}
        end
    end
  end

  defp repo_config do
    config = Quotor.Repo.config()

    case config[:url] do
      url when is_binary(url) -> Keyword.merge(config, Ecto.Repo.Supervisor.parse_url(url))
      _ -> config
    end
  end

  defp pg_database, do: to_string(repo_config()[:database])

  @doc false
  def pg_env do
    c = repo_config()

    [
      {"PGHOST", c[:socket_dir] || c[:hostname] || "localhost"},
      {"PGPORT", to_string(c[:port] || 5432)},
      {"PGUSER", to_string(c[:username] || "postgres")},
      {"PGPASSWORD", to_string(c[:password] || "")},
      {"PGDATABASE", to_string(c[:database])}
    ] ++
      if c[:ssl] not in [nil, false] do
        # vérification du certificat avec les autorités du système (libpq ≥ 16)
        [{"PGSSLMODE", "verify-full"}, {"PGSSLROOTCERT", "system"}]
      else
        [{"PGSSLMODE", "prefer"}]
      end
  end

  ## Utilitaires

  @doc "Taille lisible (o, Ko, Mo, Go)."
  def format_size(bytes) when bytes < 1024, do: "#{bytes} o"
  def format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} Ko"

  def format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)} Mo"

  def format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} Go"
end
