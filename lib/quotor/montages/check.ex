defmodule Quotor.Montages.Check do
  @moduledoc """
  Contrôle à l'écoute d'un montage, **avant** son rendu et sa livraison.

  Chaque morceau du plan (un bout d'extrait censé dire quelques mots de la
  phrase) est réécouté par la transcription vocale, avec 0,4 s de contexte
  autour (whisper reconnaît mal un mot isolé de 300 ms). Tous les morceaux
  passent en un seul lancement du moteur. Pour chacun :

    * les mots attendus sont alignés sur ce qui est entendu ;
    * un mot entendu mais **coupé** par les bornes du morceau (il déborde
      dans le contexte) fait recaler la borne sur la parole, de 250 ms au
      plus, sans sortir du clip ;
    * si le morceau ne dit pas assez ses mots (fiabilité sous
      `Quotor.Ingest.Transcriber.min_score/0`), un **autre extrait** disant la
      même expression est essayé (deux fois au plus), et le meilleur est gardé.

  Le résultat donne la fiabilité globale (part des mots de la phrase
  entendus) et les mots restés douteux, affichés à l'utilisateur.
  """

  require Logger

  alias Quotor.{Media, Search}
  alias Quotor.Ingest.{Alignment, Transcriber}
  alias Quotor.Media.Ffmpeg

  @context_ms 400
  # tolérance sur les horodatages de whisper avant de considérer un mot coupé
  @tolerance_ms 80
  @max_shift_ms 250
  @lead_ms 60
  @tail_ms 120
  @rounds 2

  @doc "Le contrôle est-il possible sur ce nœud ?"
  def enabled?, do: Transcriber.enabled?()

  @doc """
  Contrôle et corrige les segments d'un plan (cf. `Quotor.Search.plan/2`).
  Renvoie `{:ok, segments, %{asr_score: float, doubtful: [mot]}}`, ou
  `{:error, raison}` si le moteur est indisponible.
  """
  def run(segments, workdir) when segments != [] do
    started = System.monotonic_time(:millisecond)

    with {:ok, evals} <- evaluate(segments, workdir) do
      checked =
        segments
        |> Enum.zip(evals)
        |> Enum.map(fn {seg, eval} -> {seg, eval, [seg.quote_id]} end)
        |> improve(workdir, 1)

      segments =
        Enum.map(checked, fn {seg, eval, _} ->
          %{seg | from_ms: eval.from_ms, to_ms: eval.to_ms}
        end)

      total = checked |> Enum.map(fn {_, e, _} -> e.tokens end) |> Enum.sum()
      heard = checked |> Enum.map(fn {_, e, _} -> e.heard end) |> Enum.sum()
      doubtful = Enum.flat_map(checked, fn {_, e, _} -> e.missing end)
      score = if total == 0, do: 0.0, else: Float.round(heard / total, 3)

      Logger.info(
        "montage contrôlé à l'écoute : #{round(score * 100)} % (#{length(segments)} morceaux, #{System.monotonic_time(:millisecond) - started} ms)"
      )

      {:ok, segments, %{asr_score: score, doubtful: doubtful}}
    end
  end

  # Remplace les morceaux trop peu fiables par un autre extrait, si mieux.
  defp improve(checked, _workdir, round) when round > @rounds, do: checked

  # `checked` : liste de `{segment, évaluation, extraits déjà essayés}`.
  defp improve(checked, workdir, round) do
    # morceaux faibles pour lesquels un autre extrait existe : {indice, autre segment}
    weak =
      checked
      |> Enum.with_index()
      |> Enum.flat_map(fn {{seg, eval, tried}, i} ->
        with true <- eval.score < Transcriber.min_score(),
             %{} = alt <- Search.alternative(tokens(seg), tried) do
          [{i, alt}]
        else
          _ -> []
        end
      end)

    case weak do
      [] ->
        checked

      weak ->
        case evaluate(Enum.map(weak, &elem(&1, 1)), workdir) do
          {:ok, alt_evals} ->
            candidates =
              weak |> Enum.zip(alt_evals) |> Map.new(fn {{i, alt}, e} -> {i, {alt, e}} end)

            checked
            |> Enum.with_index()
            |> Enum.map(fn {{seg, eval, tried}, i} ->
              case candidates do
                %{^i => {alt, alt_eval}} ->
                  tried = [alt.quote_id | tried]

                  if alt_eval.score > eval.score,
                    do: {alt, alt_eval, tried},
                    else: {seg, eval, tried}

                _ ->
                  {seg, eval, tried}
              end
            end)
            |> improve(workdir, round + 1)

          {:error, reason} ->
            Logger.warning("contrôle du montage : autres extraits non vérifiés (#{reason})")
            checked
        end
    end
  end

  defp tokens(seg), do: String.split(seg.text, " ", trim: true)

  # Écoute un lot de morceaux (un seul lancement du moteur).
  defp evaluate(segments, workdir) do
    pieces = Enum.map(segments, &piece(&1, workdir))

    paths = for {:ok, p} <- pieces, do: p.path

    with {:ok, results} <- transcribe(paths, workdir) do
      by_path = Map.new(Enum.zip(paths, results))

      evals =
        segments
        |> Enum.zip(pieces)
        |> Enum.map(fn
          {seg, {:ok, p}} -> judge(seg, p, Map.fetch!(by_path, p.path))
          {seg, {:error, _}} -> judge(seg, nil, {:error, :no_audio})
        end)

      {:ok, evals}
    end
  end

  defp transcribe([], _workdir), do: {:ok, []}
  defp transcribe(paths, workdir), do: Transcriber.impl().transcribe_many(paths, workdir)

  # Audio du morceau, avec du contexte de part et d'autre (dans le clip).
  defp piece(seg, workdir) do
    clip_len = seg.clip_end_ms - seg.clip_start_ms
    ctx_start = max(seg.from_ms - seg.clip_start_ms - @context_ms, 0)
    ctx_end = min(seg.to_ms - seg.clip_start_ms + @context_ms, clip_len)
    path = Path.join(workdir, "#{seg.quote_id}-#{System.unique_integer([:positive])}.wav")

    with {:ok, clip} <- Media.fetch(seg.clip_path),
         {:ok, _} <- Ffmpeg.audio_segment(clip, ctx_start, ctx_end - ctx_start, path) do
      # temps absolu (dans la vidéo source) du début de l'audio extrait
      {:ok, %{path: path, origin_ms: seg.clip_start_ms + ctx_start}}
    end
  end

  defp judge(seg, piece, result) do
    tokens = tokens(seg)
    base = %{tokens: length(tokens), from_ms: seg.from_ms, to_ms: seg.to_ms}

    case {piece, result} do
      {%{origin_ms: origin}, {:ok, words}} ->
        {pairs, heard} = Alignment.match(tokens, words)
        heard = List.to_tuple(heard)
        by_token = Map.new(pairs)
        matched = map_size(by_token)

        at = fn i -> by_token[i] && elem(heard, by_token[i]) end
        first = at.(0)
        last = at.(length(tokens) - 1)

        from_ms =
          if first && origin + first.start_ms < seg.from_ms - @tolerance_ms,
            do:
              Enum.max([
                origin + first.start_ms - @lead_ms,
                seg.from_ms - @max_shift_ms,
                seg.clip_start_ms
              ]),
            else: seg.from_ms

        to_ms =
          if last && origin + last.end_ms > seg.to_ms + @tolerance_ms,
            do:
              Enum.min([
                origin + last.end_ms + @tail_ms,
                seg.to_ms + @max_shift_ms,
                seg.clip_end_ms
              ]),
            else: seg.to_ms

        missing = for {t, i} <- Enum.with_index(tokens), !Map.has_key?(by_token, i), do: t

        Map.merge(base, %{
          score: if(tokens == [], do: 0.0, else: matched / length(tokens)),
          heard: matched,
          missing: missing,
          from_ms: from_ms,
          to_ms: to_ms
        })

      _ ->
        Map.merge(base, %{score: 0.0, heard: 0, missing: tokens})
    end
  end
end
