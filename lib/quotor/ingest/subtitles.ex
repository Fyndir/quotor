defmodule Quotor.Ingest.Subtitles do
  @moduledoc """
  Analyse de sous-titres WebVTT et SRT.

  Deux cas sont gérés :

    * **sous-titres manuels** : chaque cue contient une phrase ; les mots
      reçoivent un horodatage interpolé proportionnellement à leur longueur ;
    * **sous-titres automatiques YouTube** : les cues contiennent des balises
      `<00:00:01.234>` donnant le début de chaque mot. Les lignes répétées
      (effet « roll-up ») sont ignorées : seules les lignes horodatées mot à mot
      sont conservées.

  Le résultat est toujours `%{kind: :auto | :manual, cues: [cue]}` où chaque cue
  vaut `%{start_ms, end_ms, text, words: [%{text, start_ms, end_ms}]}`.
  """

  @timestamp ~r/(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})/
  @inline_ts ~r/<(\d{2}:\d{2}:\d{2}\.\d{3})>/

  @type word :: %{text: String.t(), start_ms: integer(), end_ms: integer()}
  @type cue :: %{start_ms: integer(), end_ms: integer(), text: String.t(), words: [word()]}

  @doc "Lit un fichier de sous-titres (VTT ou SRT, selon l'extension ou le contenu)."
  def parse_file(path) do
    with {:ok, content} <- File.read(path) do
      {:ok, parse(content)}
    end
  end

  @spec parse(String.t()) :: %{kind: :auto | :manual, cues: [cue()]}
  def parse(content) when is_binary(content) do
    blocks =
      content
      |> String.replace("﻿", "")
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.split("\n")
      |> split_cues([])

    if Enum.any?(blocks, fn {_s, _e, lines} -> Enum.any?(lines, &Regex.match?(@inline_ts, &1)) end) do
      %{kind: :auto, cues: auto_cues(blocks)}
    else
      %{kind: :manual, cues: manual_cues(blocks)}
    end
  end

  # Découpe ligne à ligne : une cue commence à une ligne « --> » ; son texte
  # s'arrête à la première ligne vide rencontrée *après* du texte. (YouTube
  # place une ligne ne contenant qu'un espace en tête de cue : elle ne doit pas
  # terminer la cue.) Les identifiants de cue (index SRT…) sont ainsi ignorés.
  defp split_cues([], acc), do: Enum.reverse(acc)

  defp split_cues([line | rest], acc) do
    if String.contains?(line, "-->") do
      {text, rest} = take_text(rest, [], false)

      case parse_timing(line) do
        {:ok, s, e} -> split_cues(rest, [{s, e, text} | acc])
        :error -> split_cues(rest, acc)
      end
    else
      split_cues(rest, acc)
    end
  end

  defp take_text([], acc, _seen?), do: {Enum.reverse(acc), []}

  defp take_text([line | rest] = lines, acc, seen?) do
    blank? = String.trim(line) == ""

    cond do
      String.contains?(line, "-->") -> {Enum.reverse(acc), lines}
      blank? and seen? -> {Enum.reverse(acc), rest}
      blank? -> take_text(rest, acc, seen?)
      true -> take_text(rest, [line | acc], true)
    end
  end

  defp parse_timing(line) do
    case String.split(line, "-->", parts: 2) do
      [left, right] ->
        with {:ok, s} <- parse_ts(left), {:ok, e} <- parse_ts(right) do
          {:ok, s, max(e, s)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @doc false
  def parse_ts(str) do
    case Regex.run(@timestamp, str) do
      [_, h, m, s, ms] ->
        h = if h == "", do: 0, else: String.to_integer(h)

        {:ok,
         ((h * 60 + String.to_integer(m)) * 60 + String.to_integer(s)) * 1000 +
           String.to_integer(ms)}

      _ ->
        :error
    end
  end

  ## Sous-titres automatiques (mot à mot)

  defp auto_cues(blocks) do
    blocks
    |> Enum.flat_map(fn {cue_start, cue_end, lines} ->
      lines
      |> Enum.filter(&Regex.match?(@inline_ts, &1))
      |> Enum.map(&timed_line_words(&1, cue_start, cue_end))
    end)
    |> Enum.reject(&(&1 == []))
    |> Enum.map(fn words ->
      %{
        start_ms: hd(words).start_ms,
        end_ms: List.last(words).end_ms,
        text: Enum.map_join(words, " ", & &1.text),
        words: words
      }
    end)
    |> fix_overlaps()
  end

  # "bonjour<00:00:00.480><c> à</c><00:00:00.720><c> tous</c>"
  defp timed_line_words(line, cue_start, cue_end) do
    line = String.replace(line, ~r/<\/?c[^>]*>/, "")
    parts = Regex.split(@inline_ts, line, include_captures: true)

    {pieces, _} =
      Enum.reduce(parts, {[], cue_start}, fn part, {acc, current_start} ->
        case Regex.run(@inline_ts, part) do
          [_, ts] ->
            {:ok, ms} = parse_ts(ts)
            {acc, ms}

          nil ->
            {[{current_start, clean_text(part)} | acc], current_start}
        end
      end)

    pieces = pieces |> Enum.reverse() |> Enum.reject(fn {_, t} -> t == "" end)

    ends = (pieces |> Enum.drop(1) |> Enum.map(&elem(&1, 0))) ++ [cue_end]

    pieces
    |> Enum.zip(ends)
    |> Enum.flat_map(fn {{start, text}, stop} -> spread_words(text, start, max(stop, start)) end)
  end

  ## Sous-titres manuels

  defp manual_cues(blocks) do
    blocks
    |> Enum.map(fn {s, e, lines} ->
      {s, e, lines |> Enum.map(&clean_text/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")}
    end)
    |> Enum.reject(fn {_s, _e, text} -> text == "" end)
    |> Enum.dedup_by(fn {_s, _e, text} -> text end)
    |> Enum.map(fn {s, e, text} ->
      %{start_ms: s, end_ms: e, text: text, words: spread_words(text, s, e)}
    end)
    |> fix_overlaps()
  end

  # Répartit les mots d'un texte sur l'intervalle [start, stop], au prorata de
  # leur longueur.
  defp spread_words(text, start, stop) do
    words = String.split(text, ~r/\s+/, trim: true)
    weights = Enum.map(words, &(String.length(&1) + 1))
    total = max(Enum.sum(weights), 1)
    span = stop - start

    {result, _} =
      words
      |> Enum.zip(weights)
      |> Enum.map_reduce(start, fn {word, weight}, cursor ->
        stop_w = cursor + div(span * weight, total)
        {%{text: word, start_ms: cursor, end_ms: stop_w}, stop_w}
      end)

    case result do
      [] -> []
      _ -> List.update_at(result, -1, &%{&1 | end_ms: stop})
    end
  end

  defp fix_overlaps(cues) do
    cues
    |> Enum.sort_by(& &1.start_ms)
    |> Enum.reject(&(Quotor.Text.normalize(&1.text) == ""))
  end

  @doc false
  def clean_text(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\[[^\]]*\]|\([A-ZÉÈ\s]+\)/u, "")
    |> String.replace(["♪", "♫"], "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&#39;", "'")
    |> String.replace("&quot;", "\"")
    |> String.replace(~r/^\s*-\s*/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
