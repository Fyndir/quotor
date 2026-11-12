defmodule Quotor.Ingest.YtDlp do
  @moduledoc """
  Téléchargement via [yt-dlp](https://github.com/yt-dlp/yt-dlp) : vidéo en
  480p max + sous-titres français (manuels de préférence, sinon automatiques).

  Variables d'environnement utiles :

    * `YTDLP_PATH` — chemin de l'exécutable (défaut `yt-dlp`) ;
    * `YTDLP_COOKIES` — fichier cookies.txt (YouTube bloque souvent les IP
      de datacenters sans cookies) ;
    * `YTDLP_EXTRA_ARGS` — arguments supplémentaires (séparés par des espaces).
  """
  @behaviour Quotor.Ingest.Downloader

  require Logger

  @sub_priority ~w(fr fr-FR fr-CA fr-orig)

  @impl true
  def fetch(url, workdir) do
    args =
      [
        "--no-playlist",
        "--no-progress",
        "--no-warnings",
        "-f",
        "bv*[height<=480][ext=mp4]+ba[ext=m4a]/b[height<=480]/bv*+ba/b",
        "--merge-output-format",
        "mp4",
        "--write-subs",
        "--write-auto-subs",
        "--sub-langs",
        Enum.join(@sub_priority, ","),
        "--sub-format",
        "vtt",
        "--write-info-json",
        "-o",
        Path.join(workdir, "video.%(ext)s")
      ] ++ common_args() ++ [url]

    with {:ok, _} <- run(args, true),
         {:ok, video} <- find_video(workdir) do
      {:ok,
       %{
         video_path: video,
         subtitle_path: find_subtitle(workdir),
         metadata: read_info(workdir)
       }}
    end
  end

  @impl true
  def list_channel(url, limit) do
    args =
      ["--flat-playlist", "-J", "--playlist-end", to_string(limit)] ++
        common_args() ++ [videos_url(url)]

    with {:ok, out} <- run(args, false),
         {:ok, json} <- Jason.decode(out) do
      {:ok, json |> flatten_entries() |> Enum.take(limit)}
    else
      {:error, %Jason.DecodeError{}} -> {:error, "réponse yt-dlp illisible"}
      error -> error
    end
  end

  # https://www.youtube.com/@handle -> https://www.youtube.com/@handle/videos
  defp videos_url(url) do
    uri = URI.parse(url)

    if uri.path && Regex.match?(~r{^/(@[^/]+|c/[^/]+|channel/[^/]+|user/[^/]+)/?$}, uri.path) do
      String.trim_trailing(url, "/") <> "/videos"
    else
      url
    end
  end

  defp flatten_entries(%{"entries" => entries}) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"_type" => "playlist"} = sub -> flatten_entries(sub)
      %{"id" => id} = e when is_binary(id) -> [%{id: id, title: e["title"]}]
      _ -> []
    end)
  end

  defp flatten_entries(_), do: []

  defp common_args do
    cookies =
      case System.get_env("YTDLP_COOKIES") do
        nil -> []
        "" -> []
        path -> ["--cookies", path]
      end

    extra =
      case System.get_env("YTDLP_EXTRA_ARGS") do
        nil -> []
        args -> String.split(args, " ", trim: true)
      end

    cookies ++ extra
  end

  defp find_video(workdir) do
    workdir
    |> File.ls!()
    |> Enum.find(&(Path.extname(&1) in ~w(.mp4 .mkv .webm) and String.starts_with?(&1, "video.")))
    |> case do
      nil -> {:error, "aucune vidéo téléchargée"}
      file -> {:ok, Path.join(workdir, file)}
    end
  end

  defp find_subtitle(workdir) do
    files = File.ls!(workdir)

    Enum.find_value(@sub_priority, fn lang ->
      name = "video.#{lang}.vtt"
      if name in files, do: Path.join(workdir, name)
    end) ||
      Enum.find_value(files, fn f ->
        if String.ends_with?(f, ".vtt"), do: Path.join(workdir, f)
      end)
  end

  defp read_info(workdir) do
    with {:ok, body} <- File.read(Path.join(workdir, "video.info.json")),
         {:ok, info} <- Jason.decode(body) do
      %{
        title: info["title"],
        uploader: info["uploader"] || info["channel"],
        duration_s: info["duration"] && round(info["duration"]),
        published_on: parse_date(info["upload_date"])
      }
    else
      _ -> %{}
    end
  end

  defp parse_date(<<y::binary-4, m::binary-2, d::binary-2>>) do
    case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp run(args, merge_stderr?) do
    exe = System.get_env("YTDLP_PATH", "yt-dlp")

    case System.find_executable(exe) do
      nil ->
        {:error, "yt-dlp introuvable"}

      path ->
        Logger.debug("yt-dlp #{Enum.join(args, " ")}")

        case System.cmd(path, args, stderr_to_stdout: merge_stderr?) do
          {out, 0} ->
            {:ok, out}

          {out, code} ->
            {:error, "yt-dlp a échoué (code #{code}) #{String.slice(out, -500, 500)}"}
        end
    end
  end
end
