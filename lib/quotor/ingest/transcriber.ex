defmodule Quotor.Ingest.Transcriber do
  @moduledoc """
  Reconnaissance vocale : transforme la piste audio d'une vidéo en mots
  horodatés. L'implémentation par défaut est `Quotor.Ingest.WhisperCpp` ; les
  tests utilisent une transcription factice.

  La transcription sert à vérifier et recaler les quotes tirées des
  sous-titres (`Quotor.Ingest.Alignment`), et à créer les quotes d'une vidéo
  qui n'a pas de sous-titres.

  Configuration (`config :quotor, :transcription`, cf. `config/runtime.exs`) :
  `enabled` (`:auto` : actif si whisper.cpp est installé, `true`, `false`),
  `min_score` (fiabilité minimale d'un clip affiné pour être publié, cf.
  `Quotor.Ingest.Refine`).
  """

  @type word :: %{
          text: String.t(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer(),
          prob: float()
        }

  @doc """
  Transcrit le média `path`. `workdir` est un dossier temporaire utilisable.
  Renvoie les mots dans l'ordre chronologique.
  """
  @callback transcribe(path :: String.t(), workdir :: String.t()) ::
              {:ok, [word()]} | {:error, String.t()}

  @doc """
  Transcrit plusieurs médias courts (clips découpés, pour l'affinage) en un
  seul passage. Renvoie un résultat par fichier, dans l'ordre.
  """
  @callback transcribe_many(paths :: [String.t()], workdir :: String.t()) ::
              {:ok, [{:ok, [word()]} | {:error, String.t()}]} | {:error, String.t()}

  @doc "Le moteur est-il installé et prêt à l'emploi ?"
  @callback available?() :: boolean()

  @doc "Description courte du moteur (supervision)."
  @callback label() :: String.t()

  def impl, do: Application.get_env(:quotor, :transcriber, Quotor.Ingest.WhisperCpp)

  defp settings, do: Application.get_env(:quotor, :transcription, [])

  @doc "La transcription est-elle active sur ce nœud ?"
  def enabled? do
    case Keyword.get(settings(), :enabled, :auto) do
      true -> true
      false -> false
      :auto -> impl().available?()
    end
  end

  @doc "Fiabilité minimale (0..1) d'un clip affiné pour être publié."
  def min_score, do: Keyword.get(settings(), :min_score, 0.75)

  @doc "Transcrit `path` si la transcription est active : `{:ok, mots}`, `{:error, _}` ou `:disabled`."
  def run(path, workdir) do
    if enabled?(), do: impl().transcribe(path, workdir), else: :disabled
  end
end
