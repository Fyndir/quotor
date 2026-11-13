defmodule Quotor.FakeTranscriber do
  @moduledoc """
  Transcription factice pour les tests.

    * `transcribe/2` (vidéo entière) renvoie les mots placés dans
      `Application.get_env(:quotor, :fake_transcript)` (liste de
      `{texte, début_ms, fin_ms}`), ou l'erreur `{:error, raison}` qui s'y trouve ;
    * `transcribe_many/2` (affinage des clips) « entend » par défaut exactement
      le texte de la quote, réparti dans le clip avec 200 ms de marge. Une
      fonction `fn quote, clip_duration_ms -> mots | {:error, raison} end` dans
      `:fake_clip_transcript` permet de simuler d'autres cas.
  """
  @behaviour Quotor.Ingest.Transcriber

  alias Quotor.Catalog.Quote
  alias Quotor.Media.Ffmpeg

  @impl true
  def available?, do: true

  @impl true
  def label, do: "transcription factice"

  @impl true
  def transcribe(path, _workdir) do
    true = File.regular?(path)

    case Application.get_env(:quotor, :fake_transcript, []) do
      {:error, reason} -> {:error, reason}
      words -> {:ok, to_words(words)}
    end
  end

  @impl true
  def transcribe_many(paths, _workdir) do
    {:ok, Enum.map(paths, &clip_result/1)}
  end

  defp clip_result(path) do
    [id | _] = path |> Path.basename() |> String.split("-")
    quote = Quotor.Repo.get!(Quote, String.to_integer(id))
    {:ok, duration} = Ffmpeg.duration_ms(path)

    case Application.get_env(:quotor, :fake_clip_transcript, &echo/2).(quote, duration) do
      {:error, reason} -> {:error, reason}
      words -> {:ok, to_words(words)}
    end
  end

  @doc "Le texte de la quote, réparti dans le clip avec 200 ms de marge."
  def echo(quote, duration) do
    tokens = String.split(quote.norm, " ", trim: true)
    step = div(max(duration - 400, 100), max(length(tokens), 1))

    tokens
    |> Enum.with_index()
    |> Enum.map(fn {t, i} -> {t, 200 + i * step, 200 + (i + 1) * step} end)
  end

  defp to_words(words),
    do: for({text, s, e} <- words, do: %{text: text, start_ms: s, end_ms: e, prob: 0.9})
end
