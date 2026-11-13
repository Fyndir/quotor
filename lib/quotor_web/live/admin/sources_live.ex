defmodule QuotorWeb.Admin.SourcesLive do
  @moduledoc """
  Gestion des vidéos sources : l'admin fournit des URLs YouTube particulières
  (ou envoie un fichier vidéo + sous-titres) pour générer des quotes.
  """
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.{Catalog, Ingest, Media, Text}
  alias Quotor.Catalog.Source

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:sources}>
      <h1 class="text-2xl font-black mb-6">Vidéos sources</h1>

      <div class="grid gap-6 lg:grid-cols-2 mb-8">
        <section class="rounded-2xl bg-base-200 p-5">
          <h2 class="font-bold mb-1">Ajouter des vidéos YouTube</h2>
          <p class="text-sm text-base-content/60 mb-3">
            Une URL par ligne. Les sous-titres français (manuels ou automatiques) sont utilisés
            s'il y en a, vérifiés par transcription vocale ; sinon le texte vient de la seule
            transcription (whisper.cpp actif sur le worker). Traitement en arrière-plan.
          </p>
          <.form for={@url_form} id="url-form" phx-submit="add_urls">
            <.input
              field={@url_form[:urls]}
              type="textarea"
              rows="4"
              placeholder="https://www.youtube.com/watch?v=…"
            />
            <.button class="btn btn-primary btn-sm" phx-disable-with="Ajout…">
              <.icon name="hero-plus" class="size-4" /> Ajouter
            </.button>
          </.form>
        </section>

        <section class="rounded-2xl bg-base-200 p-5">
          <h2 class="font-bold mb-1">Envoyer un fichier</h2>
          <p class="text-sm text-base-content/60 mb-3">
            Vidéo (mp4, mkv, webm, mov) + sous-titres facultatifs (.vtt ou .srt) : sans eux, le
            texte vient de la transcription vocale.
          </p>
          <.form for={@upload_form} id="upload-form" phx-submit="upload" phx-change="validate_upload">
            <.input field={@upload_form[:title]} type="text" label="Titre" required />
            <.input field={@upload_form[:uploader]} type="text" label="Chaîne" />
            <.input field={@upload_form[:url]} type="url" label="Lien de l'original (attribution)" />
            <.input
              field={@upload_form[:author_id]}
              type="select"
              label="Auteur (qui parle)"
              options={@author_options}
              prompt="— la chaîne ci-dessus —"
            />
            <div class="grid gap-3 sm:grid-cols-2 my-3 text-sm">
              <label class="block">
                <span class="block mb-1">Vidéo</span>
                <.live_file_input upload={@uploads.video} class="file-input file-input-sm w-full" />
              </label>
              <label class="block">
                <span class="block mb-1">Sous-titres</span>
                <.live_file_input upload={@uploads.subtitles} class="file-input file-input-sm w-full" />
              </label>
            </div>
            <div :for={entry <- @uploads.video.entries} class="text-xs mb-2">
              {entry.client_name} — {entry.progress}%
              <progress class="progress progress-primary w-full" value={entry.progress} max="100" />
              <p :for={err <- upload_errors(@uploads.video, entry)} class="text-error">
                {upload_error(err)}
              </p>
            </div>
            <.button class="btn btn-primary btn-sm" phx-disable-with="Envoi…">
              <.icon name="hero-arrow-up-tray" class="size-4" /> Envoyer
            </.button>
          </.form>
        </section>
      </div>

      <div class="flex flex-wrap items-center gap-2 mb-4">
        <.link
          :for={status <- [nil | Source.statuses()]}
          patch={~p"/admin/sources?#{if status, do: %{status: status}, else: %{}}"}
          class={["btn btn-xs", if(@status == status, do: "btn-primary", else: "btn-ghost")]}
        >
          {if status, do: status_label(status), else: "Toutes"}
          <span class="opacity-60">{if status,
            do: Map.get(@counts, status, 0),
            else: Enum.sum(Map.values(@counts))}</span>
        </.link>
      </div>

      <div class="overflow-x-auto rounded-2xl bg-base-200">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Vidéo</th>
              <th>Auteur</th>
              <th>Statut</th>
              <th>Quotes</th>
              <th>Durée</th>
              <th></th>
            </tr>
          </thead>
          <tbody id="sources" phx-update="stream">
            <tr :for={{dom_id, source} <- @streams.sources} id={dom_id}>
              <td class="max-w-md">
                <div class="font-semibold truncate">{source.title || source.url}</div>
                <div class="text-xs text-base-content/60 truncate">
                  <span :if={source.uploader}>{source.uploader} · </span>
                  <span :if={source.channel}>via {source.channel.name} · </span>
                  <a :if={source.url} href={source.url} target="_blank" rel="noopener" class="link">
                    {source.origin}
                  </a>
                  <span :if={!source.url}>{source.origin}</span>
                </div>
                <div :if={source.error} class="text-xs text-error mt-1">{source.error}</div>
              </td>
              <td>
                <form id={"source-author-#{source.id}"} phx-change="set_author">
                  <input type="hidden" name="source_id" value={source.id} />
                  <select
                    name="author_id"
                    class="select select-xs w-40"
                    aria-label="Auteur de la vidéo"
                  >
                    <option value="">—</option>
                    <option
                      :for={{name, id} <- @author_options}
                      value={id}
                      selected={source.author_id == id}
                    >
                      {name}
                    </option>
                  </select>
                </form>
              </td>
              <td>
                <.status_badge status={source.status} />
                <span :if={!source.enabled} class="badge badge-sm badge-warning ml-1">masquée</span>
                <div :if={source.text_origin} class="text-xs text-base-content/60 mt-1">
                  {text_origin_label(source)}
                </div>
              </td>
              <td>
                <.link navigate={~p"/admin/quotes?#{%{source_id: source.id}}"} class="link">
                  {source.quotes_count}
                </.link>
              </td>
              <td class="text-xs">
                {if source.duration_s, do: Text.format_ms(source.duration_s * 1000), else: "–"}
              </td>
              <td class="text-right whitespace-nowrap">
                <button
                  :if={source.status in ~w(failed ready)}
                  type="button"
                  phx-click="retry"
                  phx-value-id={source.id}
                  class="btn btn-xs btn-ghost"
                  title="Relancer le traitement"
                >
                  <.icon name="hero-arrow-path" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="toggle"
                  phx-value-id={source.id}
                  class="btn btn-xs btn-ghost"
                  title={if source.enabled, do: "Masquer", else: "Afficher"}
                >
                  <.icon
                    name={if source.enabled, do: "hero-eye-slash", else: "hero-eye"}
                    class="size-4"
                  />
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={source.id}
                  data-confirm="Supprimer cette vidéo et toutes ses quotes ?"
                  class="btn btn-xs btn-ghost text-error"
                  title="Supprimer"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Catalog.subscribe()

    {:ok,
     socket
     |> assign(
       page_title: "Vidéos sources",
       url_form: to_form(%{"urls" => ""}),
       upload_form: to_form(%{"title" => "", "uploader" => "", "url" => "", "author_id" => ""}),
       author_options: author_options()
     )
     |> allow_upload(:video,
       accept: ~w(.mp4 .mkv .webm .mov),
       max_entries: 1,
       max_file_size: 2_000_000_000,
       chunk_size: 1_000_000
     )
     |> allow_upload(:subtitles, accept: ~w(.vtt .srt), max_entries: 1, max_file_size: 5_000_000)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status = if params["status"] in Source.statuses(), do: params["status"]

    {:noreply,
     socket
     |> assign(status: status, counts: Catalog.count_sources_by_status())
     |> stream(:sources, Catalog.list_sources(status: status), reset: true)}
  end

  @impl true
  def handle_event("add_urls", %{"urls" => urls}, socket) do
    results =
      urls
      |> String.split(~r/[\s,]+/, trim: true)
      |> Enum.uniq()
      |> Enum.map(&{&1, Ingest.submit_youtube(&1, socket.assigns.current_scope)})

    ok = Enum.count(results, &match?({_, {:ok, _}}, &1))

    errors =
      for {url, {:error, cs}} <- results do
        msg = cs.errors |> Enum.map(fn {_f, {m, _}} -> m end) |> Enum.join(", ")
        "#{url} : #{msg}"
      end

    Logger.info("admin : #{ok} vidéo(s) ajoutée(s)")

    socket =
      socket
      |> assign(
        url_form: to_form(%{"urls" => Enum.map_join(errors, "\n", &hd(String.split(&1, " : ")))})
      )
      |> refresh()

    socket =
      if ok > 0,
        do: put_flash(socket, :info, "#{ok} vidéo(s) en file de traitement."),
        else: socket

    socket =
      if errors != [], do: put_flash(socket, :error, Enum.join(errors, " — ")), else: socket

    {:noreply, socket}
  end

  def handle_event("validate_upload", params, socket) do
    {:noreply,
     assign(socket, upload_form: to_form(Map.take(params, ~w(title uploader url author_id))))}
  end

  def handle_event("upload", params, socket) do
    tmp = Media.tmp_dir!("uploads")

    [video] =
      case consume_uploaded_entries(socket, :video, &copy_upload(&1, &2, tmp)) do
        [] -> [nil]
        paths -> paths
      end

    subtitles =
      consume_uploaded_entries(socket, :subtitles, &copy_upload(&1, &2, tmp)) |> List.first()

    cond do
      is_nil(video) ->
        {:noreply, put_flash(socket, :error, "Choisis un fichier vidéo.")}

      true ->
        attrs = Map.take(params, ~w(title uploader url author_id))

        case Ingest.submit_upload(attrs, video, subtitles, socket.assigns.current_scope) do
          {:ok, _source} ->
            {:noreply,
             socket
             |> put_flash(:info, "Fichier reçu, traitement en arrière-plan.")
             |> assign(upload_form: to_form(%{"title" => "", "uploader" => "", "url" => ""}))
             |> refresh()}

          {:error, cs} ->
            File.rm(video)
            if subtitles, do: File.rm(subtitles)
            {:noreply, assign(socket, upload_form: to_form(cs, as: "source"))}
        end
    end
  end

  def handle_event("retry", %{"id" => id}, socket) do
    {:ok, _} = id |> Catalog.get_source!() |> Ingest.retry()
    {:noreply, socket |> put_flash(:info, "Traitement relancé.") |> refresh()}
  end

  def handle_event("set_author", %{"source_id" => id, "author_id" => author_id}, socket) do
    source = Catalog.get_source!(id)
    {:ok, _} = Catalog.update_source(source, %{author_id: blank_to_nil(author_id)})
    Logger.info("admin : auteur de la source #{id} → #{author_id}")
    {:noreply, socket |> put_flash(:info, "Auteur de la vidéo mis à jour.") |> refresh()}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    source = Catalog.get_source!(id)
    {:ok, _} = Catalog.update_source(source, %{enabled: !source.enabled})
    Logger.info("admin : source #{id} #{if source.enabled, do: "masquée", else: "affichée"}")
    {:noreply, refresh(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    source = Catalog.get_source!(id)
    {:ok, _} = Catalog.delete_source(source)
    Logger.info("admin : source #{id} supprimée")
    {:noreply, socket |> stream_delete(:sources, source) |> refresh()}
  end

  @impl true
  def handle_info({Catalog, {:source_updated, _source}}, socket) do
    {:noreply, refresh(socket)}
  end

  def handle_info({Catalog, _}, socket), do: {:noreply, socket}

  defp refresh(socket) do
    socket
    |> assign(counts: Catalog.count_sources_by_status())
    |> stream(:sources, Catalog.list_sources(status: socket.assigns.status), reset: true)
  end

  defp copy_upload(%{path: path}, entry, tmp) do
    dest = Path.join(tmp, "#{entry.uuid}#{Path.extname(entry.client_name) |> String.downcase()}")
    File.cp!(path, dest)
    {:ok, dest}
  end

  defp author_options, do: Enum.map(Catalog.list_authors(), &{&1.name, &1.id})

  defp text_origin_label(%{text_origin: "transcription"}), do: "texte : transcription vocale"
  defp text_origin_label(%{asr_status: "done"}), do: "sous-titres vérifiés à la voix"
  defp text_origin_label(%{asr_status: "failed"}), do: "sous-titres (transcription en échec)"
  defp text_origin_label(_), do: "sous-titres (non vérifiés)"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp upload_error(:too_large), do: "Fichier trop volumineux"
  defp upload_error(:not_accepted), do: "Format non accepté"
  defp upload_error(:too_many_files), do: "Un seul fichier à la fois"
  defp upload_error(err), do: inspect(err)
end
