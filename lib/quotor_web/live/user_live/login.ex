defmodule QuotorWeb.UserLive.Login do
  use QuotorWeb, :live_view

  alias Quotor.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Connexion</p>
            <:subtitle>
              <%= if @current_scope do %>
                Merci de vous reconnecter pour effectuer cette action sensible.
              <% else %>
                Pas encore de compte ? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-primary hover:underline"
                  phx-no-format
                >Inscrivez-vous</.link> gratuitement.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>Adaptateur d'emails local (développement).</p>
            <p>
              Les emails envoyés sont visibles sur <.link href="/dev/mailbox" class="underline">la boîte de test</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
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
            label="Mot de passe"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Se connecter et rester connecté <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Se connecter pour cette fois
          </.button>
        </.form>

        <%= if magic_link_enabled?() do %>
          <div class="divider">ou</div>

          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log-in"}
            phx-submit="submit_magic"
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.button class="btn btn-ghost w-full">
              Recevoir un lien de connexion par email <span aria-hidden="true">→</span>
            </.button>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, page_title: "Connexion")}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "Si votre adresse est connue, vous allez recevoir un lien de connexion par email."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:quotor, Quotor.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  # Sans SMTP configuré (adaptateur Logger), le lien magique est masqué.
  defp magic_link_enabled? do
    Application.get_env(:quotor, Quotor.Mailer)[:adapter] != Swoosh.Adapters.Logger
  end
end
