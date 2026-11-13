defmodule QuotorWeb.MontageLive do
  @moduledoc "Page partageable d'un montage."
  use QuotorWeb, :live_view

  alias Quotor.Montages

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <h1 class="text-2xl sm:text-3xl font-extrabold mb-6">« {@montage.query} »</h1>
        <.montage_player montage={@montage} />
        <p class="mt-4 text-xs text-base-content/50">
          Montage parodique composé d'extraits de leurs auteurs respectifs — les personnes
          apparaissant n'ont pas réellement prononcé cette phrase.
        </p>
        <div
          :if={@owner?}
          id="montage-listing"
          class="mt-6 flex flex-wrap items-center gap-3 rounded-2xl bg-base-200 p-4 text-sm"
        >
          <.icon
            name={if @montage.listed, do: "hero-globe-europe-africa", else: "hero-lock-closed"}
            class="size-5 text-base-content/60"
          />
          <span class="flex-1">
            <%= if @montage.listed do %>
              Ton montage est visible dans <.link navigate={~p"/decouvrir"} class="link">Découvrir</.link>.
            <% else %>
              Ton montage n'apparaît pas dans Découvrir (le lien reste partageable).
            <% end %>
          </span>
          <button
            id="toggle-listed"
            type="button"
            phx-click="toggle_listed"
            class="btn btn-sm btn-ghost"
          >
            {if @montage.listed, do: "Retirer de Découvrir", else: "Afficher dans Découvrir"}
          </button>
        </div>
        <div class="mt-6 flex gap-2">
          <.link navigate={~p"/?#{%{q: @montage.query, mode: "advanced"}}"} class="btn btn-ghost">
            <.icon name="hero-scissors" class="size-4" /> Faire le mien
          </.link>
          <.link navigate={~p"/signaler?#{%{montage: @montage.key}}"} class="btn btn-ghost btn-sm">
            <.icon name="hero-flag" class="size-4" /> Signaler
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    case Montages.get_by_key(key) do
      nil ->
        raise QuotorWeb.NotFoundError

      montage ->
        if connected?(socket), do: Montages.increment_views(montage)

        {:ok,
         assign(socket,
           montage: montage,
           owner?: Montages.owner?(montage, socket.assigns.current_scope),
           page_title: montage.query,
           og: QuotorWeb.OpenGraph.for_montage(montage)
         )}
    end
  end

  @impl true
  def handle_event("toggle_listed", _params, socket) do
    %{montage: montage, current_scope: scope} = socket.assigns

    case Montages.set_listed(montage, scope, !montage.listed) do
      {:ok, montage} -> {:noreply, assign(socket, montage: montage)}
      {:error, _} -> {:noreply, socket}
    end
  end
end
