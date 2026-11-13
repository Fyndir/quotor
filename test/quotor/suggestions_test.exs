defmodule Quotor.SuggestionsTest do
  use Quotor.DataCase, async: true

  import Quotor.CatalogFixtures

  alias Quotor.{Catalog, Search, Suggestions}

  setup do
    quotes_fixture(source_fixture(), [
      "Bonjour à tous, c'est le joueur du grenier.",
      "Aujourd'hui on teste un jeu complètement nul."
    ])

    quotes_fixture(source_fixture(), [
      "Le pire, c'est que j'ai payé pour ça.",
      "Franchement, ce jeu est une vraie catastrophe."
    ])

    :ok
  end

  test "propose des greffes de deux répliques sur un mot commun" do
    ideas = Suggestions.random(20)

    assert ideas != []
    # « Bonjour à tous, c'est » + « que j'ai payé pour ça. »
    assert "Bonjour à tous, c'est que j'ai payé pour ça." in ideas
  end

  test "chaque idée est entièrement montable avec les extraits publiés" do
    for idea <- Suggestions.random(20) do
      plan = Search.plan(idea)
      assert plan.missing == [], "« #{idea} » : mots introuvables #{inspect(plan.missing)}"
      assert plan.segments != []
    end
  end

  test "jamais une réplique existante telle quelle" do
    texts = Enum.map(Catalog.list_admin_quotes(), &Quotor.Text.normalize(&1.text))

    for idea <- Suggestions.random(20) do
      refute Quotor.Text.normalize(idea) in texts
    end
  end

  test "n'utilise pas les extraits masqués ni ceux à vérifier" do
    for q <- Catalog.list_admin_quotes(),
        do: {:ok, _} = Catalog.update_quote(q, %{enabled: false})

    assert Suggestions.random() == []
  end
end
