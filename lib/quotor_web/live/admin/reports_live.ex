defmodule QuotorWeb.Admin.ReportsLive do
  @moduledoc "Traitement des signalements et demandes de retrait."
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.Catalog
  alias Quotor.Catalog.Report

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:reports}>
      <h1 class="text-2xl font-black mb-4">Signalements</h1>

      <div class="flex gap-2 mb-4">
        <.link
          :for={
            {status, label} <- [
              {"open", "À traiter"},
              {"resolved", "Traités"},
              {"rejected", "Rejetés"},
              {nil, "Tous"}
            ]
          }
          patch={~p"/admin/signalements?#{if status, do: %{status: status}, else: %{status: "all"}}"}
          class={["btn btn-xs", if(@status == status, do: "btn-primary", else: "btn-ghost")]}
        >
          {label}
        </.link>
      </div>

      <p :if={@reports == []} class="rounded-2xl bg-base-200 p-6 text-center text-base-content/60">
        Aucun signalement.
      </p>

      <ul class="space-y-3">
        <li :for={report <- @reports} id={"report-#{report.id}"} class="rounded-2xl bg-base-200 p-4">
          <div class="flex flex-wrap items-center gap-2 text-sm">
            <span class={[
              "badge",
              if(report.reason == "copyright", do: "badge-error", else: "badge-warning")
            ]}>
              {Report.reason_label(report.reason)}
            </span>
            <span class="badge badge-ghost">{report.status}</span>
            <span class="text-xs text-base-content/60">
              {Calendar.strftime(report.inserted_at, "%d/%m/%Y %H:%M")}
            </span>
            <span :if={report.contact_email} class="text-xs">
              {report.contact_name} &lt;<a href={"mailto:#{report.contact_email}"} class="link">{report.contact_email}</a>&gt;
            </span>
          </div>

          <p class="mt-2 whitespace-pre-line text-sm">{report.message}</p>

          <div :if={report.quote} class="mt-2 text-sm rounded-lg bg-base-100 p-2">
            <.link navigate={~p"/q/#{report.quote.id}"} class="link">
              Extrait n° {report.quote.id}
            </.link>
            « {report.quote.text} » — {report.quote.source.title}
            <span :if={!report.quote.enabled} class="badge badge-xs badge-warning">masqué</span>
            <span :if={!report.quote.source.enabled} class="badge badge-xs badge-warning">vidéo masquée</span>
          </div>

          <p :if={report.resolution} class="mt-2 text-xs text-base-content/60">
            Résolution : {report.resolution}
          </p>

          <div :if={report.status == "open"} class="mt-3 flex flex-wrap gap-2">
            <button
              :if={report.quote}
              type="button"
              phx-click="hide_quote"
              phx-value-id={report.id}
              class="btn btn-xs"
            >
              Masquer l'extrait
            </button>
            <button
              :if={report.quote}
              type="button"
              phx-click="hide_source"
              phx-value-id={report.id}
              class="btn btn-xs"
            >
              Masquer toute la vidéo
            </button>
            <button
              type="button"
              phx-click="resolve"
              phx-value-id={report.id}
              class="btn btn-xs btn-success"
            >
              Marquer traité
            </button>
            <button
              type="button"
              phx-click="reject"
              phx-value-id={report.id}
              class="btn btn-xs btn-ghost"
            >
              Rejeter
            </button>
          </div>
        </li>
      </ul>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Catalog.subscribe()
    {:ok, assign(socket, page_title: "Signalements")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status =
      case params["status"] do
        "all" -> nil
        s when s in ~w(open resolved rejected) -> s
        _ -> "open"
      end

    {:noreply, socket |> assign(status: status) |> load()}
  end

  @impl true
  def handle_event("hide_quote", %{"id" => id}, socket) do
    report = Catalog.get_report!(id)
    {:ok, _} = Catalog.update_quote(report.quote, %{enabled: false})
    resolve(socket, report, "resolved", "extrait masqué")
  end

  def handle_event("hide_source", %{"id" => id}, socket) do
    report = Catalog.get_report!(id)
    {:ok, _} = Catalog.update_source(report.quote.source, %{enabled: false})
    resolve(socket, report, "resolved", "vidéo source masquée")
  end

  def handle_event("resolve", %{"id" => id}, socket),
    do: resolve(socket, Catalog.get_report!(id), "resolved", "traité")

  def handle_event("reject", %{"id" => id}, socket),
    do: resolve(socket, Catalog.get_report!(id), "rejected", "rejeté")

  @impl true
  def handle_info({Catalog, {:report_created, _}}, socket), do: {:noreply, load(socket)}
  def handle_info({Catalog, _}, socket), do: {:noreply, socket}

  defp resolve(socket, report, status, resolution) do
    by = socket.assigns.current_scope.user.email

    {:ok, _} =
      Catalog.resolve_report(report, %{
        status: status,
        resolution:
          "#{resolution} par #{by} le #{Calendar.strftime(DateTime.utc_now(), "%d/%m/%Y %H:%M")}"
      })

    Logger.info("admin : signalement #{report.id} #{resolution}")
    {:noreply, socket |> put_flash(:info, "Signalement mis à jour.") |> load()}
  end

  defp load(socket), do: assign(socket, reports: Catalog.list_reports(socket.assigns.status))
end
