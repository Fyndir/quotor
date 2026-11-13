defmodule QuotorWeb.Router do
  use QuotorWeb, :router

  import QuotorWeb.UserAuth
  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {QuotorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Santé (Render health check) et fichiers médias : sans session.
  scope "/", QuotorWeb do
    get "/health", HealthController, :show
    get "/media/*path", MediaController, :show
    # téléchargement en pièce jointe (montage, extrait)
    get "/m/:key/telecharger", DownloadController, :montage
    get "/q/:id/telecharger", DownloadController, :quote
  end

  ## Public (anonyme, utilisateur, admin)

  scope "/", QuotorWeb do
    pipe_through :browser

    get "/mentions-legales", PageController, :legal
    get "/conditions", PageController, :terms

    live_session :public, on_mount: [{QuotorWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive, :index
      live "/decouvrir", DiscoverLive, :index
      live "/auteurs", AuthorsLive, :index
      live "/auteurs/:slug", AuthorLive, :show
      live "/q/:id", QuoteLive, :show
      live "/m/:key", MontageLive, :show
      live "/signaler", ReportLive, :new
    end
  end

  ## Utilisateurs connectés

  scope "/", QuotorWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{QuotorWeb.UserAuth, :require_authenticated}] do
      live "/favoris", FavoritesLive, :index
      live "/mes-montages", MyMontagesLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Administration

  scope "/admin", QuotorWeb.Admin, as: :admin do
    pipe_through [:browser, :require_admin_user]

    live_session :admin, on_mount: [{QuotorWeb.UserAuth, :require_admin}] do
      live "/", DashboardLive, :index
      live "/sources", SourcesLive, :index
      live "/chaines", ChannelsLive, :index
      live "/auteurs", AuthorsLive, :index
      live "/quotes", QuotesLive, :index
      live "/signalements", ReportsLive, :index
      live "/utilisateurs", UsersLive, :index
      live "/logs", LogsLive, :index
      live "/sauvegardes", BackupsLive, :index
      live "/historique", HistoryLive, :index
    end

    # Téléchargement d'une archive de sauvegarde (admin uniquement)
    get "/sauvegardes/:name", BackupController, :download
  end

  scope "/admin" do
    pipe_through [:browser, :require_admin_user]

    live_dashboard "/dashboard",
      metrics: QuotorWeb.Telemetry,
      on_mount: [{QuotorWeb.UserAuth, :require_admin}]

    oban_dashboard("/oban", on_mount: [{QuotorWeb.UserAuth, :require_admin}])
  end

  # Prévisualisation des emails en dev
  if Application.compile_env(:quotor, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentification

  scope "/", QuotorWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{QuotorWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
