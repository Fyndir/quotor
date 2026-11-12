defmodule QuotorWeb.AuthorsLive do
  @moduledoc "Liste publique des auteurs (personnes et chaînes) ayant des répliques."
  use QuotorWeb, :live_view

  alias Quotor.Catalog
  alias Quotor.Catalog.Author

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <h1 class="text-3xl font-black">Auteurs</h1>
      <p class="text-base-content/70 mb-6">
        Les personnes qui parlent dans les extraits, ou à défaut la chaîne qui a publié la vidéo.
      </p>

      <p :if={@authors == []} class="rounded-2xl bg-base-200 p-10 text-center text-base-content/70">
        Aucun auteur pour l'instant.
      </p>

      <ul id="authors" class="grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        <li :for={{author, count} <- @authors} id={"author-#{author.id}"}>
          <.link
            navigate={~p"/auteurs/#{author.slug}"}
            class="flex items-center gap-3 rounded-2xl bg-base-200 p-4 ring-1 ring-base-300 hover:ring-primary/60 transition"
          >
            <span class="grid place-items-center size-11 shrink-0 rounded-full bg-primary text-primary-content font-black text-lg">
              {initial(author.name)}
            </span>
            <span class="min-w-0">
              <span class="block font-semibold truncate">{author.name}</span>
              <span class="block text-xs text-base-content/60">
                {Author.kind_label(author.kind)} · {count} réplique{if count > 1, do: "s"}
              </span>
            </span>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Auteurs", authors: Catalog.list_public_authors())}
  end

  def initial(name), do: name |> String.trim() |> String.first() |> String.upcase()
end
