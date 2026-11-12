defmodule Quotor.AuthorsTest do
  use Quotor.DataCase, async: true

  import Quotor.CatalogFixtures

  alias Quotor.{Catalog, Search}

  doctest Quotor.Catalog.Author

  setup do
    {:ok, channel} = Catalog.create_author(%{name: "Chaîne Démo", kind: "channel"})
    {:ok, person} = Catalog.create_author(%{name: "Jean Parleur", kind: "person"})

    source = source_fixture(%{author_id: channel.id, uploader: "Chaîne Démo"})
    [a, b] = quotes_fixture(source, ["Première phrase.", "Deuxième phrase."])
    {:ok, b} = Catalog.update_quote(b, %{author_id: person.id})

    %{channel: channel, person: person, a: a, b: b}
  end

  test "slug unique dérivé du nom" do
    assert {:error, cs} = Catalog.create_author(%{name: "chaine démo"})
    assert %{slug: ["un auteur porte déjà ce nom"]} = errors_on(cs)
  end

  test "find_or_create_author/1 est idempotent", %{channel: channel} do
    assert {:ok, found} = Catalog.find_or_create_author(%{name: "CHAINE DEMO", kind: "channel"})
    assert found.id == channel.id

    assert {:ok, new} = Catalog.find_or_create_author(%{name: "Nouvelle chaîne", kind: "channel"})
    assert new.slug == "nouvelle-chaine"
  end

  test "l'auteur d'une quote prime sur celui de la vidéo", %{a: a, b: b, channel: c, person: p} do
    [qa] = Search.search("première")
    [qb] = Search.search("deuxième")
    assert qa.id == a.id and Catalog.author_of(qa).id == c.id
    assert qb.id == b.id and Catalog.author_of(qb).id == p.id
  end

  test "quotes d'un auteur et liste publique", %{a: a, b: b, channel: c, person: p} do
    assert Enum.map(Catalog.author_quotes(c), & &1.id) == [a.id]
    assert Enum.map(Catalog.author_quotes(p), & &1.id) == [b.id]

    counts = Map.new(Catalog.list_public_authors(), fn {author, n} -> {author.id, n} end)
    assert counts == %{c.id => 1, p.id => 1}
  end

  test "recherche d'auteurs par nom", %{person: p} do
    assert [%{id: id}] = Catalog.search_authors("jean")
    assert id == p.id
    assert Catalog.search_authors("je") == []
  end

  test "supprimer un auteur conserve ses quotes", %{person: p, b: b} do
    {:ok, _} = Catalog.delete_author(p)
    assert Catalog.get_quote!(b.id).author_id == nil
  end
end
