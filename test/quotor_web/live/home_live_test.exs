defmodule QuotorWeb.HomeLiveTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.CatalogFixtures

  setup do
    source = source_fixture(%{title: "Bref.", uploader: "Kyan Khojandi"})

    quotes =
      quotes_fixture(source, [
        "Bref, j'ai fait une soirée.",
        "Je suis pas venu ici pour souffrir."
      ])

    %{quotes: quotes}
  end

  test "page d'accueil anonyme : recherche et découverte", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Trouve"
    assert html =~ "Créer un compte"
    assert has_element?(view, "#search-form")
    # plus d'aperçus sur l'accueil : un lien vers l'onglet Découvrir à la place
    refute has_element?(view, "article")
    assert has_element?(view, "#discover-hint a[href='/decouvrir']")
    # pas de favoris pour un anonyme
    refute has_element?(view, "button[phx-click=toggle_favorite]")
  end

  test "recherche standard", %{conn: conn, quotes: [bref, _]} do
    {:ok, view, _html} = live(conn, ~p"/?q=soiree")
    assert has_element?(view, "#quotes-#{bref.id}")
    assert render(view) =~ "Kyan Khojandi"

    view |> form("#search-form", %{q: "zorglub"}) |> render_submit()
    assert_patch(view, ~p"/?q=zorglub")
    refute has_element?(view, "#results article")
  end

  test "un utilisateur connecté peut mettre en favori", %{conn: conn, quotes: [bref, _]} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/?q=soiree")

    view |> element("#quotes-#{bref.id} button[phx-click=toggle_favorite]") |> render_click()
    assert [%{id: id}] = Quotor.Catalog.list_favorites(scope)
    assert id == bref.id

    {:ok, _view, html} = live(conn, ~p"/favoris")
    assert html =~ "Bref, j&#39;ai fait une soirée."
  end

  test "page d'une quote : source et lien vers l'original", %{conn: conn, quotes: [bref, _]} do
    {:ok, _view, html} = live(conn, ~p"/q/#{bref.id}")
    assert html =~ "Bref."
    assert html =~ "Voir la vidéo originale"
    assert html =~ "youtube.com/watch?v="
    assert html =~ "Signaler"
  end

  test "balises Open Graph pour l'intégration Discord", %{conn: conn, quotes: [bref, _]} do
    html =
      conn
      |> put_req_header("user-agent", "Mozilla/5.0 (compatible; Discordbot/2.0)")
      |> get(~p"/q/#{bref.id}")
      |> html_response(200)

    base = QuotorWeb.Endpoint.url()
    assert html =~ ~s(<meta property="og:type" content="video.other")
    assert html =~ ~s(<meta property="og:video" content="#{base}/media/#{bref.clip_path}")
    assert html =~ ~s(<meta property="og:video:type" content="video/mp4")
    assert html =~ ~s(<meta property="og:image" content="#{base}/media/#{bref.thumb_path}")
    assert html =~ "og:title"
    assert html =~ "Kyan Khojandi"
  end

  test "quote inexistante : 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/q/999999") end
  end

  test "signalement d'un extrait par un ayant droit", %{conn: conn, quotes: [bref, _]} do
    {:ok, view, _html} = live(conn, ~p"/signaler?quote_id=#{bref.id}")

    assert view
           |> form("#report-form", report: %{reason: "copyright", message: "C'est mon œuvre."})
           |> render_submit() =~ "obligatoire pour une demande de retrait"

    view
    |> form("#report-form",
      report: %{
        reason: "copyright",
        message: "Je suis l'auteur de cette vidéo, merci de la retirer.",
        contact_name: "Auteur",
        contact_email: "auteur@example.com"
      }
    )
    |> render_submit()

    assert_redirect(view, ~p"/")
    assert [report] = Quotor.Catalog.list_reports("open")
    assert report.quote_id == bref.id
  end
end
