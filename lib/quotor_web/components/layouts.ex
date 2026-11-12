defmodule QuotorWeb.Layouts do
  @moduledoc """
  Layouts de l'application : `app/1` (site public) et `admin/1` (back-office).
  """
  use QuotorWeb, :html

  alias Quotor.Accounts.Scope

  embed_templates "layouts/*"

  @doc """
  Layout principal : en-tête avec navigation selon le profil (anonyme,
  utilisateur, admin), contenu, pied de page légal (copyright, parodie).
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false, doc: "contenu pleine largeur"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.site_header current_scope={@current_scope} />

      <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
        <div class={["mx-auto", if(@wide, do: "max-w-7xl", else: "max-w-5xl")]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <.site_footer />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc "Layout du back-office admin (navigation latérale)."
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :active, :atom, required: true
  slot :inner_block, required: true

  def admin(assigns) do
    assigns =
      assign(assigns, :links, [
        {:dashboard, ~p"/admin", "hero-chart-bar", "Supervision"},
        {:sources, ~p"/admin/sources", "hero-film", "Vidéos sources"},
        {:channels, ~p"/admin/chaines", "hero-tv", "Chaînes suivies"},
        {:quotes, ~p"/admin/quotes", "hero-chat-bubble-bottom-center-text", "Quotes"},
        {:reports, ~p"/admin/signalements", "hero-flag", "Signalements"},
        {:users, ~p"/admin/utilisateurs", "hero-users", "Utilisateurs"},
        {:logs, ~p"/admin/logs", "hero-command-line", "Logs"}
      ])

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.site_header current_scope={@current_scope} />

      <div class="flex-1 mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 lg:px-8 lg:flex lg:gap-8">
        <nav class="lg:w-56 shrink-0 mb-6 lg:mb-0" aria-label="Administration">
          <p class="text-xs uppercase tracking-widest text-base-content/50 mb-3 px-3">Admin</p>
          <ul class="flex lg:flex-col gap-1 overflow-x-auto">
            <li :for={{key, path, icon, label} <- @links}>
              <.link
                navigate={path}
                class={[
                  "flex items-center gap-2 rounded-lg px-3 py-2 text-sm whitespace-nowrap transition-colors",
                  if(@active == key,
                    do: "bg-primary text-primary-content font-semibold",
                    else: "hover:bg-base-200"
                  )
                ]}
              >
                <.icon name={icon} class="size-4" /> {label}
              </.link>
            </li>
            <li class="lg:mt-4">
              <a
                href={~p"/admin/oban"}
                class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200 whitespace-nowrap"
              >
                <.icon name="hero-queue-list" class="size-4" /> Jobs (Oban)
              </a>
            </li>
            <li>
              <a
                href={~p"/admin/dashboard"}
                class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200 whitespace-nowrap"
              >
                <.icon name="hero-cpu-chip" class="size-4" /> LiveDashboard
              </a>
            </li>
          </ul>
        </nav>

        <main class="flex-1 min-w-0">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, default: nil

  defp site_header(assigns) do
    assigns = assign(assigns, :profile, Scope.profile(assigns.current_scope))

    ~H"""
    <header class="border-b border-base-300/60 bg-base-100/80 backdrop-blur sticky top-0 z-30">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 h-16 flex items-center gap-4">
        <.link navigate={~p"/"} class="flex items-center gap-2 group" aria-label="Accueil Quotor">
          <span class="grid place-items-center size-9 rounded-xl bg-primary text-primary-content font-black text-lg shadow-sm group-hover:rotate-[-6deg] transition-transform">
            “
          </span>
          <span class="font-black text-xl tracking-tight">Quotor</span>
        </.link>

        <nav class="ml-auto flex items-center gap-1 text-sm" aria-label="Navigation principale">
          <.link :if={@profile != :anonymous} navigate={~p"/favoris"} class="nav-link">
            <.icon name="hero-heart" class="size-4" />
            <span class="hidden sm:inline">Favoris</span>
          </.link>
          <.link :if={@profile != :anonymous} navigate={~p"/mes-montages"} class="nav-link">
            <.icon name="hero-film" class="size-4" />
            <span class="hidden sm:inline">Mes montages</span>
          </.link>
          <.link :if={@profile == :admin} navigate={~p"/admin"} class="nav-link text-primary">
            <.icon name="hero-shield-check" class="size-4" />
            <span class="hidden sm:inline">Admin</span>
          </.link>

          <%= if @profile == :anonymous do %>
            <.link navigate={~p"/users/log-in"} class="nav-link">Connexion</.link>
            <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm rounded-full">
              Créer un compte
            </.link>
          <% else %>
            <div class="dropdown dropdown-end">
              <div
                tabindex="0"
                role="button"
                class="nav-link"
                aria-label="Mon compte"
              >
                <.icon name="hero-user-circle" class="size-5" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu bg-base-200 rounded-box z-40 mt-2 w-60 p-2 shadow-lg"
              >
                <li class="menu-title truncate">{@current_scope.user.email}</li>
                <li><.link navigate={~p"/users/settings"}>Paramètres</.link></li>
                <li><.link href={~p"/users/log-out"} method="delete">Déconnexion</.link></li>
              </ul>
            </div>
          <% end %>
          <div class="hidden md:block ml-2"><.theme_toggle /></div>
        </nav>
      </div>
    </header>
    """
  end

  defp site_footer(assigns) do
    ~H"""
    <footer class="border-t border-base-300/60 mt-12">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 text-sm text-base-content/60 space-y-3">
        <div class="flex flex-wrap gap-x-6 gap-y-2">
          <.link navigate={~p"/mentions-legales"} class="hover:text-base-content">
            Mentions légales
          </.link>
          <.link navigate={~p"/conditions"} class="hover:text-base-content">
            Conditions d'utilisation &amp; droit d'auteur
          </.link>
          <.link navigate={~p"/signaler"} class="hover:text-base-content">
            Signaler un contenu
          </.link>
        </div>
        <p>
          © {Date.utc_today().year} Quotor. Les extraits vidéo restent la propriété de leurs auteurs
          et ayants droit respectifs ; ils sont proposés à des fins exclusivement parodiques et
          humoristiques (art. L. 122-5, 4° du Code de la propriété intellectuelle). Quotor n'est
          affilié à aucun des créateurs cités.
        </p>
      </div>
    </footer>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connexion perdue")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnexion en cours")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Une erreur est survenue")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnexion en cours")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
