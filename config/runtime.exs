import Config

# config/runtime.exs est exécuté au démarrage, y compris dans les releases.
# Toute la configuration de production passe par des variables d'environnement
# (cf. README.md, section « Variables d'environnement »).

if System.get_env("PHX_SERVER") do
  config :quotor, QuotorWeb.Endpoint, server: true
end

config :quotor, QuotorWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :quotor, QuotorWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"priv/gettext/.*\.po$"E,
        ~r"lib/quotor_web/router\.ex$"E,
        ~r"lib/quotor_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

# Jamais en test : les tests utilisent (et nettoient) un dossier temporaire dédié.
media_dir = System.get_env("MEDIA_DIR")

if config_env() != :test and media_dir do
  config :quotor, :media_dir, media_dir
end

# Stockage objet S3 / Cloudflare R2 (sinon : disque local sous MEDIA_DIR).
# Indispensable si le site et les workers tournent sur des machines différentes.
s3_bucket = System.get_env("S3_BUCKET", "")
backup_bucket = System.get_env("BACKUP_S3_BUCKET", "")

if config_env() != :test and s3_bucket != "" do
  config :quotor, :storage, :s3
end

# Identifiants S3 : pour les médias (S3_BUCKET) et/ou les sauvegardes (BACKUP_S3_BUCKET).
if config_env() != :test and (s3_bucket != "" or backup_bucket != "") do
  config :quotor, :s3,
    bucket: s3_bucket,
    endpoint:
      System.get_env("S3_ENDPOINT") ||
        raise("S3_ENDPOINT manquant (ex. https://<compte>.r2.cloudflarestorage.com)"),
    region: System.get_env("S3_REGION", "auto"),
    access_key_id: System.fetch_env!("S3_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("S3_SECRET_ACCESS_KEY"),
    public_url: System.get_env("S3_PUBLIC_URL")
end

# Sauvegardes (base + médias), cf. Quotor.Backup. Destination : bucket privé
# BACKUP_S3_BUCKET s'il est défini, sinon le dossier BACKUP_DIR.
if config_env() != :test do
  backup =
    [
      enabled: System.get_env("BACKUP_ENABLED", "true") not in ~w(false 0),
      keep: String.to_integer(System.get_env("BACKUP_KEEP", "7")),
      media:
        case System.get_env("BACKUP_MEDIA", "auto") do
          "always" -> :always
          "never" -> :never
          "auto" -> :auto
          other -> raise "BACKUP_MEDIA invalide : #{inspect(other)} (auto, always ou never)"
        end
    ] ++
      if(dir = System.get_env("BACKUP_DIR"), do: [dir: dir], else: []) ++
      if(backup_bucket != "", do: [s3_bucket: backup_bucket], else: [])

  config :quotor, :backup, backup
end

# Rôle du nœud :
#   all    — site + tâches de fond (défaut, une seule machine)
#   web    — site uniquement : les tâches sont mises en file, pas exécutées
#   worker — tâches de fond uniquement (alimentation, découpe), sans serveur HTTP
role = System.get_env("ROLE", "all")

unless role in ~w(all web worker) do
  raise "ROLE invalide : #{inspect(role)} (attendu : all, web ou worker)"
end

config :quotor, :role, String.to_atom(role)

if role == "web" and config_env() != :test do
  # `false` et non `[]` : la configuration fusionne les listes, `[]` ne remplacerait rien
  config :quotor, Oban, queues: false
end

if role == "worker" do
  config :quotor, QuotorWeb.Endpoint, server: false

  if concurrency = System.get_env("WORKER_MEDIA_CONCURRENCY") do
    config :quotor, Oban, queues: [default: 5, ingest: 1, media: String.to_integer(concurrency)]
  end
end

if System.get_env("KEEP_SOURCES") in ~w(true 1) do
  config :quotor, :keep_sources, true
end

# Transcription vocale (whisper.cpp) : vérifie et recale les quotes tirées des
# sous-titres, et crée celles des vidéos sans sous-titres.
if config_env() != :test do
  config :quotor, :transcription,
    enabled:
      (case System.get_env("TRANSCRIBE", "auto") do
         v when v in ~w(true 1) -> true
         v when v in ~w(false 0) -> false
         "auto" -> :auto
         other -> raise "TRANSCRIBE invalide : #{inspect(other)} (auto, true ou false)"
       end),
    min_score: System.get_env("TRANSCRIBE_MIN_SCORE", "0.75") |> Float.parse() |> elem(0)

  config :quotor,
         :whisper,
         [
           path: System.get_env("WHISPER_PATH", "whisper-cli"),
           model: System.get_env("WHISPER_MODEL", "small"),
           language: System.get_env("WHISPER_LANGUAGE", "fr"),
           vad: System.get_env("WHISPER_VAD", "false") in ~w(true 1)
         ] ++
           if(t = System.get_env("WHISPER_THREADS"),
             do: [threads: String.to_integer(t)],
             else: []
           ) ++
           if(d = System.get_env("WHISPER_MODELS_DIR"), do: [models_dir: d], else: [])
end

legal =
  [
    editor_name: System.get_env("LEGAL_EDITOR_NAME"),
    editor_address: System.get_env("LEGAL_EDITOR_ADDRESS"),
    contact_email: System.get_env("LEGAL_CONTACT_EMAIL"),
    publication_director: System.get_env("LEGAL_PUBLICATION_DIRECTOR")
  ]
  |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

if legal != [] do
  config :quotor, :legal, Keyword.merge(Application.get_env(:quotor, :legal, []), legal)
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      (l'image Docker démarre une base PostgreSQL interne si elle est absente)
      """

  # Les URLs Neon ressemblent à
  #   postgresql://user:pass@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require
  # On retire la query string (non comprise par Postgrex) et on active TLS avec
  # vérification du certificat si sslmode=require|verify-full ou DATABASE_SSL=true.
  uri = URI.parse(database_url)
  query = URI.decode_query(uri.query || "")

  ssl? =
    System.get_env("DATABASE_SSL") in ~w(true 1) or
      query["sslmode"] in ~w(require verify-ca verify-full) or
      query["ssl"] == "true"

  ssl_opts =
    if ssl? do
      host = String.to_charlist(uri.host)

      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: host,
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    else
      false
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :quotor, Quotor.Repo,
    url: URI.to_string(%{uri | query: nil}),
    ssl: ssl_opts,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # Compatible avec le pooler Neon (PgBouncer en mode transaction)
    prepare: if(System.get_env("DATABASE_POOLER") in ~w(true 1), do: :unnamed, else: :named),
    socket_options: maybe_ipv6

  # Notifications entre nœuds (site → workers) : LISTEN/NOTIFY PostgreSQL,
  # sauf derrière un pooler en mode transaction, qui ne le supporte pas
  # (les workers découvrent alors les nouvelles tâches par interrogation).
  unless System.get_env("DATABASE_POOLER") in ~w(true 1) do
    config :quotor, Oban, notifier: Oban.Notifiers.Postgres
  end

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Render fournit RENDER_EXTERNAL_HOSTNAME automatiquement.
  host = System.get_env("PHX_HOST") || System.get_env("RENDER_EXTERNAL_HOSTNAME") || "localhost"
  local? = host in ["localhost", "127.0.0.1"]
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :quotor, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :quotor, QuotorWeb.Endpoint,
    url:
      if(local?,
        do: [host: host, port: port, scheme: "http"],
        else: [host: host, port: 443, scheme: "https"]
      ),
    check_origin: if(local?, do: false, else: ["https://#{host}"]),
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base

  # Emails (liens de connexion, changement d'email). Sans SMTP, les emails sont
  # simplement journalisés : l'inscription par mot de passe fonctionne sans.
  if smtp_host = System.get_env("SMTP_HOST") do
    config :quotor, Quotor.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: String.to_integer(System.get_env("SMTP_PORT", "587")),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always,
      auth: :always,
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        depth: 99
      ]
  else
    config :quotor, Quotor.Mailer, adapter: Swoosh.Adapters.Logger, level: :info
  end

  config :quotor, :mail_from, System.get_env("MAIL_FROM", "noreply@#{host}")

  if level = System.get_env("LOG_LEVEL") do
    config :logger, level: String.to_existing_atom(level)
  end
end
