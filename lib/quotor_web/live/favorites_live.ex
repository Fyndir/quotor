defmodule QuotorWeb.FavoritesLive do
  @moduledoc "Favoris de l'utilisateur connecté."
  use QuotorWeb, :live_view

  alias Quotor.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <h1 class="text-3xl font-black mb-6">Mes favoris</h1>
      <div
        id="favorites"
        phx-update="stream"
        class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <div
          id="favorites-empty"
          class="hidden only:block col-span-full rounded-2xl bg-base-200 p-10 text-center text-base-content/70"
        >
          Pas encore de favori. Clique sur le cœur d'un extrait pour le retrouver ici.
        </div>
        <.quote_card
          :for={{dom_id, quote} <- @streams.favorites}
          id={dom_id}
          quote={quote}
          favorite
          can_favorite
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    favorites = Catalog.list_favorites(socket.assigns.current_scope)
    {:ok, socket |> assign(page_title: "Mes favoris") |> stream(:favorites, favorites)}
  end

  @impl true
  def handle_event("toggle_favorite", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Catalog.toggle_favorite(socket.assigns.current_scope, id) do
      :removed -> {:noreply, stream_delete_by_dom_id(socket, :favorites, "favorites-#{id}")}
      :added -> {:noreply, socket}
    end
  end
end
