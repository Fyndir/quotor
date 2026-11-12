defmodule Quotor.Ingest do
  @moduledoc """
  Alimentation du catalogue, entièrement en arrière-plan (Oban) :

      soumission (admin / chaîne suivie)
        └─ IngestSource : téléchargement (yt-dlp) + sous-titres → quotes + mots
             └─ CutSource : découpe ffmpeg de chaque quote + vignette

  Les vidéos sources sont supprimées après découpe (sauf `KEEP_SOURCES=true`).
  """

  require Logger

  alias Quotor.{Catalog, Media}
  alias Quotor.Accounts.Scope
  alias Quotor.Catalog.{Channel, Source}
  alias Quotor.Ingest.{Downloader, Segmenter, Subtitles}
  alias Quotor.Media.Ffmpeg
  alias Quotor.Workers

  ## Soumission

  @doc "Ajoute une vidéo YouTube au catalogue et lance son traitement."
  def submit_youtube(url, scope, extra \\ %{}) do
    attrs = Map.merge(%{url: url, submitted_by_id: Scope.user_id(scope)}, extra)

    with {:ok, source} <- Catalog.create_youtube_source(attrs) do
      Logger.info("source #{source.id} soumise (#{source.url})", source_id: source.id)
      enqueue_ingest(source)
      {:ok, source}
    end
  end

  @doc """
  Ajoute une vidéo envoyée par un admin. `video_path` (et `subtitle_path`
  optionnel, .vtt ou .srt) sont des fichiers temporaires qui seront déplacés.
  """
  def submit_upload(attrs, video_path, subtitle_path, scope) do
    placeholder = "tmp/upload-#{System.unique_integer([:positive])}"

    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{"file_path" => placeholder, "submitted_by_id" => Scope.user_id(scope)})

    with {:ok, source} <- Catalog.create_upload_source(attrs) do
      video_rel = Media.source_rel(source.id, ext(video_path, ".mp4"))
      move!(video_path, Media.prepare!(video_rel))

      sub_rel =
        if subtitle_path do
          rel = Media.source_rel(source.id, ext(subtitle_path, ".vtt"))
          move!(subtitle_path, Media.prepare!(rel))
          rel
        end

      {:ok, source} =
        Catalog.update_source(source, %{file_path: video_rel, subtitle_path: sub_rel})

      Logger.info("source #{source.id} envoyée par fichier", source_id: source.id)
      enqueue_ingest(source)
      {:ok, source}
    end
  end

  def retry(%Source{} = source) do
    {:ok, source} = Catalog.update_source(source, %{status: "pending", error: nil})
    enqueue_ingest(source)
    {:ok, source}
  end

  defp enqueue_ingest(%Source{id: id}) do
    %{source_id: id} |> Workers.IngestSource.new() |> Oban.insert()
  end

  ## Étape 1 : téléchargement + sous-titres → quotes

  @doc false
  def process(source_id) do
    case Catalog.get_source(source_id) do
      nil ->
        {:cancel, "source #{source_id} introuvable"}

      source ->
        Logger.metadata(source_id: source.id)
        {:ok, source} = Catalog.update_source(source, %{status: "downloading", error: nil})

        with {:ok, source} <- fetch(source),
             {:ok, source} <- ensure_author(source),
             {:ok, sub_path} <- subtitle_file(source),
             {:ok, parsed} <- Subtitles.parse_file(sub_path),
             segments when segments != [] <- Segmenter.segment(parsed) do
          duration = probe_duration(source)
          {:ok, count} = Catalog.replace_quotes(source, segments, duration)

          {:ok, _} =
            Catalog.update_source(source, %{
              status: "cutting",
              quotes_count: count,
              duration_s: source.duration_s || (duration && div(duration, 1000))
            })

          Logger.info("source #{source.id} : #{count} quotes (sous-titres #{parsed.kind})")
          %{source_id: source.id} |> Workers.CutSource.new() |> Oban.insert()
          :ok
        else
          [] -> fail(source, "Aucune phrase exploitable dans les sous-titres", :cancel)
          {:error, :no_subtitles} -> fail(source, "Aucun sous-titre français disponible", :cancel)
          {:error, reason} -> fail(source, inspect_reason(reason), :error)
        end
    end
  end

  defp fetch(%Source{origin: "upload"} = source), do: {:ok, source}

  defp fetch(%Source{} = source) do
    workdir = Media.tmp_dir!("source-#{source.id}")

    try do
      with {:ok, fetched} <- Downloader.impl().fetch(source.url, workdir) do
        video_rel = Media.source_rel(source.id, ext(fetched.video_path, ".mp4"))
        move!(fetched.video_path, Media.prepare!(video_rel))

        sub_rel =
          if fetched.subtitle_path do
            rel = Media.source_rel(source.id, ext(fetched.subtitle_path, ".vtt"))
            move!(fetched.subtitle_path, Media.prepare!(rel))
            rel
          end

        meta = fetched.metadata || %{}

        Catalog.update_source(source, %{
          file_path: video_rel,
          subtitle_path: sub_rel,
          title: meta[:title] || source.title,
          uploader: meta[:uploader],
          channel_url: meta[:channel_url],
          duration_s: meta[:duration_s],
          published_on: meta[:published_on]
        })
      end
    after
      File.rm_rf(workdir)
    end
  end

  # Sans auteur choisi par l'admin, la vidéo est rattachée à sa chaîne YouTube
  # (créée comme auteur de type « chaîne » si besoin).
  defp ensure_author(%Source{author_id: nil, uploader: uploader} = source)
       when is_binary(uploader) and uploader != "" do
    case Catalog.find_or_create_author(%{
           name: uploader,
           kind: "channel",
           url: source.channel_url
         }) do
      {:ok, author} -> Catalog.update_source(source, %{author_id: author.id})
      {:error, _} -> {:ok, source}
    end
  end

  defp ensure_author(source), do: {:ok, source}

  defp subtitle_file(%Source{subtitle_path: nil}), do: {:error, :no_subtitles}

  defp subtitle_file(%Source{subtitle_path: rel}) do
    path = Media.abs_path(rel)
    if File.exists?(path), do: {:ok, path}, else: {:error, :no_subtitles}
  end

  defp probe_duration(%Source{file_path: rel}) when is_binary(rel) do
    case Ffmpeg.duration_ms(Media.abs_path(rel)) do
      {:ok, ms} -> ms
      _ -> nil
    end
  end

  defp probe_duration(_), do: nil

  ## Étape 2 : découpe

  @doc false
  def cut(source_id) do
    case Catalog.get_source(source_id) do
      nil ->
        {:cancel, "source #{source_id} introuvable"}

      %Source{file_path: rel} = source ->
        Logger.metadata(source_id: source.id)
        input = rel && Media.abs_path(rel)

        if input && File.exists?(input) do
          do_cut(source, input)
        else
          # Le fichier a disparu (disque éphémère, redémarrage…) : on recommence.
          Logger.warning("source #{source.id} : vidéo absente, nouveau téléchargement")
          {:ok, _} = retry(source)
          :ok
        end
    end
  end

  defp do_cut(source, input) do
    quotes = Catalog.pending_quotes_for_source(source.id)

    failures =
      Enum.count(quotes, fn quote ->
        clip_rel = Media.clip_rel(source.id, quote.id)
        thumb_rel = Media.thumb_rel(source.id, quote.id)
        clip = Media.prepare!(clip_rel)
        duration = quote.clip_end_ms - quote.clip_start_ms

        with {:ok, _} <- Ffmpeg.cut_clip(input, quote.clip_start_ms, duration, clip),
             {:ok, _} <- Ffmpeg.thumbnail(clip, div(duration, 2), Media.prepare!(thumb_rel)) do
          Catalog.update_quote_media(quote, %{
            status: "ready",
            clip_path: clip_rel,
            thumb_path: thumb_rel
          })

          false
        else
          {:error, _msg} ->
            Catalog.update_quote_media(quote, %{status: "failed"})
            true
        end
      end)

    if failures > 0, do: Logger.warning("source #{source.id} : #{failures} découpe(s) en échec")

    {:ok, source} = Catalog.update_source(source, %{status: "ready", error: nil})

    unless Application.get_env(:quotor, :keep_sources, false) or source.origin == "upload" do
      Media.delete(source.file_path)
      Catalog.update_source(source, %{file_path: nil})
    end

    Logger.info(
      "source #{source.id} prête (#{length(quotes) - failures}/#{length(quotes)} clips)"
    )

    :ok
  end

  ## Chaînes suivies

  @doc "Récupère les dernières vidéos d'une chaîne et soumet les nouvelles."
  def sync_channel(%Channel{} = channel) do
    case Downloader.impl().list_channel(channel.url, channel.max_videos) do
      {:ok, entries} ->
        new =
          entries
          |> Enum.reject(&Catalog.get_source_by_youtube_id(&1.id))
          |> Enum.map(fn entry ->
            submit_youtube(Source.canonical_url(entry.id), nil, %{
              channel_id: channel.id,
              title: entry.title
            })
          end)
          |> Enum.count(&match?({:ok, _}, &1))

        Catalog.mark_channel_synced(channel)
        Logger.info("chaîne #{channel.name} : #{new} nouvelle(s) vidéo(s)")
        {:ok, new}

      {:error, reason} ->
        Catalog.mark_channel_synced(channel, reason)
        Logger.error("chaîne #{channel.name} : #{reason}")
        {:error, reason}
    end
  end

  ## Utilitaires

  defp fail(source, message, kind) do
    Logger.error("source #{source.id} en échec : #{message}")
    Catalog.update_source(source, %{status: "failed", error: message})
    {kind, message}
  end

  defp inspect_reason(reason) when is_binary(reason), do: reason
  defp inspect_reason(reason), do: inspect(reason)

  defp ext(path, default) do
    case Path.extname(path) do
      "" -> default
      e -> String.downcase(e)
    end
  end

  defp move!(from, to) do
    case File.rename(from, to) do
      :ok ->
        :ok

      {:error, _} ->
        File.cp!(from, to)
        File.rm(from)
        :ok
    end
  end
end
