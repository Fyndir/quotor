defmodule Quotor.FakeDownloader do
  @moduledoc """
  Téléchargeur factice pour les tests : génère une courte vidéo avec ffmpeg
  (mire + bip) et fournit des sous-titres automatiques de test.

  Les URLs contenant `nosubs` simulent une vidéo sans sous-titres, celles
  contenant `fail` une erreur de téléchargement.
  """
  @behaviour Quotor.Ingest.Downloader

  @fixture Path.expand("fixtures/auto.fr.vtt", __DIR__)

  @impl true
  def fetch(url, workdir) do
    cond do
      String.contains?(url, "fail") ->
        {:error, "HTTP Error 403: Forbidden"}

      true ->
        video = Path.join(workdir, "video.mp4")
        :ok = generate_video(video, 7)

        subtitle =
          if String.contains?(url, "nosubs") do
            nil
          else
            dest = Path.join(workdir, "video.fr.vtt")
            File.cp!(@fixture, dest)
            dest
          end

        {:ok,
         %{
           video_path: video,
           subtitle_path: subtitle,
           metadata: %{
             title: "Vidéo de test",
             uploader: "Chaîne test",
             channel_url: "https://www.youtube.com/@chainetest",
             duration_s: 7
           }
         }}
    end
  end

  @impl true
  def list_channel(_url, limit) do
    entries =
      for i <- 1..3, do: %{id: "chan#{i}aaaaaa" |> String.slice(0, 11), title: "Vidéo #{i}"}

    {:ok, Enum.take(entries, limit)}
  end

  @doc "Génère une vidéo de test de `seconds` secondes."
  def generate_video(path, seconds) do
    {_, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-hide_banner",
          "-loglevel",
          "error",
          "-y",
          "-f",
          "lavfi",
          "-i",
          "testsrc=size=320x240:rate=25:duration=#{seconds}",
          "-f",
          "lavfi",
          "-i",
          "sine=frequency=440:duration=#{seconds}",
          "-c:v",
          "libx264",
          "-preset",
          "ultrafast",
          "-pix_fmt",
          "yuv420p",
          "-c:a",
          "aac",
          "-shortest",
          path
        ],
        stderr_to_stdout: true
      )

    :ok
  end
end
