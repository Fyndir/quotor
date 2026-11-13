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
    assigns =
      assigns
      |> assign_new(:dom_id, fn -> assigns.id || "quote-#{assigns.quote.id}" end)
      |> assign(:author, Quotor.Catalog.author_of(assigns.quote))

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
        <div class="min-w-0 flex-1 leading-tight">
          <.link
            :if={@author}
            navigate={~p"/auteurs/#{@author.slug}"}
            class="block truncate font-semibold text-base-content/80 hover:text-primary"
            title={"Toutes les répliques de #{@author.name}"}
          >
            {@author.name}
          </.link>
          <.link
            navigate={~p"/q/#{@quote.id}"}
            class="block truncate text-base-content/50 hover:text-base-content"
            title={@quote.source && @quote.source.title}
          >
            {source_label(@quote.source, @author)}
          </.link>
        </div>
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
        <p
          :if={@montage.asr_score}
          id={"montage-#{@montage.key}-check"}
          class={[
            "text-sm flex items-center gap-1.5",
            if(@montage.doubtful == [], do: "text-success", else: "text-warning")
          ]}
        >
          <.icon
            name={if @montage.doubtful == [], do: "hero-check-badge", else: "hero-speaker-wave"}
            class="size-4"
          />
          <%= if @montage.doubtful == [] do %>
            Vérifié à l'écoute : chaque mot est bien prononcé.
          <% else %>
            Vérifié à l'écoute ({round(@montage.asr_score * 100)} %) — peut-être mal rendu{if length(
                                                                                                @montage.doubtful
                                                                                              ) > 1,
                                                                                              do: "s",
                                                                                              else: ""} : {Enum.join(
              @montage.doubtful,
              ", "
            )}
          <% end %>
        </p>
        <p :if={@montage.missing != []} class="text-sm text-warning">
          <.icon name="hero-exclamation-triangle-micro" class="size-4" />
          Introuvable{if length(@montage.missing) > 1, do: "s", else: ""} : {Enum.join(
            @montage.missing,
            ", "
          )}
        </p>
        <div class="flex flex-wrap gap-2">
          <a
            id={"montage-#{@montage.key}-download"}
            href={~p"/m/#{@montage.key}/telecharger"}
            download
            class="btn btn-sm btn-primary"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Télécharger
          </a>
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
        "review" -> "badge-warning"
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
  def status_label("refining"), do: "affinage"
  def status_label("cut"), do: "brut"
  def status_label("review"), do: "à vérifier"
  def status_label("ready"), do: "prête"
  def status_label("failed"), do: "échec"
  def status_label(other), do: other

  def original_url(source, start_ms), do: Source.original_url(source, start_ms)

  @doc """
  Ligne « source » d'une carte : le titre de la vidéo, précédé de la chaîne
  quand l'auteur affiché est une personne différente de la chaîne.
  """
  def source_label(nil, _author), do: nil

  def source_label(source, author) do
    channel = source.uploader
    author_name = author && author.name

    if is_binary(channel) and is_binary(source.title) and author_name != channel do
      "#{channel} · #{source.title}"
    else
      source.title || channel
    end
  end

  @doc "Bloc « qui parle / chaîne / source » de la page d'un extrait."
  attr :quote, :map, required: true

  def attribution(assigns) do
    assigns = assign(assigns, :author, Quotor.Catalog.author_of(assigns.quote))

    ~H"""
    <dl class="space-y-3 text-sm">
      <div :if={@author}>
        <dt class="text-xs uppercase tracking-widest text-base-content/50">
          {if @author.kind == "channel", do: "Auteur (chaîne)", else: "Qui parle"}
        </dt>
        <dd>
          <.link
            navigate={~p"/auteurs/#{@author.slug}"}
            class="font-semibold hover:text-primary"
            id="quote-author"
          >
            {@author.name}
          </.link>
        </dd>
      </div>
      <div :if={@quote.source.uploader}>
        <dt class="text-xs uppercase tracking-widest text-base-content/50">Chaîne</dt>
        <dd>
          <a
            :if={@quote.source.channel_url}
            href={@quote.source.channel_url}
            target="_blank"
            rel="noopener"
            class="hover:text-primary"
          >
            {@quote.source.uploader}
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-3" />
          </a>
          <span :if={!@quote.source.channel_url}>{@quote.source.uploader}</span>
        </dd>
      </div>
      <div>
        <dt class="text-xs uppercase tracking-widest text-base-content/50">Source</dt>
        <dd class="font-semibold">{@quote.source.title}</dd>
        <dd class="text-base-content/70">
          à {Quotor.Text.format_ms(@quote.start_ms)}
          <span :if={@quote.source.published_on}>
            · publiée le {Calendar.strftime(@quote.source.published_on, "%d/%m/%Y")}
          </span>
        </dd>
      </div>
    </dl>
    """
  end
end
