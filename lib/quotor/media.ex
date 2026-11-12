defmodule Quotor.Media do
  @moduledoc """
  Fichiers médias de Quotor : clips, vignettes, montages et vidéos sources.

  Les fichiers sont rangés dans le stockage configuré (`Quotor.Storage` :
  disque local ou S3/R2) sous des **clés relatives** (`clips/12/345.mp4`),
  qui sont ce qui est enregistré en base.

  `MEDIA_DIR` sert de racine au stockage local et, dans tous les cas, d'espace
  de travail : dossiers temporaires (`tmp/`) et cache des fichiers
  téléchargés depuis le stockage objet (`cache/`).
  """

  alias Quotor.Storage

  @doc "Racine locale (`MEDIA_DIR`)."
  def root do
    :quotor
    |> Application.get_env(:media_dir, "priv/media")
    |> Path.expand()
  end

  ## URLs

  @doc """
  URL d'un fichier : URL publique du bucket si elle est configurée, sinon
  `/media/<clé>` (servi ou relayé par `QuotorWeb.MediaController`).
  """
  def url(nil), do: nil

  def url(key) when is_binary(key) do
    Storage.adapter().public_url(key) || "/media/" <> key
  end

  ## Stockage

  @doc """
  Range le fichier local `path` sous `key` dans le stockage. Par défaut le
  fichier local est déplacé (`move: false` pour le conserver).
  """
  def store(path, key, opts \\ []) do
    {cache?, opts} = Keyword.pop(opts, :cache, false)

    if cache? and not Storage.local?() do
      # envoi au stockage, puis le fichier local devient la copie en cache
      with :ok <- Storage.adapter().put(path, key, move: false) do
        dest = cache_path(key)
        File.mkdir_p!(Path.dirname(dest))
        File.rename(path, dest)
        :ok
      end
    else
      Storage.adapter().put(path, key, Keyword.put_new(opts, :move, true))
    end
  end

  @doc """
  Chemin local d'un fichier du stockage, en le téléchargeant si besoin (cache
  local `cache/` en mode S3). Renvoie `{:ok, path}` ou `{:error, raison}`.
  """
  def fetch(nil), do: {:error, :not_found}

  def fetch(key) do
    if Storage.local?() do
      path = Storage.Local.path(key)
      if File.regular?(path), do: {:ok, path}, else: {:error, :not_found}
    else
      path = cache_path(key)

      if File.regular?(path) do
        {:ok, path}
      else
        with :ok <- Storage.adapter().get(key, path), do: {:ok, path}
      end
    end
  end

  @doc "Supprime la copie en cache local d'un fichier (mode S3)."
  def evict(nil), do: :ok

  def evict(key) do
    unless Storage.local?(), do: File.rm(cache_path(key))
    :ok
  end

  def exists?(nil), do: false
  def exists?(key), do: Storage.adapter().exists?(key)

  def delete(nil), do: :ok

  def delete(key) do
    evict(key)
    Storage.adapter().delete(key)
  end

  @doc "Supprime tous les fichiers sous un préfixe (ex. `clips/12/`)."
  def delete_prefix(prefix) do
    prefix = String.trim_trailing(prefix, "/") <> "/"
    unless Storage.local?(), do: File.rm_rf(cache_path(prefix))
    Storage.adapter().delete_prefix(prefix)
  end

  defp cache_path(key), do: Path.join([root(), "cache", key])

  ## Espace de travail local

  @doc "Dossier de travail temporaire (local, jamais dans le stockage objet)."
  def tmp_dir!(name) do
    dir = Path.join([root(), "tmp", name])
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Résout des segments de chemin venant d'une requête en un chemin local
  (stockage local uniquement), en refusant toute sortie de la racine.
  """
  def resolve(segments) when is_list(segments) do
    if Enum.any?(segments, &(&1 in ["", ".", ".."] or String.contains?(&1, ["\\", "\0", ":"]))) do
      :error
    else
      root = root()
      path = Path.expand(Path.join([root | segments]))

      if String.starts_with?(path, root <> "/") and File.regular?(path),
        do: {:ok, path},
        else: :error
    end
  end

  ## Clés

  def clip_rel(source_id, quote_id), do: "clips/#{source_id}/#{quote_id}.mp4"
  def thumb_rel(source_id, quote_id), do: "thumbs/#{source_id}/#{quote_id}.jpg"
  def montage_rel(key), do: "montages/#{String.slice(key, 0, 2)}/#{key}.mp4"
  def source_rel(source_id, ext), do: "sources/#{source_id}#{ext}"

  ## Supervision

  @doc "Taille totale (octets) par type de fichier, pour la supervision."
  def usage do
    adapter = Storage.adapter()

    ~w(clips thumbs montages sources)
    |> Map.new(fn dir ->
      {dir, dir |> Kernel.<>("/") |> adapter.list() |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
    end)
  end
end
