defmodule QuotorWeb.DiscoverLive do
  @moduledoc """
  Onglet « Découvrir » : parcourir le catalogue sans chercher, au hasard, par
  nouveautés ou par popularité.
  """
  use QuotorWeb, :live_view

  alias Quotor.Catalog
  alias Quotor.Accounts.Scope

  @page_size 24
  @sorts [
    {"hasard", "Au hasard", "hero-sparkles"},
    {"recents", "Nouveautés", "hero-clock"},
    {"populaires", "Populaires", "hero-fire"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="flex flex-wrap items-end justify-between gap-4 mb-6">
        <div>
          <h1 class="text-3xl font-black">Découvrir</h1>
          <p class="text-base-content/70">
            Pas d'idée ? Clique sur un extrait pour l'écouter.
          </p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <div class="inline-flex rounded-full bg-base-200 p-1 text-sm" role="tablist">
            <.link
              :for={{sort, label, icon} <- @sorts}
              patch={~p"/decouvrir?#{%{tri: sort}}"}
              role="tab"
              aria-selected={to_string(@sort == sort)}
              class={[
                "flex items-center gap-1.5 rounded-full px-4 py-1.5 transition-colors",
                if(@sort == sort,
                  do: "bg-primary text-primary-content font-semibold shadow",
                  else: "hover:bg-base-300"
                )
              ]}
            >
              <.icon name={icon} class="size-4" /> {label}
            </.link>
          </div>
          <button
            :if={@sort == "hasard"}
            type="button"
            phx-click="shuffle"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Mélanger
          </button>
        </div>
      </div>

      <div
        id="discover"
        phx-update="stream"
        class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <div
          id="discover-empty"
          class="hidden only:block col-span-full rounded-2xl bg-base-200 p-10 text-center text-base-content/70"
        >
          Le catalogue est encore vide : les extraits arrivent en arrière-plan dès qu'un
          administrateur ajoute des vidéos.
        </div>
        <.quote_card
          :for={{dom_id, quote} <- @streams.quotes}
          id={dom_id}
          quote={quote}
          favorite={MapSet.member?(@favorites, quote.id)}
          can_favorite={@can_favorite}
        />
      </div>

      <div :if={@has_more} class="mt-8 text-center">
        <button type="button" phx-click="more" class="btn btn-ghost">Voir plus</button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Découvrir",
       sorts: @sorts,
       sort: "hasard",
       offset: 0,
       has_more: false,
       favorites: MapSet.new(),
       can_favorite: Scope.user?(socket.assigns.current_scope)
     )
     |> stream(:quotes, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort = if params["tri"] in Enum.map(@sorts, &elem(&1, 0)), do: params["tri"], else: "hasard"
    {:noreply, socket |> assign(sort: sort, offset: 0) |> load(reset: true)}
  end

  @impl true
  def handle_event("shuffle", _params, socket) do
    {:noreply, load(socket, reset: true)}
  end

  def handle_event("more", _params, socket) do
    {:noreply, socket |> assign(offset: socket.assigns.offset + @page_size) |> load(reset: false)}
  end

  def handle_event("toggle_favorite", %{"id" => id}, socket) do
    id = String.to_integer(id)
    scope = socket.assigns.current_scope

    if Scope.user?(scope) do
      favorites =
        case Catalog.toggle_favorite(scope, id) do
          :added -> MapSet.put(socket.assigns.favorites, id)
          :removed -> MapSet.delete(socket.assigns.favorites, id)
        end

      socket = assign(socket, favorites: favorites)

      case Catalog.get_public_quote(id) do
        nil -> {:noreply, socket}
        quote -> {:noreply, stream_insert(socket, :quotes, quote)}
      end
    else
      {:noreply, put_flash(socket, :error, "Connecte-toi pour garder tes favoris.")}
    end
  end

  defp load(socket, reset: reset?) do
    %{sort: sort, offset: offset} = socket.assigns

    quotes =
      case sort do
        "hasard" -> Catalog.random_quotes(@page_size)
        "recents" -> Catalog.latest_quotes(@page_size + 1, offset)
        "populaires" -> Catalog.popular_quotes(@page_size + 1, offset)
      end

    page = Enum.take(quotes, @page_size)
    ids = Catalog.favorite_ids(socket.assigns.current_scope, Enum.map(page, & &1.id))

    socket
    |> assign(
      has_more: sort != "hasard" and length(quotes) > @page_size,
      favorites: if(reset?, do: ids, else: MapSet.union(socket.assigns.favorites, ids))
    )
    |> stream(:quotes, page, reset: reset?)
  end
end
