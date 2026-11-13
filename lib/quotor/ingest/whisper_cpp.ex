defmodule Quotor.Ingest.WhisperCpp do
  @moduledoc """
  Transcription locale avec [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
  (programme `whisper-cli`, installé dans l'image Docker).

  1. ffmpeg extrait la piste audio (WAV mono 16 kHz) ;
  2. `whisper-cli` la transcrit, un segment par mot (`-ml 1 -sow`), avec la
     probabilité de chaque token (`-ojf`). Le détecteur de voix (VAD Silero,
     `WHISPER_VAD=true`) peut ignorer musique et silences, où Whisper a
     tendance à inventer du texte, mais il dégrade les horodatages et la
     reconnaissance sur des phrases courtes séparées de silences : il est
     désactivé par défaut ;
  3. le JSON produit est converti en mots horodatés.

  Les modèles sont téléchargés au premier usage depuis Hugging Face dans
  `models_dir` (par défaut `<MEDIA_DIR>/../models`, soit `/data/models` dans
  l'image). Réglages : `WHISPER_MODEL` (`small` par défaut ; `base` pour une
  petite machine, `medium` ou `large-v3-turbo` pour plus de précision, ou le
  chemin d'un fichier `.bin`), `WHISPER_THREADS`, `WHISPER_LANGUAGE`,
  `WHISPER_VAD`.
  """
  @behaviour Quotor.Ingest.Transcriber

  require Logger

  alias Quotor.Media
  alias Quotor.Media.Ffmpeg

  @model_url "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-~s.bin"
  @vad_model "ggml-silero-v5.1.2.bin"
  @vad_url "https://huggingface.co/ggml-org/whisper-vad/resolve/main/" <> @vad_model

  defp settings, do: Application.get_env(:quotor, :whisper, [])
  defp bin, do: Keyword.get(settings(), :path, "whisper-cli")

  @doc false
  def models_dir do
    Path.expand(settings()[:models_dir] || Path.join(Path.dirname(Media.root()), "models"))
  end

  defp model, do: Keyword.get(settings(), :model, "small")

  @impl true
  def available?, do: System.find_executable(bin()) != nil

  @impl true
  def label, do: "whisper.cpp · #{model()}"

  @impl true
  def transcribe(path, workdir) do
    audio = Path.join(workdir, "audio.wav")
    out = Path.join(workdir, "whisper")
    started = System.monotonic_time(:millisecond)

    with exe when is_binary(exe) <-
           System.find_executable(bin()) || {:error, "#{bin()} introuvable"},
         {:ok, model_path} <- ensure_model(),
         {:ok, vad_args} <- vad_args(),
         {:ok, _} <- Ffmpeg.extract_audio(path, audio),
         :ok <- run(exe, model_path, vad_args, audio, out),
         {:ok, json} <- File.read(out <> ".json"),
         {:ok, words} <- parse_json(json) do
      Logger.info(
        "transcription : #{length(words)} mots en #{div(System.monotonic_time(:millisecond) - started, 1000)} s (#{label()})"
      )

      {:ok, words}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "transcription : #{inspect(reason)}"}
    end
  end

  # Clips à vérifier par lancement de whisper-cli (le modèle n'est chargé
  # qu'une fois par lot).
  @batch 40
  # silence inséré entre deux médias mis bout à bout
  @gap_ms 700

  @doc """
  Transcrit plusieurs médias courts en **un seul fichier audio** : ils sont
  mis bout à bout, séparés de 0,7 s de silence, transcrits en une passe, puis
  les mots sont rendus à chaque média d'après leur position. whisper traite
  l'audio par fenêtres de 30 s : 4 morceaux de 1 s coûtent ainsi une fenêtre
  au lieu de quatre (de l'ordre de 3 s au lieu de 8 s sur 8 cœurs).
  """
  @impl true
  def transcribe_many(paths, workdir) do
    with exe when is_binary(exe) <-
           System.find_executable(bin()) || {:error, "#{bin()} introuvable"},
         {:ok, model_path} <- ensure_model(),
         {:ok, vad_args} <- vad_args(),
         {:ok, silence} <- silence(workdir) do
      results =
        paths
        |> Enum.with_index()
        |> Enum.chunk_every(@batch)
        |> Enum.with_index()
        |> Enum.flat_map(fn {chunk, b} ->
          transcribe_batch(chunk, b, exe, model_path, vad_args, silence, workdir)
        end)

      {:ok, results}
    end
  end

  defp silence(workdir) do
    path = Path.join(workdir, "silence.wav")
    with {:ok, _} <- Ffmpeg.silence(@gap_ms, path), do: {:ok, path}
  end

  defp transcribe_batch(chunk, b, exe, model_path, vad_args, silence, workdir) do
    audios =
      Enum.map(chunk, fn {path, i} ->
        audio = Path.join(workdir, "clip-#{i}.wav")

        with {:ok, _} <- Ffmpeg.extract_audio(path, audio),
             {:ok, ms} <- Ffmpeg.duration_ms(audio) do
          {:ok, audio, ms}
        end
      end)

    # position (ms) de chaque média dans le fichier mis bout à bout
    {placed, _} =
      Enum.map_reduce(audios, 0, fn
        {:ok, audio, ms}, at -> {{:ok, audio, at, ms}, at + ms + @gap_ms}
        error, at -> {error, at}
      end)

    files = for {:ok, audio, _, _} <- placed, f <- [audio, silence], do: f
    joined = Path.join(workdir, "batch-#{b}.wav")
    out = Path.join(workdir, "batch-#{b}")

    words =
      with true <- files != [] || :empty,
           {:ok, _} <- Ffmpeg.concat_audio(files, joined, workdir),
           :ok <- run(exe, model_path, vad_args, joined, out),
           {:ok, json} <- File.read(out <> ".json") do
        parse_json(json)
      else
        :empty -> {:ok, []}
        {:error, reason} when is_binary(reason) -> {:error, reason}
        {:error, reason} -> {:error, inspect(reason)}
      end

    Enum.map(placed, fn
      {:ok, _audio, at, ms} ->
        with {:ok, words} <- words do
          mine =
            for w <- words,
                w.start_ms >= at - 100 and w.start_ms < at + ms + div(@gap_ms, 2),
                do: %{w | start_ms: max(w.start_ms - at, 0), end_ms: max(w.end_ms - at, 0)}

          {:ok, mine}
        end

      {:error, reason} ->
        {:error, if(is_binary(reason), do: reason, else: inspect(reason))}
    end)
  end

  # `out` nil : un JSON par fichier, nommé `<fichier audio>.json`.
  defp run(exe, model_path, vad_args, audio, out) do
    inputs = audio |> List.wrap() |> Enum.flat_map(&["-f", &1])
    output = if out, do: ["-of", out], else: []

    args =
      ["-m", model_path] ++
        inputs ++
        [
          "-l",
          Keyword.get(settings(), :language, "fr"),
          "-t",
          to_string(threads()),
          # un segment par mot, avec probabilités et JSON complet
          "-ml",
          "1",
          "-sow",
          "-ojf",
          "-np"
        ] ++ output ++ vad_args

    case System.cmd(exe, args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, code} ->
        msg = output |> String.split("\n", trim: true) |> Enum.take(-3) |> Enum.join(" | ")
        {:error, "whisper-cli (code #{code}) : #{msg}"}
    end
  end

  defp threads do
    Keyword.get(settings(), :threads) || min(System.schedulers_online(), 8)
  end

  ## Modèles

  defp ensure_model do
    case model() do
      "/" <> _ = path ->
        if File.regular?(path), do: {:ok, path}, else: {:error, "modèle #{path} introuvable"}

      name ->
        if Regex.match?(~r/\A[a-z0-9.\-]+\z/, name) do
          ensure_file("ggml-#{name}.bin", :io_lib.format(@model_url, [name]) |> to_string())
        else
          {:error, "WHISPER_MODEL invalide : #{inspect(name)}"}
        end
    end
  end

  defp vad_args do
    if Keyword.get(settings(), :vad, false) do
      with {:ok, path} <- ensure_file(@vad_model, @vad_url), do: {:ok, ["--vad", "-vm", path]}
    else
      {:ok, []}
    end
  end

  # Télécharge un modèle s'il manque (une seule fois par machine : le dossier
  # des modèles est sur le volume de données).
  defp ensure_file(name, url) do
    dest = Path.join(models_dir(), name)

    if File.regular?(dest) do
      {:ok, dest}
    else
      File.mkdir_p!(models_dir())
      part = dest <> ".part"
      Logger.info("whisper.cpp : téléchargement du modèle #{name}…")

      case Req.get(url, into: File.stream!(part), retry: :transient, receive_timeout: 120_000) do
        {:ok, %Req.Response{status: 200}} ->
          File.rename!(part, dest)
          Logger.info("whisper.cpp : modèle #{name} prêt")
          {:ok, dest}

        {:ok, %Req.Response{status: status}} ->
          File.rm(part)
          {:error, "téléchargement du modèle #{name} : HTTP #{status}"}

        {:error, exception} ->
          File.rm(part)
          {:error, "téléchargement du modèle #{name} : #{Exception.message(exception)}"}
      end
    end
  end

  ## Résultat

  @doc """
  Convertit le JSON de `whisper-cli -ml 1 -sow -ojf` en mots horodatés. La
  probabilité d'un mot est la moyenne de celles de ses tokens.
  """
  def parse_json(json) do
    case Jason.decode(json) do
      {:ok, %{"transcription" => segments}} when is_list(segments) ->
        words =
          Enum.flat_map(segments, fn
            %{"offsets" => %{"from" => from, "to" => to}, "text" => text} = seg ->
              case String.trim(text) do
                "" ->
                  []

                text ->
                  [%{text: text, start_ms: from, end_ms: max(to, from), prob: word_prob(seg)}]
              end

            _ ->
              []
          end)

        {:ok, Enum.sort_by(words, & &1.start_ms)}

      {:ok, _} ->
        {:error, "JSON whisper inattendu"}

      {:error, _} ->
        {:error, "JSON whisper illisible"}
    end
  end

  defp word_prob(%{"tokens" => tokens}) when is_list(tokens) do
    probs =
      for %{"text" => t, "p" => p} <- tokens,
          not String.starts_with?(t, "[_"),
          is_number(p),
          do: p * 1.0

    if probs == [], do: 0.0, else: Enum.sum(probs) / length(probs)
  end

  defp word_prob(_), do: 0.0
end
