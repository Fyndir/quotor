defmodule Quotor.Search do
  @moduledoc """
  Recherche de quotes.

  * **Standard** (`search/2`) : plein texte PostgreSQL (`tsvector` en
    configuration `simple`, sur le texte normalisé sans accents), avec un repli
    sur la similarité trigramme (`pg_trgm`) pour tolérer les fautes de frappe.
    L'expression exacte est classée en premier.

  * **Avancée** (`plan/2`) : découpe la phrase demandée en morceaux, chacun
    trouvé dans une quote existante (au mot près, grâce aux mots horodatés).
    Algorithme glouton : à chaque position, on cherche l'expression la plus
    longue possible. Le plan est ensuite rendu en vidéo par `Quotor.Montages`.
  """

  import Ecto.Query

  alias Quotor.{Catalog, Repo, Text}
  alias Quotor.Catalog.QuoteWord

  @max_query_words 40
  @max_phrase_words 12

  @doc """
  Recherche standard. Options : `:limit` (24), `:offset` (0).
  """
  def search(query, opts \\ []) do
    norm = Text.normalize(query)

    if norm == "" do
      []
    else
      limit = Keyword.get(opts, :limit, 24)
      offset = Keyword.get(opts, :offset, 0)

      Catalog.visible_quotes()
      |> where(
        [quote: q],
        fragment("? @@ plainto_tsquery('simple', ?)", q.tsv, ^norm) or
          fragment("? <% ?", ^norm, q.norm)
      )
      |> order_by([quote: q],
        desc: fragment("? @@ phraseto_tsquery('simple', ?)", q.tsv, ^norm),
        desc: fragment("ts_rank_cd(?, plainto_tsquery('simple', ?))", q.tsv, ^norm),
        desc: fragment("word_similarity(?, ?)", ^norm, q.norm),
        asc: fragment("length(?)", q.norm),
        asc: q.id
      )
      |> limit(^limit)
      |> offset(^offset)
      |> Catalog.with_display()
      |> Repo.all()
    end
  end

  @doc """
  Construit un plan de montage pour `query`.

  Renvoie `%{segments: [segment], missing: [mot]}` où chaque segment vaut :

      %{quote_id, source_id, clip_path, clip_start_ms, from_ms, to_ms, text, quote_text, source_title}

  Option `:shuffle` (booléen) : choisit des extraits au hasard parmi les
  candidats pour obtenir un autre montage de la même phrase.
  """
  def plan(query, opts \\ []) do
    tokens = query |> Text.tokens() |> Enum.take(@max_query_words)
    shuffle? = Keyword.get(opts, :shuffle, false)
    do_plan(tokens, shuffle?, [], [])
  end

  defp do_plan([], _shuffle?, segments, missing) do
    %{segments: Enum.reverse(segments), missing: Enum.reverse(missing)}
  end

  defp do_plan(tokens, shuffle?, segments, missing) do
    max_k = min(length(tokens), @max_phrase_words)

    found =
      Enum.find_value(max_k..1//-1, fn k ->
        phrase = Enum.take(tokens, k)

        case find_phrase(phrase, shuffle?) do
          nil -> nil
          segment -> {k, segment}
        end
      end)

    case found do
      {k, segment} ->
        do_plan(Enum.drop(tokens, k), shuffle?, [segment | segments], missing)

      nil ->
        [word | rest] = tokens
        do_plan(rest, shuffle?, segments, [word | missing])
    end
  end

  @candidates 6

  @doc """
  Autre segment pour la même expression (`tokens`), pris dans un extrait
  différent de ceux de `exclude` (identifiants de quotes). Sert au contrôle
  à l'écoute des montages (`Quotor.Montages.Check`). Renvoie `nil` s'il n'y en
  a pas.
  """
  def alternative(tokens, exclude) when is_list(exclude) do
    find_phrase(tokens, false, exclude)
  end

  defp find_phrase(phrase_tokens, shuffle?, exclude \\ []) do
    phrase = Enum.join(phrase_tokens, " ")

    order =
      if shuffle?,
        do: dynamic(fragment("random()")),
        else: dynamic([quote: q], fragment("length(?)", q.norm))

    Catalog.visible_quotes()
    |> where([quote: q], fragment("? @@ phraseto_tsquery('simple', ?)", q.tsv, ^phrase))
    |> where([quote: q], q.id not in ^exclude)
    |> order_by(^[asc: order])
    |> limit(@candidates)
    |> select([quote: q, source: s], %{
      quote_id: q.id,
      source_id: q.source_id,
      clip_path: q.clip_path,
      clip_start_ms: q.clip_start_ms,
      clip_end_ms: q.clip_end_ms,
      quote_text: q.text,
      source_title: s.title
    })
    |> Repo.all()
    |> Enum.find_value(&locate(&1, phrase_tokens, phrase))
  end

  # Retrouve la position exacte de l'expression dans les mots de la quote.
  defp locate(candidate, phrase_tokens, phrase) do
    words =
      Repo.all(
        from w in QuoteWord,
          where: w.quote_id == ^candidate.quote_id,
          order_by: w.position,
          select: %{word: w.word, start_ms: w.start_ms, end_ms: w.end_ms}
      )

    k = length(phrase_tokens)

    words
    |> Enum.chunk_every(k, 1, :discard)
    |> Enum.find(fn chunk -> Enum.map(chunk, & &1.word) == phrase_tokens end)
    |> case do
      nil ->
        nil

      chunk ->
        from_ms = max(hd(chunk).start_ms - 40, candidate.clip_start_ms)
        to_ms = min(List.last(chunk).end_ms + 150, candidate.clip_end_ms)

        candidate
        |> Map.merge(%{from_ms: from_ms, to_ms: max(to_ms, from_ms + 200), text: phrase})
    end
  end
end
