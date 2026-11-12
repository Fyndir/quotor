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

    # Les fichiers sont rangés dans le stockage partagé : la vidéo pourra être
    # traitée par un worker sur une autre machine que le site.
    with {:ok, source} <- Catalog.create_upload_source(attrs),
         {:ok, video_rel} <- store_source_file(source, video_path, ".mp4"),
         {:ok, sub_rel} <- store_source_file(source, subtitle_path, ".vtt") do
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
             :ok <- Media.evict(source.subtitle_path),
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
      with {:ok, fetched} <- Downloader.impl().fetch(source.url, workdir),
           # la découpe peut avoir lieu sur un autre worker : la vidéo va au stockage
           {:ok, video_rel} <-
             store_source_file(source, fetched.video_path, ".mp4", keep_local: true),
           {:ok, sub_rel} <- store_source_file(source, fetched.subtitle_path, ".vtt") do
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
    case Media.fetch(rel) do
      {:ok, path} -> {:ok, path}
      {:error, :not_found} -> {:error, :no_subtitles}
      {:error, reason} -> {:error, reason}
    end
  end

  defp probe_duration(%Source{file_path: rel}) when is_binary(rel) do
    with {:ok, path} <- Media.fetch(rel),
         {:ok, ms} <- Ffmpeg.duration_ms(path) do
      ms
    else
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

        # En mode S3, la vidéo est téléchargée depuis le stockage si ce worker
        # ne l'a pas déjà (cache local).
        case Media.fetch(rel) do
          {:ok, input} ->
            do_cut(source, input)

          {:error, :not_found} ->
            # Vidéo disparue (disque éphémère, purge…) : on recommence tout.
            Logger.warning("source #{source.id} : vidéo absente, nouveau téléchargement")
            {:ok, _} = retry(source)
            :ok

          {:error, reason} ->
            # Stockage momentanément indisponible : Oban réessaiera.
            {:error, inspect_reason(reason)}
        end
    end
  end

  defp do_cut(source, input) do
    quotes = Catalog.pending_quotes_for_source(source.id)
    workdir = Media.tmp_dir!("cut-#{source.id}-#{System.unique_integer([:positive])}")

    failures =
      try do
        Enum.count(quotes, &(cut_quote(source, input, &1, workdir) == :error))
      after
        File.rm_rf(workdir)
      end

    if failures > 0, do: Logger.warning("source #{source.id} : #{failures} découpe(s) en échec")

    {:ok, source} = Catalog.update_source(source, %{status: "ready", error: nil})
    Media.evict(source.file_path)

    unless Application.get_env(:quotor, :keep_sources, false) or source.origin == "upload" do
      Media.delete(source.file_path)
      Catalog.update_source(source, %{file_path: nil})
    end

    Logger.info(
      "source #{source.id} prête (#{length(quotes) - failures}/#{length(quotes)} clips)"
    )

    :ok
  end

  # Découpe une quote dans un dossier de travail local, puis range le clip et
  # la vignette dans le stockage.
  defp cut_quote(source, input, quote, workdir) do
    clip_rel = Media.clip_rel(source.id, quote.id)
    thumb_rel = Media.thumb_rel(source.id, quote.id)
    clip = Path.join(workdir, "#{quote.id}.mp4")
    thumb = Path.join(workdir, "#{quote.id}.jpg")
    duration = quote.clip_end_ms - quote.clip_start_ms

    with {:ok, _} <- Ffmpeg.cut_clip(input, quote.clip_start_ms, duration, clip),
         {:ok, _} <- Ffmpeg.thumbnail(clip, div(duration, 2), thumb),
         :ok <- Media.store(clip, clip_rel),
         :ok <- Media.store(thumb, thumb_rel) do
      Catalog.update_quote_media(quote, %{
        status: "ready",
        clip_path: clip_rel,
        thumb_path: thumb_rel
      })

      :ok
    else
      {:error, msg} ->
        Logger.warning("quote #{quote.id} : #{inspect_reason(msg)}")
        Catalog.update_quote_media(quote, %{status: "failed"})
        :error
    end
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

  # Range un fichier de la source (vidéo, sous-titres) dans le stockage.
  # `keep_local: true` garde une copie dans le cache local du worker (évite de
  # retélécharger la vidéo juste après pour la découper).
  defp store_source_file(source, path, default_ext, opts \\ [])

  defp store_source_file(_source, nil, _default_ext, _opts), do: {:ok, nil}

  defp store_source_file(source, path, default_ext, opts) do
    rel = Media.source_rel(source.id, ext(path, default_ext))

    case Media.store(path, rel, cache: Keyword.get(opts, :keep_local, false)) do
      :ok -> {:ok, rel}
      {:error, reason} -> {:error, reason}
    end
  end
end
