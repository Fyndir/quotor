defmodule Quotor.Suggestions do
  @moduledoc """
  Idées de phrases à monter, construites à partir des extraits déjà publiés
  (donc affinés et vérifiés à l'écoute quand la transcription est active).

  Principe : la **greffe**. Deux répliques réelles qui partagent un mot sont
  coupées sur ce mot ; on garde le début de la première et la fin de la
  seconde :

      « Bonjour à tous, c'est… »   +   « …c'est que j'ai payé pour ça. »
      → « Bonjour à tous, c'est que j'ai payé pour ça. »

  Chaque moitié existe telle quelle dans un extrait : la phrase est donc
  toujours montable (`Quotor.Montages.build/3`). Les greffes entre deux
  vidéos, et mieux encore entre deux auteurs différents, sont favorisées.
  """

  import Ecto.Query

  alias Quotor.{Catalog, Repo, Text}

  @sample 80
  @min_part 2
  @min_words 5
  @max_words 14

  @doc "Jusqu'à `count` idées de phrases, différentes à chaque appel."
  def random(count \\ 6) do
    quotes = sample()

    quotes
    |> candidates()
    |> Enum.shuffle()
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.uniq_by(& &1.norm)
    # pas deux idées tirées de la même réplique de départ
    |> Enum.uniq_by(& &1.first_id)
    |> Enum.take(count)
    |> Enum.map(& &1.text)
  end

  # Répliques publiées, tirées au hasard, avec leurs mots (affichage et forme
  # normalisée).
  defp sample do
    min_score = Quotor.Ingest.Transcriber.min_score()

    Catalog.visible_quotes()
    |> where([quote: q], is_nil(q.asr_score) or q.asr_score >= ^min_score)
    |> order_by(fragment("random()"))
    |> limit(@sample)
    |> select([quote: q, source: s], %{
      id: q.id,
      text: q.text,
      norm: q.norm,
      source_id: q.source_id,
      author_id: coalesce(q.author_id, s.author_id)
    })
    |> Repo.all()
    |> Enum.map(fn q ->
      words =
        q.text
        |> String.split(~r/\s+/u, trim: true)
        |> Enum.map(&{&1, Text.normalize(&1)})
        |> Enum.reject(fn {_, n} -> n == "" end)

      Map.put(q, :words, words)
    end)
    |> Enum.filter(&(length(&1.words) >= @min_part + 1))
  end

  @doc false
  def candidates(quotes) do
    for a <- quotes,
        b <- quotes,
        a.id != b.id,
        graft <- grafts(a, b),
        do: graft
  end

  # Toutes les greffes « début de a » + « fin de b » sur un mot commun.
  defp grafts(a, b) do
    b_index = b.words |> Enum.with_index() |> Enum.group_by(fn {{_, n}, _} -> n end)
    a_len = length(a.words)
    b_len = length(b.words)

    for {{_, pivot}, i} <- Enum.with_index(a.words),
        # au moins deux mots de chaque réplique, pivot compris côté a
        i + 1 >= @min_part,
        {_, j} <- Map.get(b_index, pivot, []),
        b_len - j - 1 >= @min_part,
        # la greffe doit changer quelque chose aux deux répliques
        i < a_len - 1 or j > 0,
        words = Enum.take(a.words, i + 1) ++ Enum.drop(b.words, j + 1),
        length(words) in @min_words..@max_words,
        text = render(words),
        norm = Enum.map_join(words, " ", &elem(&1, 1)),
        norm != a.norm and norm != b.norm,
        not String.contains?(a.norm, norm) and not String.contains?(b.norm, norm) do
      %{text: text, norm: norm, first_id: a.id, score: score(a, b, i, j, words)}
    end
  end

  # Plus drôle : deux vidéos ou deux auteurs différents, coupe au milieu des
  # répliques, phrase de longueur moyenne.
  defp score(a, b, i, j, words) do
    cross_source = if a.source_id != b.source_id, do: 2, else: 0
    cross_author = if a.author_id && b.author_id && a.author_id != b.author_id, do: 2, else: 0
    balance = min(i + 1, length(b.words) - j - 1)
    length_bonus = if length(words) in 7..11, do: 1, else: 0

    cross_source + cross_author + min(balance, 4) * 0.5 + length_bonus
  end

  # Texte affiché : majuscule au début, ponctuation de fin conservée.
  defp render(words) do
    text = Enum.map_join(words, " ", &elem(&1, 0))
    text = Text.capitalize_first(text)
    if Regex.match?(~r/[.!?…]$/u, text), do: text, else: text <> " !"
  end
end
