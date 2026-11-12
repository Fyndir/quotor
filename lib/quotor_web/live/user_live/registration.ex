defmodule QuotorWeb.UserLive.Registration do
  @moduledoc """
  Inscription par email + mot de passe. Le compte est utilisable
  immédiatement (pas besoin de serveur SMTP) : après création, le formulaire
  est soumis à `/users/log-in` pour ouvrir la session.
  """
  use QuotorWeb, :live_view

  require Logger

  alias Quotor.Accounts
  alias Quotor.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Créer un compte
            <:subtitle>
              Déjà inscrit ?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
                Connectez-vous
              </.link>
              à votre compte.
            </:subtitle>
          </.header>
        </div>

        <p class="text-sm text-base-content/70 mb-4">
          Un compte permet de garder ses extraits favoris et l'historique de ses montages. La
          recherche reste accessible sans compte.
        </p>

        <.form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
          method="post"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Mot de passe (12 caractères minimum)"
            autocomplete="new-password"
            required
          />
          <input type="hidden" name={@form[:remember_me].name} value="true" />

          <p class="text-xs text-base-content/60 mb-4">
            En créant un compte, vous acceptez les <.link navigate={~p"/conditions"} class="underline">conditions d'utilisation</.link>.
          </p>

          <.button phx-disable-with="Création du compte…" class="btn btn-primary w-full">
            Créer mon compte
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: QuotorWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(trigger_submit: false, page_title: "Créer un compte")
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user_with_password(user_params) do
      {:ok, user} ->
        Logger.info("nouvel utilisateur #{user.id}")
        changeset = Accounts.change_user_registration(user, user_params, validate_unique: false)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
