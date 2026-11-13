defmodule Quotor.Ingest do
  @moduledoc """
  Alimentation du catalogue, entièrement en arrière-plan (Oban) :

      soumission (admin / chaîne suivie)
        └─ IngestSource : téléchargement (yt-dlp) + sous-titres → quotes + mots
             transcription vocale (whisper.cpp) : vérifie et recale les quotes,
             ou les crée seule si la vidéo n'a pas de sous-titres
             └─ CutSource : découpe ffmpeg de chaque quote + vignette, puis affinage :
                  chaque clip est réécouté, élargi s'il manque un mot au bord, et
                  publié seulement s'il est fiable (sinon « à vérifier »)

  Les vidéos sources sont supprimées après découpe (sauf `KEEP_SOURCES=true`).
  """

  require Logger

  alias Quotor.{Catalog, Media}
  alias Quotor.Accounts.Scope
  alias Quotor.Catalog.{Channel, Source}
  alias Quotor.Ingest.{Alignment, Downloader, Refine, Segmenter, Subtitles, Transcriber}
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
             {:ok, parsed} <- read_subtitles(source),
             {asr, asr_status} = transcribe(source),
             {:ok, segments, origin} <- build_segments(parsed, asr),
             segments when segments != [] <- segments do
          duration = probe_duration(source)
          {:ok, count} = Catalog.replace_quotes(source, segments, duration)

          {:ok, _} =
            Catalog.update_source(source, %{
              status: "cutting",
              quotes_count: count,
              text_origin: origin,
              asr_status: asr_status,
              duration_s: source.duration_s || (duration && div(duration, 1000))
            })

          to_review = Enum.count(segments, &((&1[:asr_score] || 1.0) < 0.8))

          Logger.info(
            "source #{source.id} : #{count} quotes (#{describe_origin(origin, parsed)}, transcription #{asr_status}, #{to_review} à vérifier)"
          )

          %{source_id: source.id} |> Workers.CutSource.new() |> Oban.insert()
          :ok
        else
          [] ->
            fail(source, "Aucune phrase exploitable", :cancel)

          {:error, :no_text} ->
            fail(
              source,
              "Aucun sous-titre français disponible, et transcription vocale désactivée",
              :cancel
            )

          {:error, reason} ->
            fail(source, inspect_reason(reason), :error)
        end
    end
  end

  # Sous-titres analysés, ou `nil` si la vidéo n'en a pas.
  defp read_subtitles(source) do
    case subtitle_file(source) do
      {:ok, sub_path} ->
        with {:ok, parsed} <- Subtitles.parse_file(sub_path) do
          Media.evict(source.subtitle_path)
          {:ok, parsed}
        end

      {:error, :no_subtitles} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Transcription vocale de la vidéo (whisper.cpp) : `{mots | erreur, statut}`.
  defp transcribe(%Source{file_path: rel} = source) when is_binary(rel) do
    workdir = Media.tmp_dir!("asr-#{source.id}-#{System.unique_integer([:positive])}")

    try do
      with {:ok, path} <- Media.fetch(rel),
           {:ok, words} <- Transcriber.run(path, workdir) do
        {{:ok, words}, "done"}
      else
        :disabled ->
          {:disabled, "disabled"}

        {:error, reason} ->
          Logger.warning(
            "source #{source.id} : transcription en échec : #{inspect_reason(reason)}"
          )

          {{:error, inspect_reason(reason)}, "failed"}
      end
    after
      File.rm_rf(workdir)
    end
  end

  defp transcribe(_source), do: {:disabled, "disabled"}

  # Sous-titres + transcription : les quotes viennent des sous-titres,
  # vérifiées et recalées sur la parole. Sous-titres seuls : comme avant.
  # Transcription seule : les quotes viennent de la transcription.
  defp build_segments(parsed, asr) when not is_nil(parsed) do
    segments = Segmenter.segment(parsed)

    case asr do
      {:ok, words} -> {:ok, Alignment.align(segments, words), "subtitles"}
      _ -> {:ok, segments, "subtitles"}
    end
  end

  defp build_segments(nil, {:ok, words}),
    do: {:ok, Alignment.from_transcript(words), "transcription"}

  # sans sous-titres, une transcription en échec est réessayée (modèle à télécharger…)
  defp build_segments(nil, {:error, reason}), do: {:error, reason}
  defp build_segments(nil, :disabled), do: {:error, :no_text}

  defp describe_origin("transcription", _), do: "transcription vocale"
  defp describe_origin(_, parsed), do: "sous-titres #{parsed.kind}"

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

  # Découpe les clips dans un dossier de travail, puis (transcription active)
  # les affine avant de les publier : cf. `Quotor.Ingest.Refine`.
  defp do_cut(source, input) do
    quotes = Catalog.pending_quotes_for_source(source.id)
    workdir = Media.tmp_dir!("cut-#{source.id}-#{System.unique_integer([:positive])}")

    try do
      {items, failures} =
        Enum.reduce(quotes, {[], 0}, fn quote, {items, failures} ->
          case cut_local(input, quote, quote.clip_start_ms, quote.clip_end_ms, workdir) do
            {:ok, item} ->
              {[item | items], failures}

            {:error, msg} ->
              Logger.warning("quote #{quote.id} : #{inspect_reason(msg)}")
              Catalog.update_quote_media(quote, %{status: "failed"})
              {items, failures + 1}
          end
        end)

      with {:ok, verdicts} <- refine(source, input, Enum.reverse(items), workdir) do
        published = Enum.count(verdicts, fn {item, verdict} -> publish(source, item, verdict) end)
        finish(source, length(quotes), failures, published)
      end
    after
      File.rm_rf(workdir)
    end
  end

  # Sans transcription : les clips sont publiés tels quels, comme avant.
  defp refine(source, input, items, workdir) do
    if Transcriber.enabled?() and items != [] do
      {:ok, _} = Catalog.update_source(source, %{status: "refining"})
      neighbours = Catalog.list_quotes_for_source(source.id)

      recut = fn item, start_ms, end_ms ->
        cut_local(input, item.quote, start_ms, end_ms, workdir)
      end

      case Refine.run(items, neighbours, workdir, recut) do
        {:ok, verdicts} ->
          {:ok, verdicts}

        {:error, reason} ->
          {:error, "affinage impossible : #{inspect_reason(reason)}"}
      end
    else
      {:ok, Enum.map(items, &{&1, %{status: "ready", asr_score: &1.quote.asr_score}})}
    end
  end

  # Range le clip et la vignette dans le stockage et met la quote à jour.
  # Renvoie `true` si elle est publiée.
  defp publish(source, item, verdict) do
    clip_rel = Media.clip_rel(source.id, item.quote.id)
    thumb_rel = Media.thumb_rel(source.id, item.quote.id)

    with :ok <- Media.store(item.clip, clip_rel),
         :ok <- Media.store(item.thumb, thumb_rel) do
      {:ok, _} =
        Catalog.update_quote_media(item.quote, %{
          status: verdict.status,
          asr_score: verdict.asr_score,
          clip_path: clip_rel,
          thumb_path: thumb_rel,
          clip_start_ms: item.clip_start_ms,
          clip_end_ms: item.clip_end_ms
        })

      verdict.status == "ready"
    else
      {:error, msg} ->
        Logger.warning("quote #{item.quote.id} : #{inspect_reason(msg)}")
        Catalog.update_quote_media(item.quote, %{status: "failed"})
        false
    end
  end

  defp finish(source, total, failures, published) do
    if failures > 0, do: Logger.warning("source #{source.id} : #{failures} découpe(s) en échec")

    {:ok, source} = Catalog.update_source(source, %{status: "ready", error: nil})
    Media.evict(source.file_path)

    unless Application.get_env(:quotor, :keep_sources, false) or source.origin == "upload" do
      Media.delete(source.file_path)
      Catalog.update_source(source, %{file_path: nil})
    end

    to_review = total - failures - published

    Logger.info(
      "source #{source.id} prête : #{published} clip(s) publié(s), #{to_review} à vérifier, #{failures} en échec"
    )

    :ok
  end

  # Découpe `[start_ms, end_ms]` de la vidéo dans le dossier de travail (clip
  # + vignette), sans rien publier.
  defp cut_local(input, quote, start_ms, end_ms, workdir) do
    n = System.unique_integer([:positive])
    clip = Path.join(workdir, "#{quote.id}-#{n}.mp4")
    thumb = Path.join(workdir, "#{quote.id}-#{n}.jpg")
    duration = end_ms - start_ms

    with {:ok, _} <- Ffmpeg.cut_clip(input, start_ms, duration, clip),
         {:ok, _} <- Ffmpeg.thumbnail(clip, div(duration, 2), thumb) do
      {:ok,
       %{quote: quote, clip: clip, thumb: thumb, clip_start_ms: start_ms, clip_end_ms: end_ms}}
    end
  end

  ## Chaînes suivies

  @doc "Récupère les dernières vidéos d'une chaîne et soumet les nouvelles."
  def sync_channel(%Channel{} = channel) do
    case Downloader.impl().list_channel(channel.url, channel.max_videos) do
      {:ok, entries} ->
        new =
          entries
          # déjà analysée, même supprimée depuis : cf. historique des vidéos
          |> Enum.reject(&Catalog.known_video?(&1.id))
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
