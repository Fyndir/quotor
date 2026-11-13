defmodule QuotorWeb.DiscoverLiveTest do
  use QuotorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Quotor.AccountsFixtures
  import Quotor.CatalogFixtures

  alias Quotor.{Catalog, Montages, Repo}
  alias Quotor.Montages.Montage

  defp montage_fixture(quote, attrs) do
    %Montage{
      key: "k#{System.unique_integer([:positive])}",
      query: "Phrase de test",
      status: "ready",
      file_path: "montages/test.mp4",
      segments: [%{"quote_id" => quote.id, "source_id" => quote.source_id, "text" => quote.text}]
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  setup do
    [a, b] = quotes_fixture(source_fixture(), ["Première réplique.", "Deuxième réplique."])
    user = user_fixture()

    old =
      montage_fixture(a, %{
        query: "Le plus vu",
        user_id: user.id,
        views_count: 10,
        inserted_at: ~U[2026-01-01 00:00:00Z]
      })

    new = montage_fixture(b, %{query: "Le plus récent", user_id: user.id})
    %{quotes: [a, b], user: user, old: old, new: new}
  end

  test "onglet accessible depuis l'en-tête, même anonyme", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "header a[href='/decouvrir']", "Découvrir")
  end

  test "montre les montages des utilisateurs, pas les extraits bruts", %{
    conn: conn,
    old: old,
    new: new,
    quotes: [a, _]
  } do
    anonymous = montage_fixture(a, %{query: "Anonyme", user_id: nil})

    {:ok, view, _html} = live(conn, ~p"/decouvrir")

    assert has_element?(view, "#montages-#{old.id}")
    assert has_element?(view, "#montages-#{new.id}")
    refute has_element?(view, "#montages-#{anonymous.id}")
    refute has_element?(view, "[id^=quotes-]")
    assert has_element?(view, "#shuffle")
  end

  test "tri par nouveautés et par popularité", %{conn: conn, old: old, new: new} do
    {:ok, _view, html} = live(conn, ~p"/decouvrir?tri=recents")
    assert position(html, new.query) < position(html, old.query)

    {:ok, _view, html} = live(conn, ~p"/decouvrir?tri=populaires")
    assert position(html, old.query) < position(html, new.query)
  end

  test "un montage dont un extrait est masqué disparaît", %{conn: conn, old: old, quotes: [a, _]} do
    {:ok, _} = Catalog.update_quote(a, %{enabled: false})

    {:ok, view, _html} = live(conn, ~p"/decouvrir")
    refute has_element?(view, "#montages-#{old.id}")
  end

  test "l'auteur peut retirer son montage de Découvrir", %{conn: conn, user: user, new: new} do
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/m/#{new.key}")

    view |> element("#toggle-listed") |> render_click()
    refute Repo.get!(Montage, new.id).listed

    {:ok, discover, _html} = live(conn, ~p"/decouvrir")
    refute has_element?(discover, "#montages-#{new.id}")
  end

  test "seul l'auteur voit le réglage, et chaque visite compte une vue", %{conn: conn, new: new} do
    {:ok, view, _html} = live(conn, ~p"/m/#{new.key}")
    refute has_element?(view, "#toggle-listed")
    assert Repo.get!(Montage, new.id).views_count == 1

    other = Quotor.Accounts.Scope.for_user(user_fixture())
    assert {:error, :forbidden} = Montages.set_listed(new, other, false)
  end

  defp position(html, text) do
    {pos, _} = :binary.match(html, text)
    pos
  end
end
