defmodule QuotorWeb.QuoteComponents do
  @moduledoc "Composants d'affichage des quotes et des montages."
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: QuotorWeb.Endpoint, router: QuotorWeb.Router

  import QuotorWeb.CoreComponents, only: [icon: 1]

  alias Quotor.Media
  alias Quotor.Catalog.Source

  @doc "Carte d'un extrait : vidéo (clic = lecture avec le son), texte, source, actions."
  attr :quote, :map, required: true
  attr :favorite, :boolean, default: false
  attr :can_favorite, :boolean, default: false
  attr :id, :string, default: nil

  def quote_card(assigns) do
    assigns = assign_new(assigns, :dom_id, fn -> assigns.id || "quote-#{assigns.quote.id}" end)

    ~H"""
    <article
      id={@dom_id}
      phx-hook="QuoteVideo"
      class="quote-card group relative overflow-hidden rounded-2xl bg-base-300 shadow-sm ring-1 ring-base-300 hover:ring-primary/60 transition cursor-pointer"
    >
      <div class="relative aspect-video bg-black overflow-hidden">
        <video
          src={Media.url(@quote.clip_path)}
          poster={Media.url(@quote.thumb_path)}
          preload="none"
          playsinline
          class="size-full object-cover"
        ></video>
        <div class="absolute inset-x-0 bottom-0 p-3 bg-gradient-to-t from-black/80 via-black/40 to-transparent">
          <p class="subtitle-text text-center text-sm sm:text-base">« {@quote.text} »</p>
        </div>
        <div class="play-badge absolute top-2 left-2 rounded-full bg-black/60 text-white px-2 py-1 text-xs flex items-center gap-1">
          <.icon name="hero-speaker-wave-micro" class="size-3" /> Lire
        </div>
      </div>

      <div class="flex items-center gap-2 px-3 py-2 text-xs">
        <.link
          navigate={~p"/q/#{@quote.id}"}
          class="truncate flex-1 text-base-content/70 hover:text-base-content"
          title={@quote.source && @quote.source.title}
        >
          {@quote.source && (@quote.source.uploader || @quote.source.title)}
        </.link>
        <button
          :if={@can_favorite}
          type="button"
          phx-click="toggle_favorite"
          phx-value-id={@quote.id}
          class={[
            "p-1 rounded-full hover:bg-base-200",
            if(@favorite, do: "text-error", else: "text-base-content/50")
          ]}
          aria-label={if @favorite, do: "Retirer des favoris", else: "Ajouter aux favoris"}
        >
          <.icon name={if @favorite, do: "hero-heart-solid", else: "hero-heart"} class="size-4" />
        </button>
        <button
          id={"#{@dom_id}-copy"}
          type="button"
          phx-hook="CopyLink"
          data-url={~p"/q/#{@quote.id}"}
          class="p-1 rounded-full hover:bg-base-200 text-base-content/50"
          aria-label="Copier le lien"
        >
          <.icon name="hero-link" class="size-4" />
          <span data-label class="sr-only">Copier</span>
        </button>
      </div>
    </article>
    """
  end

  @doc "Lecteur de montage avec la liste des segments utilisés."
  attr :montage, :map, required: true

  def montage_player(assigns) do
    ~H"""
    <div class="rounded-2xl overflow-hidden bg-base-200 ring-1 ring-base-300">
      <video
        id={"montage-#{@montage.key}"}
        src={Media.url(@montage.file_path)}
        poster={Media.url(Quotor.Montages.poster_rel(@montage))}
        controls
        autoplay
        playsinline
        class="w-full aspect-video bg-black"
      ></video>
      <div class="p-4 space-y-3">
        <div class="flex flex-wrap gap-2">
          <.link
            :for={{seg, i} <- Enum.with_index(@montage.segments)}
            navigate={~p"/q/#{seg["quote_id"]}"}
            class="segment-chip badge badge-lg gap-1 bg-base-100 hover:bg-primary hover:text-primary-content border-base-300"
            style={"animation-delay: #{i * 60}ms"}
            title={seg["source_title"]}
          >
            {seg["text"]}
          </.link>
        </div>
        <p :if={@montage.missing != []} class="text-sm text-warning">
          <.icon name="hero-exclamation-triangle-micro" class="size-4" />
          Introuvable{if length(@montage.missing) > 1, do: "s", else: ""} : {Enum.join(
            @montage.missing,
            ", "
          )}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            id={"montage-#{@montage.key}-copy"}
            type="button"
            phx-hook="CopyLink"
            data-url={~p"/m/#{@montage.key}"}
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-link" class="size-4" /> <span data-label>Copier le lien</span>
          </button>
          <button
            id={"montage-#{@montage.key}-copy-mp4"}
            type="button"
            phx-hook="CopyLink"
            data-url={Media.url(@montage.file_path)}
            class="btn btn-sm btn-ghost"
            title="Lien direct vers la vidéo : lue directement dans Discord"
          >
            <.icon name="hero-film" class="size-4" /> <span data-label>Lien vidéo (.mp4)</span>
          </button>
          <.link navigate={~p"/m/#{@montage.key}"} class="btn btn-sm btn-ghost">
            <.icon name="hero-arrow-top-right-on-square" class="size-4" /> Ouvrir
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @doc "Badge de statut d'une source."
  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      case @status do
        "ready" -> "badge-success"
        "failed" -> "badge-error"
        "pending" -> "badge-ghost"
        _ -> "badge-info"
      end
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  def status_label("pending"), do: "en attente"
  def status_label("downloading"), do: "téléchargement"
  def status_label("cutting"), do: "découpe"
  def status_label("ready"), do: "prête"
  def status_label("failed"), do: "échec"
  def status_label(other), do: other

  def original_url(source, start_ms), do: Source.original_url(source, start_ms)
end
