defmodule QuotorWeb.Admin.ChannelsLive do
  @moduledoc """
  Chaînes suivies : leurs dernières vidéos sont ajoutées automatiquement
  chaque nuit (cron Oban), ou à la demande.
  """
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.Catalog
  alias Quotor.Catalog.Channel

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:channels}>
      <h1 class="text-2xl font-black mb-2">Chaînes suivies</h1>
      <p class="text-sm text-base-content/60 mb-6">
        Les chaînes activées sont synchronisées chaque nuit à 4 h (UTC) : leurs N dernières vidéos
        sont ajoutées au catalogue. Vérifiez l'URL de chaque chaîne avant de l'activer.
      </p>

      <section class="rounded-2xl bg-base-200 p-5 mb-6">
        <.form
          for={@form}
          id="channel-form"
          phx-submit="save"
          phx-change="validate"
          class="grid gap-3 sm:grid-cols-[1fr_2fr_auto_auto] items-end"
        >
          <.input field={@form[:name]} type="text" label="Nom" />
          <.input field={@form[:url]} type="url" label="URL (https://www.youtube.com/@…)" />
          <.input field={@form[:max_videos]} type="number" label="Vidéos" min="1" max="200" />
          <.button class="btn btn-primary mb-2">Ajouter</.button>
        </.form>
      </section>

      <div class="overflow-x-auto rounded-2xl bg-base-200">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Chaîne</th>
              <th>Suivi</th>
              <th>Vidéos max.</th>
              <th>Dernière synchro</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={channel <- @channels} id={"channel-#{channel.id}"}>
              <td>
                <div class="font-semibold">{channel.name}</div>
                <a
                  href={channel.url}
                  target="_blank"
                  rel="noopener"
                  class="text-xs link text-base-content/60"
                >
                  {channel.url}
                </a>
                <div :if={channel.last_error} class="text-xs text-error">{channel.last_error}</div>
              </td>
              <td>
                <input
                  type="checkbox"
                  class="toggle toggle-sm toggle-primary"
                  checked={channel.enabled}
                  phx-click="toggle"
                  phx-value-id={channel.id}
                  aria-label={"Suivre #{channel.name}"}
                />
              </td>
              <td>{channel.max_videos}</td>
              <td class="text-xs">
                {if channel.last_synced_at,
                  do: Calendar.strftime(channel.last_synced_at, "%d/%m/%Y %H:%M"),
                  else: "jamais"}
              </td>
              <td class="text-right whitespace-nowrap">
                <button
                  type="button"
                  phx-click="sync"
                  phx-value-id={channel.id}
                  class="btn btn-xs btn-ghost"
                >
                  <.icon name="hero-arrow-path" class="size-4" /> Synchroniser
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={channel.id}
                  data-confirm="Ne plus suivre cette chaîne ? (les vidéos déjà importées sont conservées)"
                  class="btn btn-xs btn-ghost text-error"
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
    {:ok,
     socket
     |> assign(page_title: "Chaînes suivies", form: to_form(Catalog.change_channel(%Channel{})))
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"channel" => params}, socket) do
    cs = %Channel{} |> Catalog.change_channel(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(cs))}
  end

  def handle_event("save", %{"channel" => params}, socket) do
    case Catalog.create_channel(params) do
      {:ok, channel} ->
        Logger.info("admin : chaîne #{channel.name} ajoutée")

        {:noreply,
         socket
         |> put_flash(:info, "Chaîne ajoutée (désactivée : activez-la pour la suivre).")
         |> assign(form: to_form(Catalog.change_channel(%Channel{})))
         |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    channel = Catalog.get_channel!(id)
    {:ok, _} = Catalog.update_channel(channel, %{enabled: !channel.enabled})
    {:noreply, load(socket)}
  end

  def handle_event("sync", %{"id" => id}, socket) do
    {:ok, _} =
      %{channel_id: String.to_integer(id)} |> Quotor.Workers.SyncChannels.new() |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Synchronisation lancée en arrière-plan.")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Catalog.get_channel!() |> Catalog.delete_channel()
    {:noreply, load(socket)}
  end

  defp load(socket), do: assign(socket, channels: Catalog.list_channels())
end
