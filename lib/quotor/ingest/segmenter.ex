defmodule Quotor.Ingest.Segmenter do
  @moduledoc """
  Transforme des sous-titres analysés en « quotes » (phrases courtes).

  Chaque quote produite vaut :

      %{text: "Bonjour à tous", start_ms: 0, end_ms: 1200,
        words: [%{word: "bonjour", position: 0, start_ms: 0, end_ms: 480}, ...]}

  Les `words` sont des tokens **normalisés** (cf. `Quotor.Text`) : leur
  concaténation est exactement le champ `norm` de la quote, ce qui permet de
  retrouver la position d'une expression dans une quote pour les montages.
  """

  alias Quotor.Text

  @max_words 14
  @max_duration 6_500
  @pause_ms 1_100
  @soft_pause_ms 600
  @soft_min_words 7
  @min_duration 350
  @max_word_ms 1_200

  def segment(%{kind: :auto, cues: cues}) do
    cues
    |> Enum.flat_map(& &1.words)
    |> Enum.sort_by(& &1.start_ms)
    |> split_words([], [])
    |> Enum.map(&build_quote(&1, :auto))
    |> finalize()
  end

  def segment(%{kind: :manual, cues: cues}) do
    cues
    |> merge_cues()
    |> Enum.map(&build_quote(&1.words, :manual, &1.text))
    |> finalize()
  end

  ## Auto : découpage du flux de mots

  defp split_words([], [], acc), do: Enum.reverse(acc)
  defp split_words([], current, acc), do: Enum.reverse([Enum.reverse(current) | acc])

  defp split_words([word | rest], current, acc) do
    word = %{word | end_ms: min(word.end_ms, word.start_ms + @max_word_ms)}
    current = [word | current]
    next = List.first(rest)

    if cut_after?(current, next) do
      split_words(rest, [], [Enum.reverse(current) | acc])
    else
      split_words(rest, current, acc)
    end
  end

  defp cut_after?(_current, nil), do: true

  defp cut_after?([last | _] = current, next) do
    first = List.last(current)
    count = length(current)
    gap = next.start_ms - last.start_ms

    gap > @pause_ms or count >= @max_words or
      next.end_ms - first.start_ms > @max_duration or
      (count >= @soft_min_words and gap > @soft_pause_ms)
  end

  ## Manuel : fusion des cues qui coupent une phrase en deux

  defp merge_cues(cues) do
    cues
    |> Enum.reduce([], fn
      cue, [prev | acc] = all ->
        if mergeable?(prev, cue) do
          [
            %{
              prev
              | end_ms: cue.end_ms,
                text: prev.text <> " " <> cue.text,
                words: prev.words ++ cue.words
            }
            | acc
          ]
        else
          [cue | all]
        end

      cue, [] ->
        [cue]
    end)
    |> Enum.reverse()
  end

  defp mergeable?(prev, cue) do
    not Regex.match?(~r/[.!?…»"]\s*$/u, prev.text) and
      cue.start_ms - prev.end_ms < 300 and
      cue.end_ms - prev.start_ms <= @max_duration and
      length(prev.words) + length(cue.words) <= @max_words + 4
  end

  ## Construction

  defp build_quote(raw_words, kind, text \\ nil) do
    words =
      raw_words
      |> Enum.flat_map(&tokenize_word/1)
      |> Enum.with_index()
      |> Enum.map(fn {w, i} -> Map.put(w, :position, i) end)

    display =
      case kind do
        :auto -> raw_words |> Enum.map_join(" ", & &1.text) |> Text.capitalize_first()
        :manual -> text
      end

    %{
      text: display,
      norm: Enum.map_join(words, " ", & &1.word),
      start_ms: (List.first(raw_words) || %{start_ms: 0}).start_ms,
      end_ms: (List.last(raw_words) || %{end_ms: 0}).end_ms,
      words: words
    }
  end

  # Un mot brut peut donner plusieurs tokens ("c'est" -> "c", "est") : on
  # partage alors son intervalle de temps.
  defp tokenize_word(%{text: text, start_ms: s, end_ms: e}) do
    tokens = Text.tokens(text)
    n = length(tokens)

    if n == 0 do
      []
    else
      step = div(max(e - s, 0), n)

      tokens
      |> Enum.with_index()
      |> Enum.map(fn {tok, i} ->
        start = s + i * step
        stop = if i == n - 1, do: e, else: start + step
        %{word: tok, start_ms: start, end_ms: stop}
      end)
    end
  end

  defp finalize(quotes) do
    Enum.filter(quotes, fn q ->
      q.words != [] and q.end_ms - q.start_ms >= @min_duration
    end)
  end
end
