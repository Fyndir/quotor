defmodule QuotorWeb.QuoteLive do
  @moduledoc "Page d'un extrait : lecture, source (attribution), partage, signalement."
  use QuotorWeb, :live_view

  alias Quotor.{Catalog, Media}
  alias Quotor.Accounts.Scope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="grid gap-8 lg:grid-cols-[2fr_1fr]">
        <div>
          <div class="rounded-2xl overflow-hidden bg-black ring-1 ring-base-300">
            <video
              id="quote-player"
              src={Media.url(@quote.clip_path)}
              poster={Media.url(@quote.thumb_path)}
              controls
              autoplay
              playsinline
              class="w-full aspect-video"
            ></video>
          </div>
          <blockquote class="mt-6 text-2xl sm:text-3xl font-extrabold leading-snug">
            « {@quote.text} »
          </blockquote>
        </div>

        <aside class="space-y-4">
          <div class="rounded-2xl bg-base-200 p-5 space-y-2 text-sm">
            <.attribution quote={@quote} />
            <a
              :if={original_url(@quote.source, @quote.start_ms)}
              href={original_url(@quote.source, @quote.start_ms)}
              target="_blank"
              rel="noopener"
              class="btn btn-sm btn-outline w-full mt-2"
            >
              <.icon name="hero-play-circle" class="size-4" /> Voir la vidéo originale
            </a>
            <p class="text-xs text-base-content/50 pt-2">
              Extrait © ses auteurs, proposé à des fins parodiques.
            </p>
          </div>

          <div class="flex flex-col gap-2">
            <button
              id="copy-quote-link"
              type="button"
              phx-hook="CopyLink"
              data-url={~p"/q/#{@quote.id}"}
              class="btn btn-primary"
            >
              <.icon name="hero-link" class="size-4" />
              <span data-label>Copier le lien (Discord, réseaux…)</span>
            </button>
            <button
              id="copy-quote-mp4"
              type="button"
              phx-hook="CopyLink"
              data-url={Media.url(@quote.clip_path)}
              class="btn btn-ghost btn-sm"
              title="Lien direct vers la vidéo : lue directement dans Discord, sans carte"
            >
              <.icon name="hero-film" class="size-4" />
              <span data-label>Copier le lien vidéo (.mp4)</span>
            </button>
            <button
              :if={@can_favorite}
              type="button"
              phx-click="toggle_favorite"
              class="btn btn-ghost"
            >
              <.icon
                name={if @favorite, do: "hero-heart-solid", else: "hero-heart"}
                class={["size-4", @favorite && "text-error"]}
              />
              {if @favorite, do: "Dans tes favoris", else: "Ajouter aux favoris"}
            </button>
            <.link
              navigate={~p"/?#{%{q: @quote.text, mode: "advanced"}}"}
              class="btn btn-ghost"
            >
              <.icon name="hero-scissors" class="size-4" /> Remonter cette phrase
            </.link>
            <.link
              navigate={~p"/signaler?#{%{quote_id: @quote.id}}"}
              class="btn btn-ghost btn-sm text-base-content/60"
            >
              <.icon name="hero-flag" class="size-4" /> Signaler / demander le retrait
            </.link>
          </div>
        </aside>
      </div>

      <section :if={@related != []} class="mt-12">
        <h2 class="text-sm uppercase tracking-widest text-base-content/50 mb-4">
          Dans la même vidéo
        </h2>
        <div class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
          <.quote_card :for={q <- @related} quote={q} id={"related-#{q.id}"} />
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with {int_id, ""} <- Integer.parse(id),
         %{} = quote <- Catalog.get_public_quote(int_id) do
      if connected?(socket), do: Catalog.increment_views(quote.id)
      scope = socket.assigns.current_scope

      {:ok,
       assign(socket,
         page_title: "« #{String.slice(quote.text, 0, 60)} »",
         og: QuotorWeb.OpenGraph.for_quote(quote),
         quote: quote,
         related: related(quote),
         can_favorite: Scope.user?(scope),
         favorite: MapSet.member?(Catalog.favorite_ids(scope, [quote.id]), quote.id)
       )}
    else
      _ -> raise QuotorWeb.NotFoundError
    end
  end

  @impl true
  def handle_event("toggle_favorite", _params, socket) do
    if socket.assigns.can_favorite do
      result = Catalog.toggle_favorite(socket.assigns.current_scope, socket.assigns.quote.id)
      {:noreply, assign(socket, favorite: result == :added)}
    else
      {:noreply, socket}
    end
  end

  defp related(quote) do
    import Ecto.Query

    Catalog.visible_quotes()
    |> where([q], q.source_id == ^quote.source_id and q.id != ^quote.id)
    |> order_by([q], fragment("abs(? - ?)", q.start_ms, ^quote.start_ms))
    |> limit(6)
    |> Catalog.with_display()
    |> Quotor.Repo.all()
  end
end
