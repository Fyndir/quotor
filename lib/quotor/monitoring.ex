defmodule Quotor.Monitoring do
  @moduledoc "Indicateurs de supervision pour le tableau de bord admin."

  import Ecto.Query

  alias Quotor.{Accounts, Catalog, Logs, Montages, Repo}

  @doc "Instantané global (appelé périodiquement par le dashboard)."
  def snapshot do
    %{
      system: system(),
      database: database(),
      jobs: jobs(),
      catalog: %{
        sources: Catalog.count_sources_by_status(),
        quotes: Catalog.count_quotes(),
        montages: Montages.count(),
        open_reports: Catalog.count_open_reports(),
        to_review: Catalog.count_quotes_to_review(),
        users: Accounts.count_users_by_role()
      },
      errors_last_hour: Logs.error_count(60),
      tools: tools(),
      at: DateTime.utc_now(:second)
    }
  end

  def system do
    mem = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      uptime_ms: uptime_ms,
      memory_total: mem[:total],
      memory_processes: mem[:processes],
      memory_binary: mem[:binary],
      memory_ets: mem[:ets],
      process_count: :erlang.system_info(:process_count),
      run_queue: :erlang.statistics(:run_queue),
      schedulers: :erlang.system_info(:schedulers_online),
      otp: to_string(:erlang.system_info(:otp_release)),
      elixir: System.version(),
      version: Application.spec(:quotor, :vsn) |> to_string(),
      node: to_string(node()),
      role: Application.get_env(:quotor, :role, :all),
      storage: storage_label(),
      queues: local_queues()
    }
  end

  defp storage_label do
    if Quotor.Storage.local?() do
      "disque local"
    else
      s3 = Application.get_env(:quotor, :s3, [])
      mode = if s3[:public_url] in [nil, ""], do: "privé, relayé", else: "public"
      "S3 · #{s3[:bucket]} (#{mode})"
    end
  end

  # Files Oban exécutées par ce nœud (vide pour un nœud « web »)
  defp local_queues do
    Oban.config().queues
    |> Enum.map(fn {queue, opts} -> {queue, opts[:limit] || opts} end)
  rescue
    _ -> []
  end

  def database do
    started = System.monotonic_time(:microsecond)

    try do
      %{rows: [[size]]} =
        Repo.query!("SELECT pg_database_size(current_database())", [], timeout: 5_000)

      %{
        ok: true,
        latency_ms: Float.round((System.monotonic_time(:microsecond) - started) / 1000, 1),
        size: size,
        pool_size: Repo.config()[:pool_size]
      }
    rescue
      e -> %{ok: false, error: Exception.message(e)}
    end
  end

  def jobs do
    counts =
      from(j in Oban.Job,
        where: j.state in ["available", "scheduled", "executing", "retryable", "discarded"],
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )
      |> Repo.all()

    failures =
      from(j in Oban.Job,
        where: j.state in ["retryable", "discarded"],
        order_by: [desc: j.attempted_at],
        limit: 10,
        select: %{
          id: j.id,
          worker: j.worker,
          state: j.state,
          attempt: j.attempt,
          max_attempts: j.max_attempts,
          args: j.args,
          errors: j.errors,
          attempted_at: j.attempted_at
        }
      )
      |> Repo.all()
      |> Enum.map(fn j ->
        last = j.errors |> List.last() |> Kernel.||(%{}) |> Map.get("error", "")
        Map.put(j, :last_error, String.slice(last, 0, 400))
      end)

    by_queue =
      Enum.reduce(counts, %{}, fn {queue, state, n}, acc ->
        Map.update(acc, queue, %{state => n}, &Map.put(&1, state, n))
      end)

    %{by_queue: by_queue, failures: failures}
  rescue
    _ -> %{by_queue: %{}, failures: []}
  end

  def tools do
    %{
      ffmpeg: System.find_executable(Application.get_env(:quotor, :ffmpeg_path, "ffmpeg")) != nil,
      yt_dlp: System.find_executable(System.get_env("YTDLP_PATH", "yt-dlp")) != nil,
      transcription: transcription_label()
    }
  end

  # Transcription vocale sur ce nœud : moteur, ou raison de son absence.
  defp transcription_label do
    alias Quotor.Ingest.Transcriber

    cond do
      Transcriber.enabled?() -> Transcriber.impl().label()
      Transcriber.impl().available?() -> "désactivée (TRANSCRIBE=false)"
      true -> "non installée"
    end
  end

  @doc "Vérification de santé (endpoint `/health`)."
  def healthy? do
    match?({:ok, _}, Repo.query("SELECT 1", [], timeout: 2_000))
  rescue
    _ -> false
  end

  def human_bytes(nil), do: "–"
  def human_bytes(b) when b < 1024, do: "#{b} o"
  def human_bytes(b) when b < 1024 * 1024, do: "#{Float.round(b / 1024, 1)} Ko"
  def human_bytes(b) when b < 1024 * 1024 * 1024, do: "#{Float.round(b / 1024 / 1024, 1)} Mo"
  def human_bytes(b), do: "#{Float.round(b / 1024 / 1024 / 1024, 2)} Go"

  def human_duration(ms) do
    s = div(ms, 1000)
    d = div(s, 86_400)
    h = div(rem(s, 86_400), 3600)
    m = div(rem(s, 3600), 60)

    cond do
      d > 0 -> "#{d} j #{h} h"
      h > 0 -> "#{h} h #{m} min"
      true -> "#{m} min #{rem(s, 60)} s"
    end
  end
end
