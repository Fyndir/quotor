defmodule QuotorWeb.Admin.HistoryLive do
  @moduledoc """
  Historique des vidéos YouTube analysées. Une vidéo supprimée du catalogue y
  reste : la synchronisation des chaînes suivies ne la réimporte pas. L'admin
  peut la réanalyser tout de suite, ou l'« oublier » pour que la prochaine
  synchronisation la reprenne.
  """
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.{Catalog, Ingest}

  @filters [
    {"", "Toutes"},
    {"ready", "Analysées"},
    {"pending", "En cours"},
    {"failed", "En échec"},
    {"deleted", "Supprimées"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:history}>
      <h1 class="text-2xl font-black mb-2">Historique des vidéos</h1>
      <p class="text-sm text-base-content/60 mb-6">
        Toutes les vidéos YouTube déjà soumises, y compris celles supprimées depuis : la
        synchronisation des chaînes suivies ne les réimporte jamais. « Oublier » une vidéo supprimée
        permet à la prochaine synchronisation de la reprendre.
      </p>

      <div class="flex flex-wrap items-center gap-2 mb-4">
        <div class="inline-flex rounded-full bg-base-200 p-1 text-sm" role="tablist">
          <.link
            :for={{value, label} <- @filters}
            patch={~p"/admin/historique?#{%{statut: value, q: @search}}"}
            role="tab"
            aria-selected={to_string(@status == value)}
            class={[
              "flex items-center gap-1.5 rounded-full px-3 py-1 transition-colors",
              if(@status == value,
                do: "bg-primary text-primary-content font-semibold",
                else: "hover:bg-base-300"
              )
            ]}
          >
            {label}
            <span class="badge badge-xs">{count(@counts, value)}</span>
          </.link>
        </div>
        <form id="history-search" phx-change="search" phx-submit="search" class="flex-1 min-w-48">
          <input
            type="search"
            name="q"
            value={@search}
            placeholder="Titre ou identifiant YouTube…"
            phx-debounce="300"
            class="input input-sm w-full"
          />
        </form>
      </div>

      <div class="overflow-x-auto rounded-2xl bg-base-200">
        <table class="table table-sm" id="history">
          <thead>
            <tr>
              <th>Vidéo</th>
              <th>Chaîne</th>
              <th>Statut</th>
              <th>Soumise</th>
              <th>Analysée</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@entries == []}>
              <td colspan="6" class="text-center text-base-content/60 py-6">Aucune vidéo.</td>
            </tr>
            <tr :for={h <- @entries} id={"history-#{h.id}"}>
              <td class="max-w-md">
                <div class="font-semibold truncate">{h.title || h.youtube_id}</div>
                <a
                  href={h.url}
                  target="_blank"
                  rel="noopener"
                  class="text-xs link text-base-content/60"
                >
                  {h.youtube_id}
                </a>
              </td>
              <td class="text-xs">{if h.channel, do: h.channel.name, else: "manuelle"}</td>
              <td>
                <span class={["badge badge-sm", status_class(h.status)]}>{history_label(h.status)}</span>
                <div :if={h.removed_at} class="text-xs text-base-content/60 mt-1">
                  le {date(h.removed_at)}
                </div>
              </td>
              <td class="text-xs">{date(h.inserted_at)}</td>
              <td class="text-xs">{date(h.analyzed_at)}</td>
              <td class="text-right whitespace-nowrap">
                <.link
                  :if={h.source_id}
                  navigate={~p"/admin/quotes?#{%{source_id: h.source_id}}"}
                  class="btn btn-xs btn-ghost"
                >
                  Quotes
                </.link>
                <button
                  :if={h.status == "deleted"}
                  id={"reanalyze-#{h.id}"}
                  type="button"
                  phx-click="reanalyze"
                  phx-value-id={h.youtube_id}
                  class="btn btn-xs btn-ghost"
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Réanalyser
                </button>
                <button
                  :if={h.status == "deleted"}
                  id={"forget-#{h.id}"}
                  type="button"
                  phx-click="forget"
                  phx-value-id={h.youtube_id}
                  data-confirm="Oublier cette vidéo ? La prochaine synchronisation de sa chaîne pourra la réimporter."
                  class="btn btn-xs btn-ghost text-error"
                >
                  Oublier
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
    {:ok, assign(socket, page_title: "Historique des vidéos", filters: @filters)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status =
      if params["statut"] in Enum.map(@filters, &elem(&1, 0)), do: params["statut"], else: ""

    {:noreply, socket |> assign(status: status, search: params["q"] || "") |> load()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/historique?#{%{statut: socket.assigns.status, q: q}}")}
  end

  def handle_event("reanalyze", %{"id" => youtube_id}, socket) do
    case Ingest.submit_youtube(
           Quotor.Catalog.Source.canonical_url(youtube_id),
           socket.assigns.current_scope
         ) do
      {:ok, _source} ->
        Logger.info("admin : vidéo #{youtube_id} réanalysée depuis l'historique")
        {:noreply, socket |> put_flash(:info, "Vidéo remise en traitement.") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Impossible de réanalyser cette vidéo.")}
    end
  end

  def handle_event("forget", %{"id" => youtube_id}, socket) do
    with %{} = h <- Catalog.get_video_history(youtube_id),
         {:ok, _} <- Catalog.forget_video(h) do
      Logger.info("admin : vidéo #{youtube_id} oubliée de l'historique")
      {:noreply, socket |> put_flash(:info, "Vidéo oubliée.") |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Seule une vidéo supprimée peut être oubliée.")}
    end
  end

  defp load(socket) do
    assign(socket,
      entries:
        Catalog.list_video_history(search: socket.assigns.search, status: socket.assigns.status),
      counts: Catalog.count_video_history_by_status()
    )
  end

  defp count(counts, ""), do: counts |> Map.values() |> Enum.sum()
  defp count(counts, status), do: Map.get(counts, status, 0)

  defp history_label("ready"), do: "analysée"
  defp history_label("pending"), do: "en cours"
  defp history_label("failed"), do: "échec"
  defp history_label("deleted"), do: "supprimée"
  defp history_label(other), do: other

  defp status_class("ready"), do: "badge-success"
  defp status_class("failed"), do: "badge-error"
  defp status_class("deleted"), do: "badge-ghost"
  defp status_class(_), do: "badge-info"

  defp date(nil), do: "—"
  defp date(dt), do: Calendar.strftime(dt, "%d/%m/%Y")
end
