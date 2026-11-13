defmodule Quotor.Ingest.Refine do
  @moduledoc """
  Affinage des clips découpés, avant publication.

  Les clips sortis de la découpe sont « bruts ». Chacun est réécouté par la
  transcription vocale (tous les clips d'une vidéo en un seul passage de
  whisper.cpp), puis son texte est aligné sur ce qui est entendu :

    * **premier ou dernier mot absent** (ou collé au bord du clip, donc
      probablement coupé) → le clip est élargi de 0,5 s de ce côté et
      redécoupé, sans empiéter sur les phrases voisines ; jusqu'à deux
      élargissements ;
    * **fiabilité** = part des mots du texte réellement entendus dans le clip.

  Seuls les clips complets dont la fiabilité atteint
  `Quotor.Ingest.Transcriber.min_score/0` sont publiés (`ready`) ; les autres
  passent « à vérifier » (`review`) et attendent la validation d'un admin.
  """

  require Logger

  alias Quotor.Ingest.{Alignment, Transcriber}

  @max_widen 2
  @widen_ms 500
  # un mot qui commence (ou finit) à moins de 40 ms du bord a sans doute été coupé
  @edge_ms 40

  @type item :: %{
          quote: Quotor.Catalog.Quote.t(),
          clip: String.t(),
          thumb: String.t(),
          clip_start_ms: integer(),
          clip_end_ms: integer()
        }

  @doc """
  Affine les clips `items`. `neighbours` sont toutes les quotes de la vidéo
  (pour ne pas déborder sur les phrases voisines) ; `recut.(item, start, end)`
  redécoupe un clip et renvoie `{:ok, item}`.

  Renvoie `{:ok, [{item, %{status, asr_score}}]}` ou `{:error, raison}` si le
  moteur de transcription est indisponible.
  """
  def run(items, neighbours, workdir, recut) do
    bounds = neighbour_bounds(neighbours)
    pass(items, bounds, workdir, recut, 0, [])
  end

  defp pass([], _bounds, _workdir, _recut, _n, done), do: {:ok, Enum.reverse(done)}

  defp pass(items, bounds, workdir, recut, n, done) do
    with {:ok, results} <- Transcriber.impl().transcribe_many(Enum.map(items, & &1.clip), workdir) do
      evaluated = Enum.zip_with(items, results, &{&1, evaluate(&1, &2)})

      {retry, final} =
        Enum.split_with(evaluated, fn {item, eval} ->
          n < @max_widen and (eval.missing_start or eval.missing_end) and
            widened(item, eval, bounds) != {item.clip_start_ms, item.clip_end_ms}
        end)

      done = Enum.reduce(final, done, fn {item, eval}, acc -> [{item, verdict(eval)} | acc] end)

      recut_items =
        Enum.flat_map(retry, fn {item, eval} ->
          {start_ms, end_ms} = widened(item, eval, bounds)

          case recut.(item, start_ms, end_ms) do
            {:ok, item} ->
              [item]

            {:error, reason} ->
              Logger.warning(
                "quote #{item.quote.id} : élargissement impossible : #{inspect(reason)}"
              )

              []
          end
        end)

      # un clip qu'on n'a pas pu redécouper garde son évaluation
      kept =
        for {item, eval} <- retry,
            not Enum.any?(recut_items, &(&1.quote.id == item.quote.id)),
            do: {item, verdict(eval)}

      pass(recut_items, bounds, workdir, recut, n + 1, Enum.reverse(kept) ++ done)
    end
  end

  @doc false
  # Évalue un clip d'après ce qui y est entendu.
  def evaluate(item, {:ok, heard_words}) do
    tokens = String.split(item.quote.norm || "", " ", trim: true)
    {pairs, heard} = Alignment.match(tokens, heard_words)
    heard = List.to_tuple(heard)
    duration = item.clip_end_ms - item.clip_start_ms
    by_token = Map.new(pairs)
    last = length(tokens) - 1

    first_heard = by_token[0] && elem(heard, by_token[0])
    last_heard = by_token[last] && elem(heard, by_token[last])

    %{
      score: if(tokens == [], do: 0.0, else: Float.round(length(pairs) / length(tokens), 3)),
      missing_start: is_nil(first_heard) or first_heard.start_ms < @edge_ms,
      missing_end: is_nil(last_heard) or last_heard.end_ms > duration - @edge_ms
    }
  end

  def evaluate(_item, {:error, _reason}),
    do: %{score: 0.0, missing_start: false, missing_end: false}

  defp verdict(eval) do
    complete? = not eval.missing_start and not eval.missing_end

    status =
      if complete? and eval.score >= Transcriber.min_score(), do: "ready", else: "review"

    %{status: status, asr_score: eval.score}
  end

  # Nouvelles bornes du clip, élargi du côté où il manque un mot, sans entrer
  # dans la phrase précédente ou suivante.
  defp widened(item, eval, bounds) do
    {floor, ceiling} = Map.get(bounds, item.quote.id, {0, :infinity})

    start_ms =
      if eval.missing_start,
        do: max(item.clip_start_ms - @widen_ms, floor),
        else: item.clip_start_ms

    end_ms =
      if eval.missing_end,
        do: cap(item.clip_end_ms + @widen_ms, ceiling),
        else: item.clip_end_ms

    {max(min(start_ms, item.clip_start_ms), 0), max(end_ms, item.clip_end_ms)}
  end

  defp cap(value, :infinity), do: value
  defp cap(value, ceiling), do: min(value, ceiling)

  # Pour chaque quote : fin de la phrase précédente, début de la suivante.
  defp neighbour_bounds(quotes) do
    sorted = quotes |> Enum.sort_by(& &1.start_ms) |> List.to_tuple()
    n = tuple_size(sorted)

    for i <- 0..(n - 1)//1, into: %{} do
      q = elem(sorted, i)
      floor = if i > 0, do: min(elem(sorted, i - 1).end_ms, q.start_ms), else: 0
      ceiling = if i < n - 1, do: max(elem(sorted, i + 1).start_ms, q.end_ms), else: :infinity
      {q.id, {floor, ceiling}}
    end
  end
end
