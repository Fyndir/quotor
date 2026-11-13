defmodule QuotorWeb.MyMontagesLive do
  @moduledoc "Historique des montages de l'utilisateur connecté."
  use QuotorWeb, :live_view

  alias Quotor.{Media, Montages}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <h1 class="text-3xl font-black mb-6">Mes montages</h1>
      <div :if={@montages == []} class="rounded-2xl bg-base-200 p-10 text-center text-base-content/70">
        Aucun montage pour l'instant.
        <.link navigate={~p"/?mode=advanced"} class="link link-primary">Crée le premier</.link>
        en mode avancé.
      </div>
      <div class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={m <- @montages}
          navigate={~p"/m/#{m.key}"}
          class="group rounded-2xl overflow-hidden bg-base-200 ring-1 ring-base-300 hover:ring-primary/60 transition"
        >
          <video
            src={Media.url(m.file_path)}
            preload="metadata"
            muted
            class="w-full aspect-video bg-black object-cover"
          ></video>
          <div class="p-3">
            <p class="font-semibold truncate">« {m.query} »</p>
            <p class="text-xs text-base-content/60">
              {length(m.segments)} extrait(s) · {m.views_count} vue(s) · {Calendar.strftime(
                m.updated_at,
                "%d/%m/%Y"
              )}
              <span :if={!m.listed} class="badge badge-xs ml-1">hors Découvrir</span>
            </p>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Mes montages",
       montages: Montages.list_for_user(socket.assigns.current_scope)
     )}
  end
end
