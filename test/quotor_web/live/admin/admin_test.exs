defmodule QuotorWeb.Admin.AdminTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.AccountsFixtures
  import Quotor.CatalogFixtures

  alias Quotor.{Accounts, Catalog}

  @pages ~w(/admin /admin/sources /admin/chaines /admin/quotes /admin/signalements /admin/utilisateurs /admin/logs /admin/sauvegardes)

  describe "contrôle d'accès" do
    test "un anonyme est redirigé vers l'accueil", %{conn: conn} do
      for page <- @pages do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, page)
      end

      assert redirected_to(get(conn, "/admin/oban")) == "/"
      assert redirected_to(get(conn, "/admin/dashboard")) == "/"
    end

    test "un utilisateur standard n'a pas accès", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      for page <- @pages do
        assert {:error,
                {:redirect, %{to: "/", flash: %{"error" => "Accès réservé aux administrateurs."}}}} =
                 live(conn, page)
      end
    end

    test "un admin accède à toutes les pages", %{conn: conn} do
      %{conn: conn} = register_and_log_in_admin(%{conn: conn})

      for page <- @pages do
        assert {:ok, _view, _html} = live(conn, page)
      end

      # (Oban Web nécessite Oban.Met, non démarré en mode test :manual)
      assert get(conn, "/admin/dashboard").status in [200, 302]
    end
  end

  describe "en tant qu'admin" do
    setup :register_and_log_in_admin

    test "supervision", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Supervision"
      assert html =~ "Base de données"
      assert html =~ "Tâches de fond"
    end

    test "ajout de vidéos YouTube particulières", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/sources")

      html =
        view
        |> form("#url-form", %{
          urls: "https://youtu.be/ccccccccccc\nhttps://example.com/pas-youtube"
        })
        |> render_submit()

      assert html =~ "1 vidéo(s) en file de traitement"
      assert html =~ "URL YouTube invalide"

      [source] = Catalog.list_sources()
      assert source.youtube_id == "ccccccccccc"
      assert_enqueued(worker: Quotor.Workers.IngestSource, args: %{source_id: source.id})
    end

    test "masquer une quote", %{conn: conn} do
      [quote] = quotes_fixture(source_fixture(), ["Coucou les amis."])
      {:ok, view, _html} = live(conn, ~p"/admin/quotes")

      view |> element("#admin-quote-#{quote.id} button[phx-click=toggle]") |> render_click()
      refute Catalog.get_quote!(quote.id).enabled
    end

    test "traiter un signalement en masquant la vidéo", %{conn: conn} do
      source = source_fixture()
      [quote] = quotes_fixture(source, ["Coucou les amis."])

      {:ok, report} =
        Catalog.create_report(%{
          reason: "copyright",
          message: "Merci de retirer ma vidéo.",
          contact_name: "A",
          contact_email: "a@example.com",
          quote_id: quote.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/signalements")
      view |> element("#report-#{report.id} button[phx-click=hide_source]") |> render_click()

      refute Catalog.get_source!(source.id).enabled
      assert Catalog.get_report!(report.id).status == "resolved"
    end

    test "promouvoir et bannir un utilisateur", %{conn: conn} do
      other = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/utilisateurs")

      view |> element("#user-#{other.id} button[phx-click=set_role]") |> render_click()
      assert Accounts.get_user!(other.id).role == "admin"

      view |> element("#user-#{other.id} button[phx-click=toggle_ban]") |> render_click()
      banned = Accounts.get_user!(other.id)
      assert Quotor.Accounts.User.banned?(banned)

      # un utilisateur banni ne peut plus se connecter
      assert Accounts.get_user_by_email_and_password(banned.email, valid_user_password()) == nil
    end

    test "chaînes suivies", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/chaines")

      view
      |> form("#channel-form",
        channel: %{name: "JDG", url: "https://www.youtube.com/@joueurdugrenier", max_videos: 5}
      )
      |> render_submit()

      [channel] = Catalog.list_channels()
      refute channel.enabled

      view |> element("#channel-#{channel.id} button[phx-click=sync]") |> render_click()
      assert_enqueued(worker: Quotor.Workers.SyncChannels, args: %{channel_id: channel.id})
    end
  end
end
