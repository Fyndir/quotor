# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :quotor, :scopes,
  user: [
    default: true,
    module: Quotor.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Quotor.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :quotor,
  ecto_repos: [Quotor.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :quotor, QuotorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: QuotorWeb.ErrorHTML, json: QuotorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Quotor.PubSub,
  live_view: [signing_salt: "KdsBQqxF"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :quotor, Quotor.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  quotor: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  quotor: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :source_id]

# Stockage des médias (clips, vignettes, montages) — surchargé par MEDIA_DIR
config :quotor, :media_dir, Path.expand("../priv/media", __DIR__)

# Types MIME supplémentaires (envoi de fichiers par l'admin)
config :mime, :types, %{
  "video/x-matroska" => ["mkv"],
  "application/x-subrip" => ["srt"],
  "text/vtt" => ["vtt"]
}

# Garder les vidéos sources après découpe (sinon supprimées pour gagner de la place)
config :quotor, :keep_sources, false

# Tâches de fond : alimentation du catalogue, découpe, montages, maintenance
config :quotor, Oban,
  repo: Quotor.Repo,
  engine: Oban.Engines.Basic,
  # Notifier sans LISTEN/NOTIFY : compatible avec les poolers (Neon / PgBouncer)
  notifier: Oban.Notifiers.PG,
  queues: [default: 5, ingest: 1, media: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 3600},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(90)},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 4 * * *", Quotor.Workers.SyncChannels},
       {"30 3 * * *", Quotor.Workers.Cleanup}
     ]}
  ]

# Informations légales affichées dans les mentions légales (surchargées par
# les variables d'environnement LEGAL_*, cf. config/runtime.exs)
config :quotor, :legal,
  editor_name: "[Nom ou pseudonyme de l'éditeur]",
  editor_address:
    "[Adresse postale — peut être communiquée à l'hébergeur seul si éditeur non professionnel]",
  contact_email: "contact@quotor.example",
  publication_director: "[Nom du directeur de la publication]"

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
