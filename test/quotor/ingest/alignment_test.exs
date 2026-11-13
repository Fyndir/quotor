defmodule Quotor.Ingest.AlignmentTest do
  use ExUnit.Case, async: true

  alias Quotor.Ingest.{Alignment, Segmenter, Subtitles}

  # sous-titres manuels : les mots reçoivent des temps interpolés, imprécis
  @srt """
  1
  00:00:01,000 --> 00:00:03,000
  Franchement, je n'en peux plus.

  2
  00:00:10,000 --> 00:00:12,000
  Le pire, c'est que j'ai payé.
  """

  defp segments, do: @srt |> Subtitles.parse() |> Segmenter.segment()

  defp heard(list), do: for({t, s, e} <- list, do: %{text: t, start_ms: s, end_ms: e, prob: 0.8})

  test "parole conforme : score 1 et temps recalés mot à mot" do
    words =
      heard([
        {"Franchement,", 1400, 1900},
        {"je", 1900, 2000},
        {"n'en", 2000, 2200},
        {"peux", 2200, 2400},
        {"plus.", 2400, 2700},
        {"Le", 10_300, 10_400},
        {"pire,", 10_400, 10_700},
        {"c'est", 10_800, 11_000},
        {"que", 11_000, 11_100},
        {"j'ai", 11_100, 11_300},
        {"payé.", 11_300, 11_800}
      ])

    [a, b] = Alignment.align(segments(), words)

    assert a.asr_score == 1.0
    assert {a.start_ms, a.end_ms} == {1400, 2700}
    assert hd(a.words) == %{word: "franchement", position: 0, start_ms: 1400, end_ms: 1900}

    assert b.asr_score == 1.0
    assert {b.start_ms, b.end_ms} == {10_300, 11_800}
  end

  test "mots presque identiques acceptés, mots manquants décalés comme leurs voisins" do
    words =
      heard([
        {"Franchemen", 1400, 1900},
        {"je", 1900, 2000},
        {"plus.", 2400, 2700}
      ])

    [a, _b] = Alignment.align(segments(), words)

    # franchement ≈ franchemen, je, plus : 3 mots sur 6 (n, en, peux absents)
    assert a.asr_score == 0.5
    assert a.start_ms == 1400
    assert a.end_ms == 2700
    assert Enum.map(a.words, & &1.start_ms) == Enum.sort(Enum.map(a.words, & &1.start_ms))
  end

  test "parole différente : score faible, temps des sous-titres conservés" do
    original = segments()

    words =
      heard([
        {"Rien", 1200, 1500},
        {"à", 1500, 1600},
        {"voir", 1600, 2000},
        {"ici.", 2000, 2300}
      ])

    [a, b] = Alignment.align(original, words)

    assert a.asr_score < 0.4
    assert {a.start_ms, a.end_ms} == {hd(original).start_ms, hd(original).end_ms}
    # aucune parole entendue autour de la seconde quote
    assert b.asr_score == 0.0
  end

  test "la parole d'une autre quote, hors fenêtre, n'est pas prise en compte" do
    words = heard([{"Le", 20_000, 20_100}, {"pire,", 20_100, 20_400}])
    [_a, b] = Alignment.align(segments(), words)
    assert b.asr_score == 0.0
  end

  test "quotes construites depuis la seule transcription" do
    words =
      heard([
        {"Bonjour", 0, 400},
        {"à", 400, 500},
        {"tous.", 500, 900},
        {"On", 3000, 3200},
        {"commence.", 3200, 3800}
      ])

    assert [
             %{text: "Bonjour à tous.", start_ms: 0, asr_score: 0.8},
             %{text: "On commence.", start_ms: 3000, asr_score: 0.8}
           ] = Alignment.from_transcript(words)
  end

  test "mots similaires" do
    assert Alignment.similar?("complètement", "completement")
    assert Alignment.similar?("greniers", "grenier")
    refute Alignment.similar?("le", "la")
    refute Alignment.similar?("bonjour", "pour")
  end
end
