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

if media_dir = System.get_env("MEDIA_DIR") do
  config :quotor, :media_dir, media_dir
end

if System.get_env("KEEP_SOURCES") in ~w(true 1) do
  config :quotor, :keep_sources, true
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
