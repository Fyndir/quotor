defmodule QuotorWeb.Admin.UsersLive do
  @moduledoc "Gestion des utilisateurs : rôle (utilisateur / admin) et bannissement."
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.Accounts
  alias Quotor.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:users}>
      <h1 class="text-2xl font-black mb-4">Utilisateurs</h1>

      <.form for={@filter} id="user-filter" phx-change="filter" class="mb-4">
        <input
          type="search"
          name="search"
          value={@filter[:search].value}
          placeholder="Rechercher par email…"
          phx-debounce="300"
          class="input input-sm w-full max-w-sm"
        />
      </.form>

      <div class="overflow-x-auto rounded-2xl bg-base-200">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Email</th>
              <th>Rôle</th>
              <th>Inscription</th>
              <th>État</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={user <- @users} id={"user-#{user.id}"}>
              <td>{user.email}</td>
              <td>
                <span class={["badge badge-sm", user.role == "admin" && "badge-primary"]}>{user.role}</span>
              </td>
              <td class="text-xs">{Calendar.strftime(user.inserted_at, "%d/%m/%Y")}</td>
              <td>
                <span :if={User.banned?(user)} class="badge badge-sm badge-error">banni</span>
                <span :if={!User.banned?(user)} class="badge badge-sm badge-ghost">actif</span>
              </td>
              <td class="text-right whitespace-nowrap">
                <%= if user.id != @current_scope.user.id do %>
                  <button
                    type="button"
                    phx-click="set_role"
                    phx-value-id={user.id}
                    phx-value-role={if user.role == "admin", do: "user", else: "admin"}
                    data-confirm={
                      if user.role == "admin",
                        do: "Retirer les droits admin ?",
                        else: "Donner les droits admin ?"
                    }
                    class="btn btn-xs btn-ghost"
                  >
                    {if user.role == "admin", do: "Rétrograder", else: "Promouvoir admin"}
                  </button>
                  <button
                    type="button"
                    phx-click="toggle_ban"
                    phx-value-id={user.id}
                    data-confirm={
                      if User.banned?(user),
                        do: "Lever le bannissement ?",
                        else: "Bannir cet utilisateur ?"
                    }
                    class={["btn btn-xs btn-ghost", !User.banned?(user) && "text-error"]}
                  >
                    {if User.banned?(user), do: "Débannir", else: "Bannir"}
                  </button>
                <% else %>
                  <span class="text-xs text-base-content/50">vous</span>
                <% end %>
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
     socket |> assign(page_title: "Utilisateurs", filter: to_form(%{"search" => ""})) |> load()}
  end

  @impl true
  def handle_event("filter", %{"search" => search}, socket) do
    {:noreply, socket |> assign(filter: to_form(%{"search" => search})) |> load()}
  end

  def handle_event("set_role", %{"id" => id, "role" => role}, socket) do
    with user when user.id != socket.assigns.current_scope.user.id <- Accounts.get_user!(id),
         {:ok, user} <- Accounts.set_user_role(user, role) do
      Logger.info("admin : #{user.email} passe #{role}")
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Action impossible.")}
    end
  end

  def handle_event("toggle_ban", %{"id" => id}, socket) do
    with user when user.id != socket.assigns.current_scope.user.id <- Accounts.get_user!(id),
         {:ok, user} <- Accounts.set_user_banned(user, !User.banned?(user)) do
      Logger.info("admin : #{user.email} #{if User.banned?(user), do: "banni", else: "débanni"}")
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Action impossible.")}
    end
  end

  defp load(socket),
    do: assign(socket, users: Accounts.list_users(search: socket.assigns.filter[:search].value))
end
