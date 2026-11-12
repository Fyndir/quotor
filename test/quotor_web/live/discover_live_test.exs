defmodule QuotorWeb.DiscoverLiveTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.CatalogFixtures

  alias Quotor.Catalog

  setup do
    quotes = quotes_fixture(source_fixture(), ["Première réplique.", "Deuxième réplique."])
    %{quotes: quotes}
  end

  test "onglet accessible depuis l'en-tête, même anonyme", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "header a[href='/decouvrir']", "Découvrir")
  end

  test "au hasard par défaut, avec bouton Mélanger", %{conn: conn, quotes: [a, b]} do
    {:ok, view, html} = live(conn, ~p"/decouvrir")
    assert html =~ "Découvrir"
    assert has_element?(view, "#quotes-#{a.id}")
    assert has_element?(view, "#quotes-#{b.id}")

    view |> element("button[phx-click=shuffle]") |> render_click()
    assert has_element?(view, "#quotes-#{a.id}")
  end

  test "tri par nouveautés et par popularité", %{conn: conn, quotes: [a, b]} do
    Catalog.increment_views(a.id)

    {:ok, view, _html} = live(conn, ~p"/decouvrir?tri=populaires")
    refute has_element?(view, "button[phx-click=shuffle]")
    assert view |> element("#discover article:first-of-type") |> render() =~ "Première réplique"

    view |> element("a[role=tab]", "Nouveautés") |> render_click()
    assert_patch(view, ~p"/decouvrir?tri=recents")
    assert has_element?(view, "#quotes-#{b.id}")
  end

  test "un utilisateur connecté peut mettre en favori", %{conn: conn, quotes: [a, _]} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/decouvrir")

    view |> element("#quotes-#{a.id} button[phx-click=toggle_favorite]") |> render_click()
    assert [%{id: id}] = Catalog.list_favorites(scope)
    assert id == a.id
  end
end
