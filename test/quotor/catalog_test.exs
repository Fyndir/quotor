defmodule Quotor.CatalogTest do
  use Quotor.DataCase, async: true

  import Quotor.AccountsFixtures
  import Quotor.CatalogFixtures

  alias Quotor.Catalog
  alias Quotor.Catalog.Source

  describe "sources YouTube" do
    test "youtube_id/1 reconnaît les formats d'URL" do
      for url <- [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=10",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "dQw4w9WgXcQ"
          ] do
        assert Source.youtube_id(url) == "dQw4w9WgXcQ", url
      end

      assert Source.youtube_id("https://example.com") == nil
    end

    test "une vidéo ne peut être ajoutée deux fois" do
      assert {:ok, source} = Catalog.create_youtube_source(%{url: "https://youtu.be/dQw4w9WgXcQ"})
      assert source.url == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

      assert {:error, cs} =
               Catalog.create_youtube_source(%{
                 url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
               })

      assert %{youtube_id: ["cette vidéo est déjà dans le catalogue"]} = errors_on(cs)
    end

    test "URL invalide" do
      assert {:error, cs} = Catalog.create_youtube_source(%{url: "https://vimeo.com/123"})
      assert %{url: ["URL YouTube invalide"]} = errors_on(cs)
    end

    test "lien vers l'original à l'instant de la quote" do
      source = source_fixture(%{youtube_id: "dQw4w9WgXcQ"})

      assert Source.original_url(source, 65_432) ==
               "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=65s"
    end
  end

  describe "replace_quotes/3" do
    test "crée quotes et mots, avec marges de découpe" do
      source = source_fixture()
      [quote] = quotes_fixture(source, ["Salut les amis."])

      quote = Catalog.get_quote!(quote.id)
      assert quote.norm == "salut les amis"
      assert Enum.map(quote.words, & &1.word) == ~w(salut les amis)
      assert quote.clip_start_ms == 0
      assert quote.clip_end_ms == quote.end_ms + 250
    end

    test "remplace les quotes existantes" do
      source = source_fixture()
      quotes_fixture(source, ["Un.", "Deux."])
      quotes_fixture(source, ["Trois."])
      assert [%{norm: "trois"}] = Catalog.list_quotes_for_source(source.id)
    end
  end

  describe "favoris" do
    test "ajout puis retrait" do
      scope = user_scope_fixture()
      [quote] = quotes_fixture(source_fixture(), ["Coucou."])

      assert :added = Catalog.toggle_favorite(scope, quote.id)
      assert MapSet.member?(Catalog.favorite_ids(scope, [quote.id]), quote.id)
      assert [%{id: id}] = Catalog.list_favorites(scope)
      assert id == quote.id

      assert :removed = Catalog.toggle_favorite(scope, quote.id)
      assert Catalog.list_favorites(scope) == []
    end

    test "un anonyme n'a pas de favoris" do
      assert Catalog.favorite_ids(nil, [1, 2]) == MapSet.new()
    end
  end

  describe "signalements" do
    test "une demande de retrait pour droit d'auteur exige nom et email" do
      assert {:error, cs} =
               Catalog.create_report(%{
                 reason: "copyright",
                 message: "C'est ma vidéo, merci de la retirer."
               })

      assert %{contact_email: [_], contact_name: [_]} = errors_on(cs)

      assert {:ok, report} =
               Catalog.create_report(%{
                 reason: "copyright",
                 message: "C'est ma vidéo, merci de la retirer.",
                 contact_name: "Jean Auteur",
                 contact_email: "jean@example.com"
               })

      assert report.status == "open"
      assert Catalog.count_open_reports() == 1
    end

    test "un autre motif n'exige pas de contact" do
      assert {:ok, _} =
               Catalog.create_report(%{reason: "offensive", message: "Ce montage est insultant."})
    end
  end
end
