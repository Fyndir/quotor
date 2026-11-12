defmodule Quotor.Montages do
  @moduledoc """
  Mode avancé : assemble plusieurs morceaux de quotes pour « faire dire » une
  phrase. Les montages sont mis en cache par empreinte des segments : la même
  phrase avec les mêmes extraits n'est rendue qu'une fois.
  """

  import Ecto.Query
  require Logger

  alias Quotor.{Media, Repo, Search}
  alias Quotor.Accounts.Scope
  alias Quotor.Media.Ffmpeg
  alias Quotor.Montages.Montage

  @doc """
  Planifie puis rend un montage.

  Renvoie `{:ok, montage}`, `{:error, :empty}` (requête vide),
  `{:error, :no_match}` (aucun mot trouvé) ou `{:error, message}`.
  """
  def build(query, scope, opts \\ []) do
    query = query |> String.trim() |> String.slice(0, 300)
    plan = Search.plan(query, opts)

    cond do
      query == "" -> {:error, :empty}
      plan.segments == [] -> {:error, :no_match}
      true -> plan |> find_or_create(query, scope) |> render()
    end
  end

  defp find_or_create(plan, query, scope) do
    segments = Enum.map(plan.segments, &serialize_segment/1)
    key = key(segments)
    user_id = Scope.user_id(scope)

    case Repo.get_by(Montage, key: key) do
      %Montage{user_id: nil} = m when not is_nil(user_id) ->
        m |> Ecto.Changeset.change(user_id: user_id) |> Repo.update!()

      %Montage{} = m ->
        m

      nil ->
        Repo.insert!(
          %Montage{
            key: key,
            query: query,
            segments: segments,
            missing: plan.missing,
            user_id: user_id
          },
          on_conflict: :nothing,
          conflict_target: :key
        )
        |> case do
          %Montage{id: nil} -> Repo.get_by!(Montage, key: key)
          m -> m
        end
    end
  end

  defp serialize_segment(seg) do
    %{
      "quote_id" => seg.quote_id,
      "source_id" => seg.source_id,
      "clip_path" => seg.clip_path,
      "offset_ms" => seg.from_ms - seg.clip_start_ms,
      "duration_ms" => seg.to_ms - seg.from_ms,
      "text" => seg.text,
      "source_title" => seg.source_title
    }
  end

  defp key(segments) do
    segments
    |> Enum.map(&[&1["quote_id"], &1["offset_ms"], &1["duration_ms"]])
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 22)
  end

  defp render(%Montage{status: "ready", file_path: path} = montage) when is_binary(path) do
    if File.exists?(Media.abs_path(path)), do: {:ok, montage}, else: do_render(montage)
  end

  defp render(%Montage{} = montage), do: do_render(montage)

  defp do_render(%Montage{} = montage) do
    rel = Media.montage_rel(montage.key)
    out = Media.prepare!(rel)

    parts =
      Enum.map(montage.segments, fn seg ->
        {Media.abs_path(seg["clip_path"]), seg["offset_ms"], seg["duration_ms"]}
      end)

    started = System.monotonic_time(:millisecond)

    case Ffmpeg.concat(parts, out) do
      {:ok, _} ->
        Logger.info(
          "montage #{montage.key} rendu (#{length(parts)} segments, #{System.monotonic_time(:millisecond) - started} ms)"
        )

        montage
        |> Ecto.Changeset.change(status: "ready", file_path: rel, error: nil)
        |> Repo.update()

      {:error, msg} ->
        Logger.error("montage #{montage.key} en échec : #{msg}")

        montage
        |> Ecto.Changeset.change(status: "failed", error: msg)
        |> Repo.update()

        {:error, "Le rendu du montage a échoué."}
    end
  end

  def get_by_key(key), do: Repo.get_by(Montage, key: key, status: "ready")

  @doc "Vignette du premier extrait du montage (affiche, aperçu Discord)."
  def poster_rel(%Montage{segments: [%{"source_id" => sid, "quote_id" => qid} | _]}),
    do: Media.thumb_rel(sid, qid)

  def poster_rel(_), do: nil

  def list_for_user(%Scope{user: user}) do
    Repo.all(
      from m in Montage,
        where: m.user_id == ^user.id and m.status == "ready",
        order_by: [desc: m.updated_at],
        limit: 100
    )
  end

  def count, do: Repo.aggregate(Montage, :count)

  @doc "Supprime les montages anonymes de plus de `days` jours (tâche de nettoyage)."
  def purge_anonymous(days \\ 7) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    old =
      Repo.all(from m in Montage, where: is_nil(m.user_id) and m.updated_at < ^cutoff)

    Enum.each(old, &Media.delete(&1.file_path))
    {count, _} = Repo.delete_all(from m in Montage, where: m.id in ^Enum.map(old, & &1.id))
    count
  end
end
