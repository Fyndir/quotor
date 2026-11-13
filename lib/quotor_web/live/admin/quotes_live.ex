defmodule QuotorWeb.Admin.QuotesLive do
  @moduledoc """
  Modération des quotes : correction du texte, masquage, et validation des
  quotes « à vérifier » (texte et parole divergent, cf. transcription vocale).
  """
  use QuotorWeb, :live_view

  alias Quotor.{Catalog, Media, Text}
  alias Quotor.Catalog.Quote

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:quotes}>
      <h1 class="text-2xl font-black mb-4">Quotes</h1>

      <.form
        for={@filter}
        id="quote-filter"
        phx-change="filter"
        phx-submit="filter"
        class="mb-4 flex gap-2"
      >
        <input
          type="search"
          name="search"
          value={@filter[:search].value}
          placeholder="Filtrer par texte…"
          phx-debounce="300"
          class="input input-sm flex-1"
        />
        <input :if={@source_id} type="hidden" name="source_id" value={@source_id} />
        <input :if={@review?} type="hidden" name="review" value="1" />
        <.link
          id="review-filter"
          patch={if @review?, do: ~p"/admin/quotes", else: ~p"/admin/quotes?review=1"}
          class={["btn btn-sm", if(@review?, do: "btn-warning", else: "btn-ghost")]}
        >
          <.icon name="hero-exclamation-triangle" class="size-4" /> À vérifier
          <span class="badge badge-sm">{@to_review}</span>
        </.link>
        <.link :if={@source_id} patch={~p"/admin/quotes"} class="btn btn-sm btn-ghost">
          Source n° {@source_id} <.icon name="hero-x-mark" class="size-4" />
        </.link>
      </.form>

      <div class="overflow-x-auto rounded-2xl bg-base-200">
        <table class="table table-sm">
          <thead>
            <tr>
              <th></th>
              <th>Texte</th>
              <th>Source</th>
              <th>Auteur</th>
              <th>Statut</th>
              <th>Vues</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={quote <- @quotes}
              id={"admin-quote-#{quote.id}"}
              class={[!quote.enabled && "opacity-50"]}
            >
              <td class="w-28">
                <img
                  :if={quote.thumb_path}
                  src={Media.url(quote.thumb_path)}
                  class="w-24 rounded aspect-video object-cover"
                  alt=""
                  loading="lazy"
                />
              </td>
              <td class="max-w-md">
                <%= if @editing == quote.id do %>
                  <.form
                    for={@edit_form}
                    id={"edit-quote-#{quote.id}"}
                    phx-submit="save_text"
                    class="flex gap-2"
                  >
                    <input type="hidden" name="quote_id" value={quote.id} />
                    <input
                      type="text"
                      name="text"
                      value={@edit_form[:text].value}
                      class="input input-sm flex-1"
                    />
                    <button class="btn btn-sm btn-primary">OK</button>
                    <button type="button" phx-click="cancel_edit" class="btn btn-sm btn-ghost">Annuler</button>
                  </.form>
                <% else %>
                  <.link navigate={~p"/q/#{quote.id}"} class="hover:underline">{quote.text}</.link>
                  <div class="text-xs text-base-content/50">
                    {Text.format_ms(quote.start_ms)} – {Text.format_ms(quote.end_ms)}
                    <span
                      :if={quote.asr_score}
                      id={"asr-score-#{quote.id}"}
                      class={[
                        "badge badge-xs ml-2",
                        if(Quote.needs_review?(quote), do: "badge-warning", else: "badge-success")
                      ]}
                      title="Accord entre le texte et la parole entendue (transcription vocale)"
                    >
                      {if Quote.needs_review?(quote), do: "à vérifier", else: "vérifiée"} · {round(
                        quote.asr_score * 100
                      )} %
                    </span>
                  </div>
                <% end %>
              </td>
              <td class="text-xs max-w-48 truncate">{quote.source.title}</td>
              <td>
                <form id={"quote-author-#{quote.id}"} phx-change="set_author">
                  <input type="hidden" name="quote_id" value={quote.id} />
                  <select
                    name="author_id"
                    class="select select-xs w-44"
                    aria-label="Auteur de la quote"
                  >
                    <option value="">
                      {if quote.source.author,
                        do: "Vidéo : #{quote.source.author.name}",
                        else: "— aucun —"}
                    </option>
                    <option
                      :for={{name, id} <- @author_options}
                      value={id}
                      selected={quote.author_id == id}
                    >
                      {name}
                    </option>
                  </select>
                </form>
              </td>
              <td><.status_badge status={quote.status} /></td>
              <td>{quote.views_count}</td>
              <td class="text-right whitespace-nowrap">
                <button
                  :if={Quote.needs_review?(quote)}
                  id={"review-quote-#{quote.id}"}
                  type="button"
                  phx-click="mark_reviewed"
                  phx-value-id={quote.id}
                  class="btn btn-xs btn-ghost text-success"
                  title="Le texte correspond à ce qui est dit : valider et afficher"
                >
                  <.icon name="hero-check-circle" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={quote.id}
                  class="btn btn-xs btn-ghost"
                  title="Corriger le texte"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="toggle"
                  phx-value-id={quote.id}
                  class="btn btn-xs btn-ghost"
                  title={if quote.enabled, do: "Masquer", else: "Afficher"}
                >
                  <.icon
                    name={if quote.enabled, do: "hero-eye-slash", else: "hero-eye"}
                    class="size-4"
                  />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@quotes == []} class="p-6 text-center text-base-content/60">Aucune quote.</p>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Quotes",
       editing: nil,
       edit_form: to_form(%{"text" => ""}),
       author_options: Enum.map(Catalog.list_authors(), &{&1.name, &1.id})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    source_id =
      case Integer.parse(params["source_id"] || "") do
        {id, ""} -> id
        _ -> nil
      end

    search = params["search"] || ""

    {:noreply,
     socket
     |> assign(
       source_id: source_id,
       review?: params["review"] == "1",
       filter: to_form(%{"search" => search})
     )
     |> load()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      Map.take(params, ["search", "source_id", "review"])
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/quotes?#{query}")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    quote = Enum.find(socket.assigns.quotes, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, editing: quote.id, edit_form: to_form(%{"text" => quote.text}))}
  end

  def handle_event("cancel_edit", _, socket), do: {:noreply, assign(socket, editing: nil)}

  def handle_event("save_text", %{"quote_id" => id, "text" => text}, socket) do
    quote = Catalog.get_quote!(id)

    case Catalog.update_quote(quote, %{text: text}) do
      {:ok, quote} ->
        # corrigée par un admin : elle n'est plus « à vérifier »
        if Quote.needs_review?(quote), do: Catalog.mark_quote_reviewed(quote)
        {:noreply, socket |> assign(editing: nil) |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Texte invalide.")}
    end
  end

  def handle_event("set_author", %{"quote_id" => id, "author_id" => author_id}, socket) do
    quote = Catalog.get_quote!(id)
    author_id = if author_id == "", do: nil, else: author_id
    {:ok, _} = Catalog.update_quote(quote, %{author_id: author_id})
    {:noreply, socket |> put_flash(:info, "Auteur de la quote mis à jour.") |> load()}
  end

  def handle_event("mark_reviewed", %{"id" => id}, socket) do
    {:ok, _} = id |> Catalog.get_quote!() |> Catalog.mark_quote_reviewed()
    {:noreply, socket |> put_flash(:info, "Quote validée et affichée.") |> load()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    quote = Catalog.get_quote!(id)
    {:ok, _} = Catalog.update_quote(quote, %{enabled: !quote.enabled})
    {:noreply, load(socket)}
  end

  defp load(socket) do
    assign(socket,
      quotes:
        Catalog.list_admin_quotes(
          search: socket.assigns.filter[:search].value,
          source_id: socket.assigns.source_id,
          review: socket.assigns.review?
        ),
      to_review: Catalog.count_quotes_to_review()
    )
  end
end
