defmodule QuotorWeb.Admin.BackupsLive do
  @moduledoc """
  Sauvegardes de la base et des médias : état, lancement manuel,
  téléchargement, suppression et procédure de restauration.
  """
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.Backup
  alias Quotor.Workers.Backup, as: BackupWorker

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:backups}>
      <div class="flex flex-wrap items-center justify-between gap-3 mb-2">
        <h1 class="text-2xl font-black">Sauvegardes</h1>
        <button
          id="backup-now"
          type="button"
          phx-click="backup_now"
          disabled={@status.running?}
          class="btn btn-primary btn-sm"
        >
          <%= if @status.running? do %>
            <span class="loading loading-spinner loading-xs"></span> Sauvegarde en cours…
          <% else %>
            <.icon name="hero-arrow-down-tray" class="size-4" /> Sauvegarder maintenant
          <% end %>
        </button>
      </div>
      <p class="text-sm text-base-content/60 mb-6">
        Chaque sauvegarde est une archive <code>.tar</code>
        contenant la base PostgreSQL (<code>pg_dump</code>) et, si inclus, les fichiers médias.
      </p>

      <section id="backup-settings" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 mb-6">
        <div class="rounded-2xl bg-base-200 p-4">
          <p class="text-xs uppercase tracking-wider text-base-content/50">Planification</p>
          <p class="font-semibold mt-1">
            {if @enabled?, do: "Chaque nuit, 2 h UTC", else: "Désactivée"}
          </p>
        </div>
        <div class="rounded-2xl bg-base-200 p-4">
          <p class="text-xs uppercase tracking-wider text-base-content/50">Rétention</p>
          <p class="font-semibold mt-1">{@keep} dernières</p>
        </div>
        <div class="rounded-2xl bg-base-200 p-4">
          <p class="text-xs uppercase tracking-wider text-base-content/50">Médias</p>
          <p class="font-semibold mt-1">
            {if @media?, do: "Inclus", else: "Non inclus"}
          </p>
          <p :if={!@media? and !@local_storage?} class="text-xs text-base-content/60 mt-1">
            déjà hors serveur (S3/R2) — <code>BACKUP_MEDIA=always</code> pour les inclure
          </p>
        </div>
        <div class="rounded-2xl bg-base-200 p-4 min-w-0">
          <p class="text-xs uppercase tracking-wider text-base-content/50">Destination</p>
          <p class="font-semibold mt-1 break-all">{@destination}</p>
        </div>
      </section>

      <div
        :if={@stale?}
        id="backup-stale"
        class="alert alert-warning mb-4 text-sm"
      >
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          <%= if @backups == [] do %>
            Aucune sauvegarde pour l'instant.
          <% else %>
            Dernière sauvegarde il y a plus de 36 h.
          <% end %>
        </span>
      </div>

      <div :if={@status.failure} id="backup-failure" class="alert alert-error mb-4 text-sm">
        <.icon name="hero-x-circle" class="size-5" />
        <div>
          <p class="font-semibold">
            Échec le {format_dt(elem(@status.failure, 0))}
          </p>
          <p class="font-mono text-xs break-all">{elem(@status.failure, 1)}</p>
        </div>
      </div>

      <div :if={@ephemeral?} id="backup-ephemeral" class="alert alert-warning mb-4 text-sm">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          Site et workers sont séparés : les sauvegardes locales restent sur le disque du worker qui
          les a faites. Définissez <code>BACKUP_S3_BUCKET</code> (bucket privé) pour les centraliser.
        </span>
      </div>

      <div class="overflow-x-auto rounded-2xl bg-base-200 mb-8">
        <table class="table table-sm" id="backups">
          <thead>
            <tr>
              <th>Sauvegarde</th>
              <th>Date (UTC)</th>
              <th>Taille</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@backups == []}>
              <td colspan="4" class="text-center text-base-content/60 py-6">
                Aucune sauvegarde.
              </td>
            </tr>
            <tr :for={b <- @backups} id={"backup-" <> String.replace(b.name, ".", "-")}>
              <td class="font-mono text-xs">{b.name}</td>
              <td class="text-xs">{format_dt(b.at)}</td>
              <td class="text-xs">{Backup.format_size(b.size)}</td>
              <td class="text-right whitespace-nowrap">
                <a
                  href={~p"/admin/sauvegardes/#{b.name}"}
                  class="btn btn-xs btn-ghost"
                  download={b.name}
                >
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Télécharger
                </a>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-name={b.name}
                  data-confirm={"Supprimer définitivement #{b.name} ?"}
                  class="btn btn-xs btn-ghost text-error"
                  aria-label={"Supprimer #{b.name}"}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <section id="restore-help" class="rounded-2xl bg-base-200 p-5 text-sm space-y-3">
        <h2 class="text-lg font-bold">Restaurer</h2>
        <p class="text-base-content/70">
          La restauration <strong>remplace</strong>
          la base et réécrit les médias de l'archive. Elle se lance en ligne de commande, de
          préférence workers arrêtés, puis on redémarre l'application.
        </p>
        <pre class="bg-base-300 rounded-xl p-3 text-xs overflow-x-auto"><code>{restore_command(@backups)}</code></pre>
        <p class="text-base-content/70">
          Depuis une archive téléchargée : copiez-la dans le conteneur
          (<code>docker cp</code>) et passez son chemin. Options : <code>media: false</code>
          (base seule), <code>database: false</code>
          (médias seuls).
        </p>
      </section>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Sauvegardes",
       enabled?: Backup.enabled?(),
       keep: Backup.keep(),
       media?: Backup.include_media?(),
       local_storage?: Quotor.Storage.local?(),
       destination: Backup.destination_label(),
       ephemeral?:
         match?({:local, _}, Backup.destination()) and
           Application.get_env(:quotor, :role, :all) != :all
     )
     |> load()}
  end

  @impl true
  def handle_event("backup_now", _params, socket) do
    case BackupWorker.enqueue() do
      {:ok, :started} ->
        Logger.info("admin : sauvegarde manuelle lancée")
        {:noreply, socket |> put_flash(:info, "Sauvegarde lancée en arrière-plan.") |> load()}

      {:ok, :already_running} ->
        {:noreply, socket |> put_flash(:info, "Une sauvegarde est déjà en cours.") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Impossible de lancer la sauvegarde.")}
    end
  end

  def handle_event("delete", %{"name" => name}, socket) do
    if Backup.valid_name?(name) do
      Backup.delete(name)
      Logger.info("admin : sauvegarde #{name} supprimée")
      {:noreply, socket |> put_flash(:info, "Sauvegarde supprimée.") |> load()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    status = BackupWorker.status()
    backups = Backup.list()

    stale? =
      case backups do
        [%{at: %DateTime{} = at} | _] -> DateTime.diff(DateTime.utc_now(), at, :hour) >= 36
        _ -> true
      end

    # tant qu'une sauvegarde tourne, on rafraîchit (le worker peut être sur une autre machine)
    if status.running? and connected?(socket), do: Process.send_after(self(), :refresh, 3_000)

    assign(socket, status: status, backups: backups, stale?: stale?)
  end

  defp format_dt(nil), do: "—"
  defp format_dt(dt), do: Calendar.strftime(dt, "%d/%m/%Y %H:%M")

  defp restore_command(backups) do
    name =
      case backups do
        [%{name: name} | _] -> name
        [] -> "quotor-AAAAMMJJ-HHMMSS.tar"
      end

    """
    # image Docker (docker exec, ou Shell Render)
    bin/quotor eval 'Quotor.Release.restore("#{name}")'

    # environnement de développement
    docker compose -f docker-compose.dev.yml exec app mix run -e 'Quotor.Backup.restore("#{name}") |> IO.inspect()'

    # lister les sauvegardes / en créer une
    bin/quotor eval 'Quotor.Release.backups()'
    bin/quotor eval 'Quotor.Release.backup()'\
    """
  end
end
