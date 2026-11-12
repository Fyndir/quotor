defmodule QuotorWeb.Admin.LogsLive do
  @moduledoc "Consultation des derniers logs applicatifs (buffer mémoire)."
  use QuotorWeb, :live_view

  alias Quotor.Logs

  import QuotorWeb.Admin.DashboardLive, only: [level_class: 1]

  @levels [{"Tous", ""}, {"Info+", "info"}, {"Avertissements+", "warning"}, {"Erreurs", "error"}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:logs}>
      <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
        <h1 class="text-2xl font-black">Logs</h1>
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="toggle_live"
            class={["btn btn-xs", if(@live, do: "btn-primary", else: "btn-ghost")]}
          >
            <.icon name={if @live, do: "hero-pause", else: "hero-play"} class="size-4" />
            {if @live, do: "Direct", else: "En pause"}
          </button>
          <button
            type="button"
            phx-click="clear"
            data-confirm="Vider le buffer de logs ?"
            class="btn btn-xs btn-ghost"
          >
            Vider
          </button>
        </div>
      </div>
      <p class="text-xs text-base-content/60 mb-4">
        Les {@max} derniers événements (niveau ≥ info) sont conservés en mémoire. L'historique complet
        est sur la sortie standard du conteneur (logs Docker / Render).
      </p>

      <.form for={@filter} id="logs-filter" phx-change="filter" class="flex flex-wrap gap-2 mb-4">
        <select name="level" class="select select-sm">
          <option
            :for={{label, value} <- @levels}
            value={value}
            selected={@filter[:level].value == value}
          >
            {label}
          </option>
        </select>
        <input
          type="search"
          name="search"
          value={@filter[:search].value}
          placeholder="Filtrer…"
          phx-debounce="300"
          class="input input-sm flex-1 min-w-48"
        />
      </.form>

      <div class="rounded-2xl bg-base-300 p-3 font-mono text-xs overflow-x-auto">
        <p :if={@logs == []} class="text-base-content/60 p-4 text-center">Aucun log.</p>
        <div :for={log <- @logs} class="flex gap-2 py-0.5 border-b border-base-100/10 last:border-0">
          <span class="text-base-content/50 shrink-0">{Calendar.strftime(log.at, "%d/%m %H:%M:%S")}</span>
          <span class={["shrink-0 w-16 uppercase", level_class(log.level)]}>{log.level}</span>
          <span class="break-all whitespace-pre-wrap flex-1">{log.message}</span>
          <span :if={log.metadata != %{}} class="shrink-0 text-base-content/40">
            {log.metadata
            |> Map.take([:request_id, :source_id, :user_id])
            |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{v}" end)}
          </span>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(3_000, :tick)

    {:ok, assign(socket, page_title: "Logs", live: true, levels: @levels, max: 2000)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = %{"level" => params["level"] || "", "search" => params["search"] || ""}
    {:noreply, socket |> assign(filter: to_form(filter)) |> load()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    params =
      params
      |> Map.take(["level", "search"])
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/logs?#{params}")}
  end

  def handle_event("toggle_live", _, socket),
    do: {:noreply, assign(socket, live: !socket.assigns.live)}

  def handle_event("clear", _, socket) do
    Logs.clear()
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info(:tick, %{assigns: %{live: true}} = socket), do: {:noreply, load(socket)}
  def handle_info(:tick, socket), do: {:noreply, socket}

  defp load(socket) do
    level =
      case socket.assigns.filter[:level].value do
        l when l in ~w(info warning error) -> String.to_existing_atom(l)
        _ -> nil
      end

    assign(socket,
      logs: Logs.recent(level: level, search: socket.assigns.filter[:search].value, limit: 300)
    )
  end
end
