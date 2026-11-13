defmodule QuotorWeb.HomeLive do
  @moduledoc """
  Page d'accueil : champ de recherche.

    * mode **standard** : les extraits correspondant au texte ;
    * mode **avancé** : un montage qui assemble plusieurs extraits pour former
      la phrase demandée.
  """
  use QuotorWeb, :live_view

  alias Quotor.{Catalog, Montages, RateLimit, Search, Suggestions}
  alias Quotor.Accounts.Scope

  @page_size 24
  # Montages : 20 par tranche de 10 minutes (anonymes : par IP)
  @montage_limit 20
  @montage_window :timer.minutes(10)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <section class="search-hero -mx-4 sm:-mx-6 lg:-mx-8 -mt-8 px-4 sm:px-6 lg:px-8 pt-12 pb-10 mb-8">
        <div class="mx-auto max-w-3xl text-center">
          <h1 class="text-4xl sm:text-6xl font-black tracking-tight">
            Trouve <span class="text-primary">la</span> réplique.
          </h1>
          <p class="mt-3 text-base-content/70 sm:text-lg">
            Des extraits vidéo, avec le son, des vidéastes français. Tape une phrase, on trouve qui
            l'a dite — ou on la leur fait dire.
          </p>

          <.form
            for={@form}
            id="search-form"
            phx-submit="search"
            phx-change="typing"
            class="mt-8"
          >
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-5 top-1/2 -translate-y-1/2 size-6 text-base-content/40 pointer-events-none"
              />
              <input
                type="search"
                name="q"
                id="search-input"
                value={@form[:q].value}
                placeholder={
                  if @mode == "advanced",
                    do: "Une phrase à faire dire… ex : « je suis pas venu ici pour souffrir »",
                    else: "Rechercher une réplique…"
                }
                autocomplete="off"
                maxlength="300"
                phx-debounce="300"
                class="w-full rounded-full bg-base-100 border-2 border-base-300 focus:border-primary focus:outline-none pl-14 pr-32 py-4 text-lg shadow-lg transition-colors"
                aria-label="Recherche"
              />
              <button
                type="submit"
                class="absolute right-2 top-1/2 -translate-y-1/2 btn btn-primary rounded-full px-6"
                phx-disable-with="…"
              >
                {if @mode == "advanced", do: "Monter", else: "Chercher"}
              </button>
            </div>
            <input type="hidden" name="mode" value={@mode} />
          </.form>

          <div class="mt-4 inline-flex rounded-full bg-base-200 p-1 text-sm" role="tablist">
            <button
              :for={
                {mode, label, icon} <- [
                  {"standard", "Standard", "hero-film"},
                  {"advanced", "Avancé · montage", "hero-scissors"}
                ]
              }
              type="button"
              role="tab"
              aria-selected={to_string(@mode == mode)}
              phx-click="set_mode"
              phx-value-mode={mode}
              class={[
                "flex items-center gap-1.5 rounded-full px-4 py-1.5 transition-colors",
                if(@mode == mode,
                  do: "bg-primary text-primary-content font-semibold shadow",
                  else: "hover:bg-base-300"
                )
              ]}
            >
              <.icon name={icon} class="size-4" /> {label}
            </button>
          </div>
          <p :if={@mode == "advanced"} class="mt-2 text-xs text-base-content/60">
            Le montage cherche les plus longs morceaux de ta phrase dans le catalogue, puis les
            assemble.
          </p>
        </div>
      </section>

      <%!-- Idées de phrases (mode avancé) --%>
      <.ideas
        :if={@mode == "advanced" and @query == ""}
        ideas={@ideas}
        title="En manque d'idée ? Essaie :"
      />

      <%!-- Mode avancé --%>
      <section :if={@mode == "advanced" and @query != ""} class="mx-auto max-w-3xl mb-10">
        <div :if={@montage_loading} class="rounded-2xl bg-base-200 p-10 text-center">
          <span class="loading loading-dots loading-lg text-primary"></span>
          <p class="mt-3 text-base-content/70">Montage en cours, puis vérification à l’écoute…</p>
        </div>
        <div :if={!@montage_loading and @montage}>
          <.montage_player montage={@montage} />
          <div class="mt-3 text-center">
            <button type="button" phx-click="remix" class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-path" class="size-4" /> Autre version
            </button>
          </div>
        </div>
        <div
          :if={!@montage_loading and @montage_error}
          class="rounded-2xl bg-base-200 p-8 text-center text-base-content/70"
        >
          <.icon name="hero-face-frown" class="size-8 mb-2" />
          <p>{@montage_error}</p>
        </div>
        <div :if={!@montage_loading} class="mt-8">
          <.ideas ideas={Enum.take(@ideas, 3)} title="Une autre idée ?" />
        </div>
      </section>

      <%!-- Mode standard --%>
      <section :if={@mode == "standard" and @query != ""}>
        <div
          :if={@authors_found != []}
          id="authors-found"
          class="flex flex-wrap items-center gap-2 mb-6"
        >
          <span class="text-sm text-base-content/60">Auteurs :</span>
          <.link
            :for={author <- @authors_found}
            navigate={~p"/auteurs/#{author.slug}"}
            class="badge badge-lg gap-1 bg-base-200 border-base-300 hover:bg-primary hover:text-primary-content"
          >
            <.icon name="hero-user-micro" class="size-4" /> {author.name}
          </.link>
        </div>
        <h2 class="text-sm uppercase tracking-widest text-base-content/50 mb-4">
          Résultats pour « {@query} »
        </h2>
        <div
          id="results"
          phx-update="stream"
          class="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
        >
          <div
            id="results-empty"
            class="hidden only:block col-span-full rounded-2xl bg-base-200 p-10 text-center text-base-content/70"
          >
            Aucune réplique trouvée. Essaie le mode <button
              type="button"
              phx-click="set_mode"
              phx-value-mode="advanced"
              class="link link-primary"
            >avancé</button>, qui assemble des morceaux de phrases.
          </div>
          <.quote_card
            :for={{dom_id, quote} <- @streams.quotes}
            id={dom_id}
            quote={quote}
            favorite={MapSet.member?(@favorites, quote.id)}
            can_favorite={@can_favorite}
          />
        </div>
        <div :if={@has_more} class="mt-8 text-center">
          <button type="button" phx-click="more" class="btn btn-ghost">Voir plus</button>
        </div>
      </section>

      <%!-- Pas encore de recherche : renvoi vers l'onglet Découvrir --%>
      <p :if={@query == ""} id="discover-hint" class="text-center text-sm text-base-content/60">
        Pas d'idée ?
        <.link navigate={~p"/decouvrir"} class="link link-primary font-semibold">
          Parcours l'onglet Découvrir
        </.link>
        pour écouter des répliques au hasard.
      </p>
    </Layouts.app>
    """
  end

  attr :ideas, :list, required: true
  attr :title, :string, required: true

  # Idées de phrases montables (cf. Quotor.Suggestions) : un clic lance le montage.
  defp ideas(assigns) do
    ~H"""
    <section :if={@ideas != []} id="ideas" class="mx-auto max-w-3xl mb-10">
      <div class="flex items-center justify-between gap-2 mb-3">
        <h2 class="text-sm font-semibold text-base-content/70 flex items-center gap-1.5">
          <.icon name="hero-light-bulb" class="size-4" /> {@title}
        </h2>
        <button id="more-ideas" type="button" phx-click="more_ideas" class="btn btn-ghost btn-xs">
          <.icon name="hero-arrow-path" class="size-3.5" /> Autres idées
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <.link
          :for={{idea, i} <- Enum.with_index(@ideas)}
          id={"idea-#{i}"}
          patch={~p"/?#{%{q: idea, mode: "advanced"}}"}
          class="segment-chip rounded-full bg-base-200 hover:bg-primary hover:text-primary-content px-4 py-2 text-sm transition-colors"
          style={"animation-delay: #{i * 50}ms"}
        >
          « {idea} »
        </.link>
      </div>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Recherche",
       can_favorite: Scope.user?(socket.assigns.current_scope),
       favorites: MapSet.new(),
       query: "",
       mode: "standard",
       offset: 0,
       has_more: false,
       montage: nil,
       montage_loading: false,
       montage_error: nil,
       authors_found: [],
       ideas: [],
       form: to_form(%{"q" => ""})
     )
     |> stream(:quotes, [])
     |> QuotorWeb.LiveHelpers.assign_rate_key()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim() |> String.slice(0, 300)
    mode = if params["mode"] == "advanced", do: "advanced", else: "standard"

    socket =
      socket
      |> assign(query: query, mode: mode, form: to_form(%{"q" => query}), montage_error: nil)
      |> assign(page_title: if(query == "", do: "Recherche", else: query))

    {:noreply, run(socket)}
  end

  defp run(%{assigns: %{query: ""}} = socket) do
    ideas =
      if socket.assigns.mode == "advanced" and connected?(socket),
        do: Suggestions.random(),
        else: []

    socket
    |> assign(ideas: ideas)
    |> assign(has_more: false, montage: nil, montage_loading: false)
    |> stream(:quotes, [], reset: true)
  end

  defp run(%{assigns: %{mode: "standard", query: query}} = socket) do
    quotes = Search.search(query, limit: @page_size + 1)

    socket
    |> assign(
      offset: 0,
      has_more: length(quotes) > @page_size,
      authors_found: Catalog.search_authors(query)
    )
    |> then(fn s ->
      quotes = Enum.take(quotes, @page_size)
      s |> assign_favorites(quotes) |> stream(:quotes, quotes, reset: true)
    end)
  end

  defp run(%{assigns: %{mode: "advanced"}} = socket) do
    socket = if connected?(socket), do: assign(socket, ideas: Suggestions.random()), else: socket

    if connected?(socket),
      do: start_montage(socket, false),
      else: assign(socket, montage_loading: true)
  end

  defp start_montage(socket, shuffle?) do
    case RateLimit.hit({:montage, socket.assigns.rate_key}, @montage_limit, @montage_window) do
      :ok ->
        query = socket.assigns.query
        scope = socket.assigns.current_scope

        socket
        |> assign(montage_loading: true, montage: nil, montage_error: nil)
        |> start_async(:montage, fn -> Montages.build(query, scope, shuffle: shuffle?) end)

      {:error, :rate_limited} ->
        assign(socket,
          montage_loading: false,
          montage: nil,
          montage_error: "Trop de montages d'un coup ! Réessaie dans quelques minutes."
        )
    end
  end

  @impl true
  def handle_async(:montage, {:ok, result}, socket) do
    socket = assign(socket, montage_loading: false)

    case result do
      {:ok, montage} ->
        {:noreply, assign(socket, montage: montage)}

      {:error, :no_match} ->
        {:noreply,
         assign(socket,
           montage_error: "Aucun mot de cette phrase n'a été trouvé dans le catalogue."
         )}

      {:error, :empty} ->
        {:noreply, assign(socket, montage_error: nil)}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, montage_error: message)}
    end
  end

  def handle_async(:montage, {:exit, _reason}, socket) do
    {:noreply, assign(socket, montage_loading: false, montage_error: "Le montage a échoué.")}
  end

  @impl true
  def handle_event("search", %{"q" => q} = params, socket) do
    mode = Map.get(params, "mode", socket.assigns.mode)
    {:noreply, push_patch(socket, to: search_path(q, mode))}
  end

  # En mode standard, recherche au fil de la frappe ; en mode avancé, on
  # attend la validation (un montage coûte du CPU).
  def handle_event("typing", %{"q" => q}, %{assigns: %{mode: "standard"}} = socket) do
    {:noreply, push_patch(socket, to: search_path(q, "standard"), replace: true)}
  end

  def handle_event("typing", %{"q" => q}, socket) do
    {:noreply, assign(socket, form: to_form(%{"q" => q}))}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    q = socket.assigns.form[:q].value || socket.assigns.query
    {:noreply, push_patch(socket, to: search_path(q, mode))}
  end

  def handle_event("remix", _params, socket) do
    {:noreply, start_montage(socket, true)}
  end

  def handle_event("more_ideas", _params, socket) do
    {:noreply, assign(socket, ideas: Suggestions.random())}
  end

  def handle_event("more", _params, socket) do
    offset = socket.assigns.offset + @page_size
    quotes = Search.search(socket.assigns.query, limit: @page_size + 1, offset: offset)
    page = Enum.take(quotes, @page_size)

    {:noreply,
     socket
     |> assign(offset: offset, has_more: length(quotes) > @page_size)
     |> assign_favorites(page, true)
     |> stream(:quotes, page)}
  end

  def handle_event("toggle_favorite", %{"id" => id}, socket) do
    {:noreply, toggle_favorite(socket, String.to_integer(id))}
  end

  defp toggle_favorite(socket, id) do
    scope = socket.assigns.current_scope

    if Scope.user?(scope) do
      favorites =
        case Catalog.toggle_favorite(scope, id) do
          :added -> MapSet.put(socket.assigns.favorites, id)
          :removed -> MapSet.delete(socket.assigns.favorites, id)
        end

      socket = assign(socket, favorites: favorites)

      case Catalog.get_public_quote(id) do
        nil ->
          socket

        quote ->
          stream_insert(socket, :quotes, quote)
      end
    else
      put_flash(socket, :error, "Connecte-toi pour garder tes favoris.")
    end
  end

  defp assign_favorites(socket, quotes, merge? \\ false) do
    ids = Catalog.favorite_ids(socket.assigns.current_scope, Enum.map(quotes, & &1.id))
    ids = if merge?, do: MapSet.union(socket.assigns.favorites, ids), else: ids
    assign(socket, favorites: ids)
  end

  defp search_path(q, mode) do
    q = String.trim(q || "")

    params =
      %{}
      |> then(&if(q != "", do: Map.put(&1, "q", q), else: &1))
      |> then(&if(mode == "advanced", do: Map.put(&1, "mode", "advanced"), else: &1))

    ~p"/?#{params}"
  end
end
