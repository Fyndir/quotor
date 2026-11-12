defmodule Quotor.Ingest.SubtitlesTest do
  use ExUnit.Case, async: true

  alias Quotor.Ingest.{Segmenter, Subtitles}

  @fixtures Path.expand("../../support/fixtures", __DIR__)

  describe "sous-titres automatiques YouTube" do
    setup do
      {:ok, parsed} = Subtitles.parse_file(Path.join(@fixtures, "auto.fr.vtt"))
      %{parsed: parsed}
    end

    test "sont détectés et horodatés mot à mot", %{parsed: parsed} do
      assert parsed.kind == :auto
      words = Enum.flat_map(parsed.cues, & &1.words)

      assert Enum.map(words, & &1.text) ==
               ~w(bonjour à tous c'est le joueur du grenier aujourd'hui on teste un jeu pourri)

      [bonjour, a | _] = words
      assert bonjour.start_ms == 0
      assert bonjour.end_ms == 400
      assert a.start_ms == 400

      grenier = Enum.find(words, &(&1.text == "grenier"))
      assert grenier.start_ms == 2100
    end

    test "les lignes répétées (roll-up) sont ignorées", %{parsed: parsed} do
      texts = Enum.map(parsed.cues, & &1.text)
      assert length(texts) == 3
      refute Enum.any?(texts, &(&1 == "bonjour à tous c'est le joueur du grenier"))
    end

    test "le segmenteur coupe sur les pauses", %{parsed: parsed} do
      [first, second] = Segmenter.segment(parsed)

      assert first.text == "Bonjour à tous c'est le joueur du grenier"
      assert first.norm == "bonjour a tous c est le joueur du grenier"
      assert second.norm == "aujourd hui on teste un jeu pourri"

      # les tokens correspondent exactement au texte normalisé
      assert Enum.map_join(first.words, " ", & &1.word) == first.norm
      assert Enum.map(first.words, & &1.position) == Enum.to_list(0..8)

      # "c'est" (0,9 s → 1,2 s) est partagé entre "c" et "est"
      c = Enum.find(first.words, &(&1.word == "c"))
      est = Enum.find(first.words, &(&1.word == "est"))
      assert c.start_ms == 900
      assert est.start_ms == 1050
      assert est.end_ms == 1200
    end
  end

  describe "sous-titres manuels (SRT)" do
    setup do
      {:ok, parsed} = Subtitles.parse_file(Path.join(@fixtures, "manual.fr.srt"))
      %{parsed: parsed}
    end

    test "nettoie balises, tirets et annotations", %{parsed: parsed} do
      assert parsed.kind == :manual

      assert Enum.map(parsed.cues, & &1.text) == [
               "Je suis pas venu ici",
               "pour souffrir, OK ?",
               "C'est l'été, les amis !"
             ]

      [first | _] = parsed.cues
      assert first.start_ms == 500
      assert first.end_ms == 2000
      assert hd(first.words).start_ms == 500
      assert List.last(first.words).end_ms == 2000
    end

    test "fusionne une phrase coupée sur deux cues", %{parsed: parsed} do
      [first, second] = Segmenter.segment(parsed)
      assert first.text == "Je suis pas venu ici pour souffrir, OK ?"
      assert first.start_ms == 500
      assert first.end_ms == 3500
      assert second.norm == "c est l ete les amis"
    end
  end

  test "gère les cues VTT avec identifiant et heures facultatives" do
    vtt = """
    WEBVTT

    intro
    00:01.000 --> 00:02.500
    Salut &amp; bienvenue

    2
    01:00:00.000 --> 01:00:01.000
    Fin
    """

    %{kind: :manual, cues: [a, b]} = Subtitles.parse(vtt)
    assert a.text == "Salut & bienvenue"
    assert a.start_ms == 1000
    assert b.start_ms == 3_600_000
  end
end
