defmodule QuotorWeb.AuthorLive do
  @moduledoc "Page d'un auteur : ses répliques (les plus vues d'abord)."
  use QuotorWeb, :live_view

  alias Quotor.Catalog
  alias Quotor.Catalog.Author
  alias Quotor.Accounts.Scope

  @page_size 24

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <.link navigate={~p"/auteurs"} class="text-sm text-base-content/60 hover:text-base-content">
        <.icon name="hero-arrow-left-micro" class="size-4" /> Tous les auteurs
      </.link>

      <div class="flex flex-wrap items-center gap-4 mt-3 mb-8">
        <span class="grid place-items-center size-16 rounded-full bg-primary text-primary-content font-black text-2xl">
          {QuotorWeb.AuthorsLive.initial(@author.name)}
        </span>
        <div class="min-w-0 flex-1">
          <h1 class="text-3xl font-black">{@author.name}</h1>
          <p class="text-sm text-base-content/60">{Author.kind_label(@author.kind)}</p>
          <p :if={@author.description} class="mt-1 text-base-content/80">{@author.description}</p>
        </div>
        <a
          :if={@author.url}
          href={@author.url}
          target="_blank"
          rel="noopener"
          class="btn btn-outline btn-sm"
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-4" />
          {if @author.kind == "channel", do: "Voir la chaîne", else: "Lien officiel"}
        </a>
      </div>

      <div
        id="author-quotes"
        phx-update="stream"
        class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <div
          id="author-quotes-empty"
          class="hidden only:block col-span-full rounded-2xl bg-base-200 p-10 text-center text-base-content/70"
        >
          Aucune réplique disponible pour cet auteur.
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
  def mount(%{"slug" => slug}, _session, socket) do
    case Catalog.get_author_by_slug(slug) do
      nil ->
        raise QuotorWeb.NotFoundError

      author ->
        {:ok,
         socket
         |> assign(
           page_title: author.name,
           author: author,
           offset: 0,
           favorites: MapSet.new(),
           can_favorite: Scope.user?(socket.assigns.current_scope)
         )
         |> stream(:quotes, [])
         |> load(true)}
    end
  end

  @impl true
  def handle_event("more", _params, socket) do
    {:noreply, socket |> assign(offset: socket.assigns.offset + @page_size) |> load(false)}
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

  defp load(socket, reset?) do
    quotes = Catalog.author_quotes(socket.assigns.author, @page_size + 1, socket.assigns.offset)
    page = Enum.take(quotes, @page_size)
    ids = Catalog.favorite_ids(socket.assigns.current_scope, Enum.map(page, & &1.id))

    socket
    |> assign(
      has_more: length(quotes) > @page_size,
      favorites: if(reset?, do: ids, else: MapSet.union(socket.assigns.favorites, ids))
    )
    |> stream(:quotes, page, reset: reset?)
  end
end
