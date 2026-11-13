defmodule Quotor.Media.Ffmpeg do
  @moduledoc "Appels à ffmpeg / ffprobe (découpe des clips, vignettes, montages)."

  require Logger

  @width 640
  @height 360

  defp ffmpeg, do: Application.get_env(:quotor, :ffmpeg_path, "ffmpeg")
  defp ffprobe, do: Application.get_env(:quotor, :ffprobe_path, "ffprobe")

  @doc "ffmpeg est-il disponible ?"
  def available? do
    System.find_executable(ffmpeg()) != nil
  end

  @doc "Découpe `[start_ms, start_ms + duration_ms]` de `input` vers `output` (mp4 H.264/AAC)."
  def cut_clip(input, start_ms, duration_ms, output) do
    run(ffmpeg(), [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      seconds(start_ms),
      "-i",
      input,
      "-t",
      seconds(duration_ms),
      "-vf",
      "scale=-2:'min(480,ih)'",
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "27",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "aac",
      "-b:a",
      "96k",
      "-ac",
      "2",
      "-ar",
      "44100",
      "-movflags",
      "+faststart",
      output
    ])
  end

  @doc "Extrait une image JPEG à `at_ms` de `input`."
  def thumbnail(input, at_ms, output) do
    run(ffmpeg(), [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      seconds(at_ms),
      "-i",
      input,
      "-frames:v",
      "1",
      "-vf",
      "scale=-2:240",
      "-q:v",
      "5",
      output
    ])
  end

  @doc """
  Assemble des morceaux de clips en une seule vidéo.

  `parts` est une liste de `{chemin, offset_ms, duree_ms}`. Toutes les entrées
  sont normalisées (640x360, 25 i/s, stéréo 44,1 kHz) avant concaténation.
  """
  def concat(parts, output) when parts != [] do
    inputs =
      Enum.flat_map(parts, fn {path, offset, duration} ->
        ["-ss", seconds(offset), "-t", seconds(duration), "-i", path]
      end)

    n = length(parts)

    filters =
      0..(n - 1)
      |> Enum.map(fn i ->
        "[#{i}:v]scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
          "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=25,format=yuv420p[v#{i}];" <>
          "[#{i}:a]aresample=44100,aformat=channel_layouts=stereo[a#{i}]"
      end)
      |> Enum.join(";")

    streams = Enum.map_join(0..(n - 1), "", &"[v#{&1}][a#{&1}]")
    filter = filters <> ";" <> streams <> "concat=n=#{n}:v=1:a=1[v][a]"

    run(
      ffmpeg(),
      ["-hide_banner", "-loglevel", "error", "-y"] ++
        inputs ++
        [
          "-filter_complex",
          filter,
          "-map",
          "[v]",
          "-map",
          "[a]",
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-crf",
          "26",
          "-c:a",
          "aac",
          "-b:a",
          "128k",
          "-movflags",
          "+faststart",
          output
        ]
    )
  end

  @doc "Extrait `[start_ms, start_ms + duration_ms]` de la piste audio en WAV mono 16 kHz."
  def audio_segment(input, start_ms, duration_ms, output) do
    run(ffmpeg(), [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      seconds(start_ms),
      "-i",
      input,
      "-t",
      seconds(duration_ms),
      "-vn",
      "-ac",
      "1",
      "-ar",
      "16000",
      "-c:a",
      "pcm_s16le",
      output
    ])
  end

  @doc "Silence de `ms` millisecondes (WAV mono 16 kHz)."
  def silence(ms, output) do
    run(ffmpeg(), [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "lavfi",
      "-t",
      seconds(ms),
      "-i",
      "anullsrc=r=16000:cl=mono",
      "-c:a",
      "pcm_s16le",
      output
    ])
  end

  @doc "Met bout à bout des WAV de même format (mono 16 kHz) sans réencodage."
  def concat_audio(files, output, workdir) do
    list = Path.join(workdir, "concat-#{System.unique_integer([:positive])}.txt")
    File.write!(list, Enum.map_join(files, "\n", &"file '#{String.replace(&1, "'", "'\\''")}'"))

    run(ffmpeg(), [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      list,
      "-c",
      "copy",
      output
    ])
  end

  @doc "Extrait la piste audio en WAV mono 16 kHz (format attendu par whisper.cpp)."
  def extract_audio(input, output) do
    run(ffmpeg(), [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-i",
      input,
      "-vn",
      "-ac",
      "1",
      "-ar",
      "16000",
      "-c:a",
      "pcm_s16le",
      output
    ])
  end

  @doc "Durée d'un fichier média en millisecondes."
  def duration_ms(path) do
    case run(ffprobe(), [
           "-v",
           "error",
           "-show_entries",
           "format=duration",
           "-of",
           "csv=p=0",
           path
         ]) do
      {:ok, out} ->
        case Float.parse(String.trim(out)) do
          {secs, _} -> {:ok, round(secs * 1000)}
          :error -> {:error, "durée illisible"}
        end

      error ->
        error
    end
  end

  defp seconds(ms), do: :erlang.float_to_binary(max(ms, 0) / 1000, decimals: 3)

  defp run(cmd, args) do
    case System.find_executable(cmd) do
      nil ->
        {:error, "#{cmd} introuvable"}

      exe ->
        case System.cmd(exe, args, stderr_to_stdout: true) do
          {out, 0} ->
            {:ok, out}

          {out, code} ->
            msg = out |> String.split("\n", trim: true) |> Enum.take(-5) |> Enum.join(" | ")
            Logger.warning("#{Path.basename(cmd)} a échoué (#{code}) : #{msg}")
            {:error, "#{Path.basename(cmd)} (code #{code}) : #{msg}"}
        end
    end
  end
end
