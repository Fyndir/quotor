defmodule Quotor.SearchTest do
  use Quotor.DataCase, async: true

  import Quotor.CatalogFixtures

  alias Quotor.{Catalog, Search}

  setup do
    source = source_fixture(%{title: "Bref."})

    quotes =
      quotes_fixture(source, [
        "Je suis pas venu ici pour souffrir.",
        "Bref, j'ai fait une soirée.",
        "C'est l'été les amis !",
        "Ici on mange des crêpes."
      ])

    %{source: source, quotes: quotes}
  end

  describe "search/2 (standard)" do
    test "trouve une expression, insensible aux accents et à la casse", %{quotes: [_, bref | _]} do
      assert [%{id: id}] = Search.search("SOIREE")
      assert id == bref.id
    end

    test "classe l'expression exacte en premier", %{quotes: [souffrir | _]} do
      [first | _] = Search.search("venu ici")
      assert first.id == souffrir.id
    end

    test "tolère une faute de frappe", %{quotes: [souffrir | _]} do
      assert Enum.any?(Search.search("pas venu ici pour soufrir"), &(&1.id == souffrir.id))
    end

    test "ignore les quotes masquées et les sources masquées", %{
      source: source,
      quotes: [_, bref | _]
    } do
      {:ok, _} = Catalog.update_quote(bref, %{enabled: false})
      assert Search.search("soirée") == []

      {:ok, _} = Catalog.update_quote(bref, %{enabled: true})
      {:ok, _} = Catalog.update_source(source, %{enabled: false})
      assert Search.search("soirée") == []
    end

    test "requête vide" do
      assert Search.search("  !! ") == []
    end
  end

  describe "plan/2 (avancé)" do
    test "assemble les plus longs morceaux trouvés", %{quotes: [souffrir, bref, ete, _]} do
      plan = Search.plan("je suis pas venu ici pour faire une soirée les amis")

      assert Enum.map(plan.segments, & &1.text) == [
               "je suis pas venu ici pour",
               "une soiree",
               "les amis"
             ]

      assert Enum.map(plan.segments, & &1.quote_id) == [souffrir.id, bref.id, ete.id]
      assert plan.missing == ["faire"]
    end

    test "les bornes d'un segment sont dans le clip", %{quotes: [souffrir | _]} do
      %{segments: [seg]} = Search.plan("venu ici")
      assert seg.quote_id == souffrir.id
      assert seg.from_ms >= souffrir.clip_start_ms
      assert seg.to_ms <= souffrir.clip_end_ms
      assert seg.to_ms > seg.from_ms
    end

    test "aucun mot trouvé" do
      assert %{segments: [], missing: ["zorglub"]} = Search.plan("zorglub")
    end
  end
end
