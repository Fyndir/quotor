defmodule QuotorWeb.MontageLive do
  @moduledoc "Page partageable d'un montage."
  use QuotorWeb, :live_view

  alias Quotor.Montages

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <h1 class="text-2xl sm:text-3xl font-extrabold mb-6">« {@montage.query} »</h1>
        <.montage_player montage={@montage} />
        <p class="mt-4 text-xs text-base-content/50">
          Montage parodique composé d'extraits de leurs auteurs respectifs — les personnes
          apparaissant n'ont pas réellement prononcé cette phrase.
        </p>
        <div class="mt-6 flex gap-2">
          <.link navigate={~p"/?#{%{q: @montage.query, mode: "advanced"}}"} class="btn btn-ghost">
            <.icon name="hero-scissors" class="size-4" /> Faire le mien
          </.link>
          <.link navigate={~p"/signaler?#{%{montage: @montage.key}}"} class="btn btn-ghost btn-sm">
            <.icon name="hero-flag" class="size-4" /> Signaler
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    case Montages.get_by_key(key) do
      nil ->
        raise QuotorWeb.NotFoundError

      montage ->
        {:ok,
         assign(socket,
           montage: montage,
           page_title: montage.query,
           og: QuotorWeb.OpenGraph.for_montage(montage)
         )}
    end
  end
end
