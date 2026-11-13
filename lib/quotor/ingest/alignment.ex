defmodule Quotor.Ingest.Alignment do
  @moduledoc """
  Rapproche les quotes issues des sous-titres de la transcription vocale
  (`Quotor.Ingest.Transcriber`).

  Pour chaque quote, les mots entendus autour de sa position (± 2,5 s) sont
  alignés sur ses mots (alignement de séquences : programmation dynamique,
  mots identiques ou presque). On en tire :

    * `asr_score` : part des mots de la quote réellement entendus (0..1) ;
    * si l'accord est suffisant, des **horodatages recalés** sur la parole :
      chaque mot reconnu prend les temps mesurés par la transcription, les
      autres sont décalés comme leur plus proche voisin reconnu. Les bornes
      de la quote, donc du clip, suivent.

  Sans sous-titres, `from_transcript/1` construit directement les quotes à
  partir de la transcription ; leur score est alors la confiance moyenne du
  moteur sur leurs mots.
  """

  alias Quotor.Ingest.Segmenter
  alias Quotor.Text

  @window_ms 2_500
  @retime_min_score 0.5
  @min_duration 350
  @max_word_ms 1_200
  @long_word_ms 700

  @match 2
  @mismatch -1
  @gap -1

  @doc "Ajoute `asr_score` (et recale les temps si possible) à chaque segment."
  def align(segments, asr_words) do
    tokens = asr_tokens(asr_words)

    segments
    |> Enum.map(&align_segment(&1, tokens))
    |> no_overlap()
  end

  # Une quote recalée ne commence jamais avant la fin de la précédente (sinon
  # son clip contiendrait la fin de l'autre phrase).
  defp no_overlap(segments) do
    {segments, _} =
      Enum.map_reduce(segments, 0, fn seg, prev_end ->
        seg =
          if seg.start_ms < prev_end and seg.end_ms - prev_end >= @min_duration do
            words = Enum.map(seg.words, &%{&1 | start_ms: max(&1.start_ms, prev_end)})
            %{seg | start_ms: prev_end, words: words}
          else
            seg
          end

        {seg, max(prev_end, seg.end_ms)}
      end)

    segments
  end

  @doc """
  Aligne des tokens (`["bonjour", "a", "tous"]`) sur des mots entendus.
  Renvoie `{paires, tokens_entendus}` : les paires `{i_token, i_entendu}` des
  mots concordants et les mots entendus, normalisés et horodatés.
  """
  def match(tokens, heard_words) do
    heard = asr_tokens(heard_words)
    q = Enum.map(tokens, &%{word: &1})
    pairs = if q == [] or heard == [], do: [], else: dp_align(q, heard)
    {pairs, heard}
  end

  @doc "Quotes construites à partir de la seule transcription."
  def from_transcript(asr_words) do
    %{kind: :auto, cues: [%{words: asr_words}]}
    |> Segmenter.segment()
    |> Enum.map(fn seg ->
      probs =
        for w <- asr_words, w.start_ms >= seg.start_ms, w.start_ms < seg.end_ms, do: w.prob

      score = if probs == [], do: 0.0, else: Enum.sum(probs) / length(probs)
      Map.put(seg, :asr_score, Float.round(score, 3))
    end)
  end

  # Mots entendus → tokens normalisés (comme ceux des quotes), en partageant
  # l'intervalle d'un mot qui donne plusieurs tokens (« c'est » → c, est).
  defp asr_tokens(words) do
    Enum.flat_map(words, fn %{text: text, start_ms: s, end_ms: e} ->
      # un mot anormalement long a « avalé » le silence qui le précède : son
      # début mesuré n'est pas fiable, sa fin l'est
      s = if e - s > @max_word_ms, do: e - @long_word_ms, else: s
      tokens = Text.tokens(text)
      n = length(tokens)
      step = if n > 0, do: div(max(e - s, 0), n), else: 0

      tokens
      |> Enum.with_index()
      |> Enum.map(fn {tok, i} ->
        start = s + i * step
        %{word: tok, start_ms: start, end_ms: if(i == n - 1, do: e, else: start + step)}
      end)
    end)
  end

  defp align_segment(%{words: []} = seg, _tokens), do: Map.put(seg, :asr_score, 0.0)

  defp align_segment(seg, tokens) do
    window =
      Enum.filter(tokens, fn t ->
        t.start_ms >= seg.start_ms - @window_ms and t.start_ms <= seg.end_ms + @window_ms
      end)

    pairs = if window == [], do: [], else: dp_align(seg.words, window)
    score = Float.round(length(pairs) / length(seg.words), 3)
    seg = Map.put(seg, :asr_score, score)

    if score >= @retime_min_score and length(pairs) >= min(2, length(seg.words)) do
      retime(seg, pairs, window)
    else
      seg
    end
  end

  @doc false
  # Alignement « semi-global » : tous les mots de la quote sont alignés, les
  # mots entendus avant et après sont gratuits. Renvoie les paires
  # `{indice quote, indice transcription}` des mots concordants.
  def dp_align(q_words, w_words) do
    q = q_words |> Enum.map(& &1.word) |> List.to_tuple()
    w = w_words |> Enum.map(& &1.word) |> List.to_tuple()
    n = tuple_size(q)
    m = tuple_size(w)

    init = for(j <- 0..m, into: %{}, do: {{0, j}, 0})

    dp =
      Enum.reduce(1..n, init, fn i, dp ->
        dp = Map.put(dp, {i, 0}, i * @gap)

        Enum.reduce(1..m, dp, fn j, dp ->
          diag = dp[{i - 1, j - 1}] + pair_score(elem(q, i - 1), elem(w, j - 1))
          up = dp[{i - 1, j}] + @gap
          left = dp[{i, j - 1}] + @gap
          Map.put(dp, {i, j}, max(diag, max(up, left)))
        end)
      end)

    best_j = Enum.max_by(0..m, &dp[{n, &1}])
    traceback(dp, q, w, n, best_j, [])
  end

  defp traceback(_dp, _q, _w, 0, _j, acc), do: acc
  defp traceback(_dp, _q, _w, _i, 0, acc), do: acc

  defp traceback(dp, q, w, i, j, acc) do
    a = elem(q, i - 1)
    b = elem(w, j - 1)

    cond do
      dp[{i, j}] == dp[{i - 1, j - 1}] + pair_score(a, b) ->
        acc = if similar?(a, b), do: [{i - 1, j - 1} | acc], else: acc
        traceback(dp, q, w, i - 1, j - 1, acc)

      dp[{i, j}] == dp[{i - 1, j}] + @gap ->
        traceback(dp, q, w, i - 1, j, acc)

      true ->
        traceback(dp, q, w, i, j - 1, acc)
    end
  end

  defp pair_score(a, b), do: if(similar?(a, b), do: @match, else: @mismatch)

  @doc false
  # Identiques, ou presque pour les mots assez longs (accords, coquilles :
  # « complètement » / « completement », « greniers » / « grenier »).
  def similar?(a, a), do: true

  def similar?(a, b) do
    String.length(a) >= 4 and String.length(b) >= 4 and String.jaro_distance(a, b) >= 0.88
  end

  defp retime(seg, pairs, window) do
    window = List.to_tuple(window)
    matched = Map.new(pairs, fn {qi, wj} -> {qi, elem(window, wj)} end)
    matched_idx = Map.keys(matched)

    {words, _} =
      seg.words
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {word, i}, prev_start ->
        {start, stop} =
          case matched do
            %{^i => heard} ->
              {heard.start_ms, heard.end_ms}

            _ ->
              nearest = Enum.min_by(matched_idx, &abs(&1 - i))
              delta = matched[nearest].start_ms - Enum.at(seg.words, nearest).start_ms
              {word.start_ms + delta, word.end_ms + delta}
          end

        start = max(start, prev_start)
        stop = max(stop, start)
        {%{word | start_ms: start, end_ms: stop}, start}
      end)

    start_ms = hd(words).start_ms
    end_ms = List.last(words).end_ms
    original = seg.end_ms - seg.start_ms

    if end_ms - start_ms >= @min_duration and end_ms - start_ms <= original * 2 + 2_000 do
      %{seg | words: words, start_ms: max(start_ms, 0), end_ms: end_ms}
    else
      seg
    end
  end
end
