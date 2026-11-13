defmodule QuotorWeb.DiscoverLive do
  @moduledoc """
  Onglet « Découvrir » : les montages créés par les utilisateurs (et non les
  extraits bruts du catalogue), au hasard, par nouveautés ou par popularité.
  """
  use QuotorWeb, :live_view

  alias Quotor.{Media, Montages}

  @page_size 24
  @sorts [
    {"hasard", "Au hasard", "hero-sparkles", :random},
    {"recents", "Nouveautés", "hero-clock", :recent},
    {"populaires", "Populaires", "hero-fire", :popular}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="flex flex-wrap items-end justify-between gap-4 mb-6">
        <div>
          <h1 class="text-3xl font-black">Découvrir</h1>
          <p class="text-base-content/70">
            Les montages de la communauté : des phrases que personne n'a jamais dites.
          </p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <div class="inline-flex rounded-full bg-base-200 p-1 text-sm" role="tablist">
            <.link
              :for={{sort, label, icon, _} <- @sorts}
              patch={~p"/decouvrir?#{%{tri: sort}}"}
              role="tab"
              aria-selected={to_string(@sort == sort)}
              class={[
                "flex items-center gap-1.5 rounded-full px-4 py-1.5 transition-colors",
                if(@sort == sort,
                  do: "bg-primary text-primary-content font-semibold shadow",
                  else: "hover:bg-base-300"
                )
              ]}
            >
              <.icon name={icon} class="size-4" /> {label}
            </.link>
          </div>
          <button
            :if={@sort == "hasard"}
            id="shuffle"
            type="button"
            phx-click="shuffle"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Mélanger
          </button>
        </div>
      </div>

      <div
        id="discover"
        phx-update="stream"
        class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <div
          id="discover-empty"
          class="hidden only:block col-span-full rounded-2xl bg-base-200 p-10 text-center text-base-content/70"
        >
          Aucun montage pour l'instant.
          <.link navigate={~p"/?mode=advanced"} class="link link-primary">Crée le premier</.link>
          en mode avancé : tape une phrase, Quotor la fait dire par les vidéastes.
        </div>
        <.link
          :for={{dom_id, m} <- @streams.montages}
          id={dom_id}
          navigate={~p"/m/#{m.key}"}
          class="group rounded-2xl overflow-hidden bg-base-200 ring-1 ring-base-300 hover:ring-primary/60 hover:-translate-y-0.5 transition"
        >
          <div class="relative aspect-video bg-black">
            <img
              :if={Montages.poster_rel(m)}
              src={Media.url(Montages.poster_rel(m))}
              alt=""
              loading="lazy"
              class="w-full h-full object-cover opacity-90 group-hover:opacity-100 transition"
            />
            <span class="absolute inset-0 grid place-items-center">
              <span class="rounded-full bg-black/60 p-3 text-white group-hover:scale-110 transition">
                <.icon name="hero-play-solid" class="size-6" />
              </span>
            </span>
          </div>
          <div class="p-3">
            <p class="font-semibold line-clamp-2">« {m.query} »</p>
            <p class="mt-1 text-xs text-base-content/60">
              {length(m.segments)} extrait(s) · {m.views_count} vue(s) · {Calendar.strftime(
                m.inserted_at,
                "%d/%m/%Y"
              )}
            </p>
          </div>
        </.link>
      </div>

      <div :if={@has_more} class="mt-8 text-center">
        <button id="more" type="button" phx-click="more" class="btn btn-ghost">Voir plus</button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Découvrir", sorts: @sorts, sort: "hasard", offset: 0, has_more: false)
     |> stream(:montages, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sorts = Enum.map(@sorts, &elem(&1, 0))
    sort = if params["tri"] in sorts, do: params["tri"], else: "hasard"
    {:noreply, socket |> assign(sort: sort, offset: 0) |> load(reset: true)}
  end

  @impl true
  def handle_event("shuffle", _params, socket), do: {:noreply, load(socket, reset: true)}

  def handle_event("more", _params, socket) do
    {:noreply, socket |> assign(offset: socket.assigns.offset + @page_size) |> load(reset: false)}
  end

  defp load(socket, reset: reset?) do
    %{sort: sort, offset: offset} = socket.assigns
    {_, _, _, order} = List.keyfind(@sorts, sort, 0)

    {montages, has_more} =
      case order do
        :random ->
          {Montages.list_public(:random, @page_size), false}

        order ->
          page = Montages.list_public(order, @page_size + 1, offset)
          {Enum.take(page, @page_size), length(page) > @page_size}
      end

    socket
    |> assign(has_more: has_more)
    |> stream(:montages, montages, reset: reset?)
  end
end
