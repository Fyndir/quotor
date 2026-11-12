defmodule QuotorWeb.AuthorsLiveTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.CatalogFixtures

  alias Quotor.Catalog

  setup do
    {:ok, channel} =
      Catalog.create_author(%{
        name: "Chaîne Démo",
        kind: "channel",
        url: "https://www.youtube.com/@demo"
      })

    {:ok, person} = Catalog.create_author(%{name: "Jean Parleur", kind: "person"})

    source =
      source_fixture(%{
        author_id: channel.id,
        uploader: "Chaîne Démo",
        channel_url: "https://www.youtube.com/@demo",
        title: "Ma vidéo"
      })

    [a, b] = quotes_fixture(source, ["Bonjour la chaîne.", "Ici Jean qui parle."])
    {:ok, b} = Catalog.update_quote(b, %{author_id: person.id})
    %{channel: channel, person: person, a: a, b: b}
  end

  test "la carte affiche l'auteur et la source", %{conn: conn, b: b} do
    {:ok, view, _html} = live(conn, ~p"/?q=jean")
    card = view |> element("#quotes-#{b.id}") |> render()
    assert card =~ "Jean Parleur"
    assert card =~ "/auteurs/jean-parleur"
    assert card =~ "Chaîne Démo · Ma vidéo"
  end

  test "page d'un extrait : qui parle, chaîne, source", %{conn: conn, b: b} do
    {:ok, view, html} = live(conn, ~p"/q/#{b.id}")
    assert html =~ "Qui parle"
    assert has_element?(view, "#quote-author", "Jean Parleur")
    assert html =~ ~s(href="https://www.youtube.com/@demo")
    assert html =~ "Ma vidéo"
    # l'auteur figure dans le titre de la carte Discord
    assert render(view) =~ "Ici Jean qui parle"
  end

  test "liste et page d'un auteur", %{conn: conn, a: a, b: b} do
    {:ok, view, _html} = live(conn, ~p"/auteurs")
    assert has_element?(view, "#authors a[href='/auteurs/chaine-demo']", "Chaîne Démo")
    assert has_element?(view, "#authors", "Jean Parleur")

    {:ok, view, html} = live(conn, ~p"/auteurs/chaine-demo")
    assert html =~ "Voir la chaîne"
    assert has_element?(view, "#quotes-#{a.id}")
    refute has_element?(view, "#quotes-#{b.id}")
  end

  test "auteur inconnu : 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/auteurs/personne") end
  end

  test "la recherche propose les auteurs correspondants", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?q=parleur")
    assert has_element?(view, "#authors-found a[href='/auteurs/jean-parleur']")
  end

  describe "admin" do
    setup :register_and_log_in_admin

    test "créer un auteur", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/auteurs")

      view
      |> form("#author-form", author: %{name: "Nouvelle Personne", kind: "person"})
      |> render_submit()

      assert Catalog.get_author_by_slug("nouvelle-personne")
    end

    test "attribuer un auteur à une vidéo puis à une quote", %{conn: conn, person: p, a: a} do
      {:ok, view, _html} = live(conn, ~p"/admin/sources")

      view
      |> form("#source-author-#{a.source_id}", %{author_id: p.id})
      |> render_change()

      assert Catalog.get_source!(a.source_id).author_id == p.id

      {:ok, view, _html} = live(conn, ~p"/admin/quotes")
      view |> form("#quote-author-#{a.id}", %{author_id: ""}) |> render_change()
      assert Catalog.get_quote!(a.id).author_id == nil
    end
  end
end
