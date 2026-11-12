defmodule Quotor.Storage do
  @moduledoc """
  Stockage des fichiers médias (clips, vignettes, montages, vidéos sources).

  Deux adaptateurs :

    * `Quotor.Storage.Local` — disque local sous `MEDIA_DIR` (développement,
      image Docker autonome) ;
    * `Quotor.Storage.S3` — stockage objet compatible S3 (Cloudflare R2, AWS
      S3, Scaleway…), indispensable dès que le site et les workers tournent sur
      des machines différentes.

  Les clés sont des chemins relatifs (`clips/12/345.mp4`). L'application
  manipule les fichiers via `Quotor.Media`, qui choisit l'adaptateur.
  """

  @type key :: String.t()

  @doc "Enregistre le fichier local `path` sous `key`. Avec `move: true`, le fichier local est supprimé."
  @callback put(path :: Path.t(), key, opts :: keyword()) :: :ok | {:error, String.t()}

  @doc "Copie l'objet `key` dans le fichier local `dest`."
  @callback get(key, dest :: Path.t()) :: :ok | {:error, :not_found | String.t()}

  @callback exists?(key) :: boolean()
  @callback delete(key) :: :ok
  @callback delete_prefix(prefix :: String.t()) :: :ok

  @doc "Liste `{clé, taille}` des objets sous un préfixe."
  @callback list(prefix :: String.t()) :: [{key, non_neg_integer()}]

  @doc "URL publique directe de l'objet, ou `nil` si les fichiers passent par l'application."
  @callback public_url(key) :: String.t() | nil

  def adapter do
    case Application.get_env(:quotor, :storage, :local) do
      :s3 -> Quotor.Storage.S3
      _ -> Quotor.Storage.Local
    end
  end

  def local?, do: adapter() == Quotor.Storage.Local
end
