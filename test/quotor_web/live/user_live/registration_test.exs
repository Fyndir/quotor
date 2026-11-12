defmodule QuotorWeb.UserLive.RegistrationTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.AccountsFixtures

  describe "page d'inscription" do
    test "s'affiche", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Créer un compte"
      assert html =~ "Connectez-vous"
    end

    test "redirige un utilisateur déjà connecté", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "affiche les erreurs de validation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "court"})

      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 12 character"
    end
  end

  describe "inscription" do
    test "crée un compte confirmé et ouvre la session", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form", user: %{email: email, password: valid_user_password()})

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      user = Quotor.Accounts.get_user_by_email(email)
      assert user.confirmed_at
      assert user.role == "user"
    end

    test "refuse un email déjà utilisé", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => valid_user_password()}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end
end
