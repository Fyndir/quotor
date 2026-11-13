defmodule QuotorWeb.IdeasLiveTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.CatalogFixtures

  setup do
    quotes_fixture(source_fixture(), ["Bonjour à tous, c'est le joueur du grenier."])
    quotes_fixture(source_fixture(), ["Le pire, c'est que j'ai payé pour ça."])
    :ok
  end

  test "mode avancé, champ vide : idées proposées, un clic lance le montage", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?mode=advanced")

    assert has_element?(view, "#ideas #idea-0")
    view |> element("#more-ideas") |> render_click()
    assert has_element?(view, "#ideas #idea-0")

    [href] =
      view
      |> element("#idea-0")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("href")

    assert href =~ "mode=advanced"
    assert href =~ "q="
  end

  test "pas d'idées en mode standard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#ideas")
  end
end
