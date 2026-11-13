defmodule QuotorWeb.Admin.DashboardLive do
  @moduledoc "Supervision : état du système, de la base, des jobs et du catalogue."
  use QuotorWeb, :live_view

  alias Quotor.{Logs, Media, Monitoring}

  import Quotor.Monitoring, only: [human_bytes: 1, human_duration: 1]

  @refresh_ms 5_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:dashboard}>
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-black">Supervision</h1>
        <span class="text-xs text-base-content/50">
          Actualisé à {Calendar.strftime(@snap.at, "%H:%M:%S")} UTC
        </span>
      </div>

      <%!-- Alertes --%>
      <div class="space-y-2 mb-6">
        <div :if={!@snap.database.ok} class="alert alert-error">
          <.icon name="hero-circle-stack" class="size-5" />
          Base de données injoignable : {@snap.database[:error]}
        </div>
        <div :if={!@snap.tools.ffmpeg} class="alert alert-error">
          <.icon name="hero-wrench" class="size-5" />
          ffmpeg est introuvable : aucune découpe possible.
        </div>
        <div :if={!@snap.tools.yt_dlp} class="alert alert-warning">
          <.icon name="hero-wrench" class="size-5" />
          yt-dlp est introuvable : seules les vidéos envoyées par fichier peuvent être traitées.
        </div>
        <div :if={@snap.errors_last_hour > 0} class="alert alert-warning">
          <.icon name="hero-exclamation-triangle" class="size-5" />
          {@snap.errors_last_hour} erreur(s) dans les logs depuis une heure.
          <.link navigate={~p"/admin/logs?level=error"} class="link">Voir</.link>
        </div>
        <div :if={@snap.catalog.to_review > 0} class="alert alert-info">
          <.icon name="hero-exclamation-triangle" class="size-5" />
          {@snap.catalog.to_review} quote(s) à vérifier : leur texte ne correspond pas à ce qui est dit.
          <.link navigate={~p"/admin/quotes?review=1"} class="link">Vérifier</.link>
        </div>
        <div :if={@snap.catalog.open_reports > 0} class="alert alert-info">
          <.icon name="hero-flag" class="size-5" />
          {@snap.catalog.open_reports} signalement(s) en attente.
          <.link navigate={~p"/admin/signalements"} class="link">Traiter</.link>
        </div>
      </div>

      <%!-- Indicateurs --%>
      <div class="grid gap-4 grid-cols-2 lg:grid-cols-4 mb-8">
        <.stat label="Quotes prêtes" value={Map.get(@snap.catalog.quotes, "ready", 0)}>
          {sum(@snap.catalog.quotes)} au total
        </.stat>
        <.stat label="Vidéos sources" value={sum(@snap.catalog.sources)}>
          {Map.get(@snap.catalog.sources, "ready", 0)} prêtes · {Map.get(
            @snap.catalog.sources,
            "failed",
            0
          )} en échec
        </.stat>
        <.stat label="Montages" value={@snap.catalog.montages}>en cache</.stat>
        <.stat label="Utilisateurs" value={sum(@snap.catalog.users)}>
          dont {Map.get(@snap.catalog.users, "admin", 0)} admin
        </.stat>
      </div>

      <div class="grid gap-6 lg:grid-cols-2 mb-8">
        <%!-- Système --%>
        <section class="rounded-2xl bg-base-200 p-5">
          <h2 class="font-bold mb-3 flex items-center gap-2">
            <.icon name="hero-cpu-chip" class="size-5" /> Système
          </h2>
          <dl class="grid grid-cols-2 gap-y-1 text-sm">
            <dt class="text-base-content/60">Uptime</dt>
            <dd>{human_duration(@snap.system.uptime_ms)}</dd>
            <dt class="text-base-content/60">Mémoire BEAM</dt>
            <dd>{human_bytes(@snap.system.memory_total)}</dd>
            <dt class="text-base-content/60">dont processus / binaires</dt>
            <dd>
              {human_bytes(@snap.system.memory_processes)} / {human_bytes(@snap.system.memory_binary)}
            </dd>
            <dt class="text-base-content/60">Processus</dt>
            <dd>{@snap.system.process_count}</dd>
            <dt class="text-base-content/60">File d'exécution</dt>
            <dd>{@snap.system.run_queue} ({@snap.system.schedulers} ordonnanceurs)</dd>
            <dt class="text-base-content/60">Rôle du nœud</dt>
            <dd>
              <span class="badge badge-sm badge-primary">{@snap.system.role}</span>
              <span class="text-xs text-base-content/60">
                {if @snap.system.queues == [],
                  do: "aucune tâche exécutée ici (workers séparés)",
                  else:
                    "files : " <>
                      Enum.map_join(@snap.system.queues, ", ", fn {q, n} -> "#{q}×#{n}" end)}
              </span>
            </dd>
            <dt class="text-base-content/60">Stockage</dt>
            <dd>{@snap.system.storage}</dd>
            <dt class="text-base-content/60">Transcription vocale</dt>
            <dd id="transcription-engine">{@snap.tools.transcription}</dd>
            <dt class="text-base-content/60">Versions</dt>
            <dd>
              Quotor {@snap.system.version} · Elixir {@snap.system.elixir} · OTP {@snap.system.otp}
            </dd>
          </dl>
        </section>

        <%!-- Base & stockage --%>
        <section class="rounded-2xl bg-base-200 p-5">
          <h2 class="font-bold mb-3 flex items-center gap-2">
            <.icon name="hero-circle-stack" class="size-5" /> Base de données &amp; stockage
          </h2>
          <dl class="grid grid-cols-2 gap-y-1 text-sm">
            <dt class="text-base-content/60">État</dt>
            <dd>
              <span class={[
                "badge badge-sm",
                if(@snap.database.ok, do: "badge-success", else: "badge-error")
              ]}>
                {if @snap.database.ok, do: "OK", else: "KO"}
              </span>
            </dd>
            <%= if @snap.database.ok do %>
              <dt class="text-base-content/60">Latence</dt>
              <dd>{@snap.database.latency_ms} ms</dd>
              <dt class="text-base-content/60">Taille</dt>
              <dd>{human_bytes(@snap.database.size)}</dd>
              <dt class="text-base-content/60">Pool</dt>
              <dd>{@snap.database.pool_size} connexions</dd>
            <% end %>
          </dl>
          <div class="mt-4">
            <%= if @media_usage do %>
              <dl class="grid grid-cols-2 gap-y-1 text-sm">
                <%= for {dir, size} <- @media_usage do %>
                  <dt class="text-base-content/60">Médias / {dir}</dt>
                  <dd>{human_bytes(size)}</dd>
                <% end %>
              </dl>
            <% else %>
              <button type="button" phx-click="media_usage" class="btn btn-xs btn-ghost">
                <.icon name="hero-folder" class="size-4" /> Calculer l'espace disque des médias
              </button>
            <% end %>
          </div>
        </section>
      </div>

      <%!-- Jobs --%>
      <section class="rounded-2xl bg-base-200 p-5 mb-8">
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-bold flex items-center gap-2">
            <.icon name="hero-queue-list" class="size-5" /> Tâches de fond
          </h2>
          <button type="button" phx-click="sync_channels" class="btn btn-xs btn-primary">
            <.icon name="hero-arrow-path" class="size-4" /> Synchroniser les chaînes
          </button>
        </div>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>File</th>
                <th>Disponibles</th>
                <th>Planifiés</th>
                <th>En cours</th>
                <th>À réessayer</th>
                <th>Abandonnés</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={queue <- ~w(ingest media default)}>
                <td class="font-mono">{queue}</td>
                <td :for={state <- ~w(available scheduled executing retryable discarded)}>
                  {get_in(@snap.jobs.by_queue, [queue, state]) || 0}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@snap.jobs.failures != []} class="mt-4">
          <h3 class="text-sm font-semibold mb-2">Derniers échecs</h3>
          <ul class="space-y-2">
            <li :for={job <- @snap.jobs.failures} class="rounded-lg bg-base-100 p-3 text-sm">
              <div class="flex items-center gap-2">
                <span class="font-mono text-xs">{short_worker(job.worker)}</span>
                <span class="badge badge-xs">{job.state}</span>
                <span class="text-xs text-base-content/60">
                  tentative {job.attempt}/{job.max_attempts} · {inspect(job.args)}
                </span>
                <button
                  type="button"
                  phx-click="retry_job"
                  phx-value-id={job.id}
                  class="btn btn-xs btn-ghost ml-auto"
                >
                  Relancer
                </button>
              </div>
              <pre class="mt-1 text-xs whitespace-pre-wrap text-error/90">{job.last_error}</pre>
            </li>
          </ul>
        </div>
      </section>

      <%!-- Derniers avertissements --%>
      <section class="rounded-2xl bg-base-200 p-5">
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-bold flex items-center gap-2">
            <.icon name="hero-command-line" class="size-5" /> Derniers avertissements
          </h2>
          <.link navigate={~p"/admin/logs"} class="btn btn-xs btn-ghost">Tous les logs</.link>
        </div>
        <p :if={@warnings == []} class="text-sm text-base-content/60">Rien à signaler.</p>
        <ul class="font-mono text-xs space-y-1">
          <li :for={log <- @warnings} class="flex gap-2">
            <span class="text-base-content/50 shrink-0">{Calendar.strftime(log.at, "%d/%m %H:%M:%S")}</span>
            <span class={["shrink-0 uppercase", level_class(log.level)]}>{log.level}</span>
            <span class="break-all">{log.message}</span>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  slot :inner_block

  defp stat(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-200 p-4">
      <p class="text-xs uppercase tracking-widest text-base-content/50">{@label}</p>
      <p class="text-3xl font-black mt-1">{@value}</p>
      <p class="text-xs text-base-content/60 mt-1">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, :refresh)

    {:ok,
     socket
     |> assign(page_title: "Supervision", media_usage: nil)
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("media_usage", _params, socket) do
    {:noreply, assign(socket, media_usage: Media.usage())}
  end

  def handle_event("sync_channels", _params, socket) do
    {:ok, _} = Quotor.Workers.SyncChannels.new(%{}) |> Oban.insert()
    {:noreply, put_flash(socket, :info, "Synchronisation des chaînes lancée.")}
  end

  def handle_event("retry_job", %{"id" => id}, socket) do
    Oban.retry_job(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Job relancé.") |> load()}
  end

  defp load(socket) do
    assign(socket,
      snap: Monitoring.snapshot(),
      warnings: Logs.recent(level: :warning, limit: 12)
    )
  end

  defp sum(map), do: map |> Map.values() |> Enum.sum()

  defp short_worker(worker), do: worker |> String.split(".") |> List.last()

  def level_class(level) when level in [:error, :critical, :alert, :emergency], do: "text-error"
  def level_class(:warning), do: "text-warning"
  def level_class(:info), do: "text-info"
  def level_class(_), do: "text-base-content/50"
end
