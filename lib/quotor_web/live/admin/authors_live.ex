defmodule QuotorWeb.Admin.AuthorsLive do
  @moduledoc """
  Gestion des auteurs : personnes qui parlent et chaînes YouTube.

  Les chaînes sont créées automatiquement à l'ingestion ; l'admin peut ajouter
  des personnes, puis les attribuer à une vidéo entière (page « Vidéos
  sources ») ou à une quote précise (page « Quotes »).
  """
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.Catalog
  alias Quotor.Catalog.Author

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:authors}>
      <h1 class="text-2xl font-black mb-2">Auteurs</h1>
      <p class="text-sm text-base-content/60 mb-6">
        Chaque vidéo a un auteur par défaut (sa chaîne YouTube, créée automatiquement) ; chaque
        quote peut avoir son propre auteur, par exemple la personne qui parle. Attribuez-les depuis
        <.link navigate={~p"/admin/sources"} class="link">Vidéos sources</.link>
        et <.link navigate={~p"/admin/quotes"} class="link">Quotes</.link>.
      </p>

      <section class="rounded-2xl bg-base-200 p-5 mb-6">
        <h2 class="font-bold mb-3">
          {if @editing, do: "Modifier « #{@editing.name} »", else: "Nouvel auteur"}
        </h2>
        <.form for={@form} id="author-form" phx-change="validate" phx-submit="save">
          <div class="grid gap-3 sm:grid-cols-[2fr_1fr_2fr]">
            <.input field={@form[:name]} type="text" label="Nom" />
            <.input
              field={@form[:kind]}
              type="select"
              label="Type"
              options={Enum.map(Author.kinds(), &{Author.kind_label(&1), &1})}
            />
            <.input field={@form[:url]} type="url" label="Lien (chaîne, site…)" />
          </div>
          <.input field={@form[:description]} type="textarea" label="Description" rows="2" />
          <div class="flex gap-2">
            <.button class="btn btn-primary btn-sm">
              {if @editing, do: "Enregistrer", else: "Ajouter"}
            </.button>
            <button :if={@editing} type="button" phx-click="cancel" class="btn btn-ghost btn-sm">
              Annuler
            </button>
          </div>
        </.form>
      </section>

      <div class="overflow-x-auto rounded-2xl bg-base-200">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Auteur</th>
              <th>Type</th>
              <th>Quotes</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={author <- @authors} id={"admin-author-#{author.id}"}>
              <td>
                <.link navigate={~p"/auteurs/#{author.slug}"} class="font-semibold hover:underline">
                  {author.name}
                </.link>
                <a
                  :if={author.url}
                  href={author.url}
                  target="_blank"
                  rel="noopener"
                  class="block text-xs link text-base-content/60 truncate max-w-xs"
                >
                  {author.url}
                </a>
              </td>
              <td><span class="badge badge-sm">{Author.kind_label(author.kind)}</span></td>
              <td>{Map.get(@counts, author.id, 0)}</td>
              <td class="text-right whitespace-nowrap">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={author.id}
                  class="btn btn-xs btn-ghost"
                  title="Modifier"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={author.id}
                  data-confirm="Supprimer cet auteur ? Ses quotes resteront, sans auteur."
                  class="btn btn-xs btn-ghost text-error"
                  title="Supprimer"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@authors == []} class="p-6 text-center text-base-content/60">Aucun auteur.</p>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Auteurs", editing: nil) |> reset_form() |> load()}
  end

  @impl true
  def handle_event("validate", %{"author" => params}, socket) do
    cs =
      (socket.assigns.editing || %Author{})
      |> Catalog.change_author(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(cs))}
  end

  def handle_event("save", %{"author" => params}, socket) do
    result =
      case socket.assigns.editing do
        nil -> Catalog.create_author(params)
        author -> Catalog.update_author(author, params)
      end

    case result do
      {:ok, author} ->
        Logger.info("admin : auteur #{author.name} enregistré")

        {:noreply,
         socket
         |> put_flash(:info, "Auteur « #{author.name} » enregistré.")
         |> assign(editing: nil)
         |> reset_form()
         |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    author = Catalog.get_author!(id)
    {:noreply, assign(socket, editing: author, form: to_form(Catalog.change_author(author)))}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(editing: nil) |> reset_form()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    author = Catalog.get_author!(id)
    {:ok, _} = Catalog.delete_author(author)
    Logger.info("admin : auteur #{author.name} supprimé")
    {:noreply, socket |> assign(editing: nil) |> reset_form() |> load()}
  end

  defp reset_form(socket), do: assign(socket, form: to_form(Catalog.change_author(%Author{})))

  defp load(socket) do
    assign(socket,
      authors: Catalog.list_authors(),
      counts: Catalog.count_quotes_by_author()
    )
  end
end
