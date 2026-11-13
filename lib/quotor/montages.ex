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
  alias Quotor.Montages.{Check, Montage}

  @doc """
  Planifie puis rend un montage.

  Renvoie `{:ok, montage}`, `{:error, :empty}` (requête vide),
  `{:error, :no_match}` (aucun mot trouvé) ou `{:error, message}`.
  """
  def build(query, scope, opts \\ []) do
    query = query |> String.trim() |> String.slice(0, 300)
    plan = Search.plan(query, opts)

    cond do
      query == "" ->
        {:error, :empty}

      plan.segments == [] ->
        {:error, :no_match}

      true ->
        plan_key = plan.segments |> Enum.map(&serialize_segment/1) |> key()

        case checked_montage(plan_key) do
          %Montage{} = m ->
            # ce plan a déjà été contrôlé et rendu : servi tel quel
            m |> claim(Scope.user_id(scope)) |> render()

          nil ->
            {plan, check} = check(plan)
            plan |> find_or_create(query, scope, plan_key, check) |> render()
        end
    end
  end

  defp checked_montage(plan_key) do
    from(m in Montage,
      where: m.plan_key == ^plan_key and m.status == "ready" and not is_nil(m.asr_score),
      limit: 1
    )
    |> Repo.one()
  end

  # Contrôle à l'écoute (cf. Quotor.Montages.Check), si la transcription est
  # disponible sur ce nœud ; sinon le montage est livré sans contrôle.
  defp check(plan) do
    if Check.enabled?() do
      workdir = Media.tmp_dir!("check-#{System.unique_integer([:positive])}")

      try do
        case Check.run(plan.segments, workdir) do
          {:ok, segments, result} ->
            {%{plan | segments: segments}, result}

          {:error, reason} ->
            Logger.warning("montage non contrôlé : #{inspect(reason)}")
            {plan, nil}
        end
      after
        File.rm_rf(workdir)
      end
    else
      {plan, nil}
    end
  end

  defp claim(%Montage{user_id: nil} = m, user_id) when not is_nil(user_id),
    do: m |> Ecto.Changeset.change(user_id: user_id) |> Repo.update!()

  defp claim(m, _user_id), do: m

  defp find_or_create(plan, query, scope, plan_key, check) do
    segments = Enum.map(plan.segments, &serialize_segment/1)
    key = key(segments)
    user_id = Scope.user_id(scope)

    check_fields =
      case check do
        %{asr_score: score, doubtful: doubtful} ->
          [asr_score: score, doubtful: doubtful, plan_key: plan_key]

        nil ->
          []
      end

    case Repo.get_by(Montage, key: key) do
      %Montage{} = m ->
        m = claim(m, user_id)

        if check_fields == [],
          do: m,
          else: m |> Ecto.Changeset.change(check_fields) |> Repo.update!()

      nil ->
        Repo.insert!(
          struct!(
            %Montage{
              key: key,
              query: query,
              segments: segments,
              missing: plan.missing,
              user_id: user_id
            },
            check_fields
          ),
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
    if Media.exists?(path), do: {:ok, montage}, else: do_render(montage)
  end

  defp render(%Montage{} = montage), do: do_render(montage)

  defp do_render(%Montage{} = montage) do
    rel = Media.montage_rel(montage.key)
    workdir = Media.tmp_dir!("montage-#{montage.key}-#{System.unique_integer([:positive])}")
    out = Path.join(workdir, "montage.mp4")
    started = System.monotonic_time(:millisecond)

    # Les clips sont pris dans le cache local (ou téléchargés depuis le stockage).
    result =
      try do
        with {:ok, parts} <- local_parts(montage.segments),
             {:ok, _} <- Ffmpeg.concat(parts, out),
             :ok <- Media.store(out, rel) do
          :ok
        end
      after
        File.rm_rf(workdir)
      end

    case result do
      :ok ->
        Logger.info(
          "montage #{montage.key} rendu (#{length(montage.segments)} segments, #{System.monotonic_time(:millisecond) - started} ms)"
        )

        montage
        |> Ecto.Changeset.change(status: "ready", file_path: rel, error: nil)
        |> Repo.update()

      {:error, msg} ->
        msg = if is_binary(msg), do: msg, else: inspect(msg)
        Logger.error("montage #{montage.key} en échec : #{msg}")

        montage
        |> Ecto.Changeset.change(status: "failed", error: msg)
        |> Repo.update()

        {:error, "Le rendu du montage a échoué."}
    end
  end

  defp local_parts(segments) do
    Enum.reduce_while(segments, {:ok, []}, fn seg, {:ok, acc} ->
      case Media.fetch(seg["clip_path"]) do
        {:ok, path} -> {:cont, {:ok, [{path, seg["offset_ms"], seg["duration_ms"]} | acc]}}
        {:error, reason} -> {:halt, {:error, "clip #{seg["clip_path"]} : #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
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

  ## Découvrir : les montages des utilisateurs

  @doc """
  Montages publics pour « Découvrir » : ceux des utilisateurs connectés, prêts,
  que leur auteur n'a pas retirés, et dont **tous les extraits sont encore
  visibles** (un extrait masqué ou retiré suite à un signalement fait
  disparaître les montages qui l'utilisent). `sort` : `:random`, `:recent`,
  `:popular`.
  """
  def list_public(sort, limit, offset \\ 0) do
    from(m in Montage,
      where: not is_nil(m.user_id) and m.listed and m.status == "ready",
      where:
        fragment(
          """
          NOT EXISTS (
            SELECT 1 FROM unnest(?) AS seg
            LEFT JOIN quotes q ON q.id = (seg->>'quote_id')::bigint
            LEFT JOIN sources s ON s.id = q.source_id
            WHERE q.id IS NULL OR q.status <> 'ready' OR NOT q.enabled OR NOT s.enabled
          )
          """,
          m.segments
        ),
      limit: ^limit,
      offset: ^offset
    )
    |> order_public(sort)
    |> Repo.all()
  end

  defp order_public(query, :random), do: order_by(query, fragment("random()"))
  defp order_public(query, :recent), do: order_by(query, [m], desc: m.inserted_at, desc: m.id)

  defp order_public(query, :popular),
    do: order_by(query, [m], desc: m.views_count, desc: m.inserted_at, desc: m.id)

  def increment_views(%Montage{id: id}) do
    from(m in Montage, where: m.id == ^id) |> Repo.update_all(inc: [views_count: 1])
  end

  @doc "Le montage appartient-il à l'utilisateur de `scope` ?"
  def owner?(%Montage{user_id: uid}, %Scope{user: %{id: uid}}) when not is_nil(uid), do: true
  def owner?(_, _), do: false

  @doc "Affiche ou retire un montage de « Découvrir » (son auteur uniquement)."
  def set_listed(%Montage{} = montage, scope, listed) when is_boolean(listed) do
    if owner?(montage, scope) do
      montage |> Ecto.Changeset.change(listed: listed) |> Repo.update()
    else
      {:error, :forbidden}
    end
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
