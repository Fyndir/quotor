defmodule Quotor.Media do
  @moduledoc """
  Stockage des fichiers médias (clips, vignettes, montages, vidéos sources)
  sur disque local, sous `MEDIA_DIR`.

  Les chemins stockés en base sont **relatifs** à la racine (ex.
  `clips/12/345.mp4`) et servis par `QuotorWeb.MediaController` sous `/media/…`.
  """

  @doc "Racine absolue du stockage."
  def root do
    :quotor
    |> Application.get_env(:media_dir, "priv/media")
    |> Path.expand()
  end

  @doc "Chemin absolu d'un fichier relatif."
  def abs_path(rel) when is_binary(rel), do: Path.join(root(), rel)

  @doc "URL publique d'un fichier relatif."
  def url(nil), do: nil
  def url(rel) when is_binary(rel), do: "/media/" <> rel

  @doc """
  Résout des segments de chemin venant d'une requête en un chemin absolu,
  en refusant toute sortie de la racine (`..`, chemins absolus…).
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

  @doc "Crée le dossier parent d'un fichier relatif et renvoie son chemin absolu."
  def prepare!(rel) do
    path = abs_path(rel)
    File.mkdir_p!(Path.dirname(path))
    path
  end

  @doc "Dossier de travail temporaire."
  def tmp_dir!(name) do
    dir = abs_path(Path.join("tmp", name))
    File.mkdir_p!(dir)
    dir
  end

  def delete(nil), do: :ok

  def delete(rel) when is_binary(rel) do
    _ = File.rm(abs_path(rel))
    :ok
  end

  def delete_dir(rel) when is_binary(rel) do
    _ = File.rm_rf(abs_path(rel))
    :ok
  end

  def clip_rel(source_id, quote_id), do: "clips/#{source_id}/#{quote_id}.mp4"
  def thumb_rel(source_id, quote_id), do: "thumbs/#{source_id}/#{quote_id}.jpg"
  def montage_rel(key), do: "montages/#{String.slice(key, 0, 2)}/#{key}.mp4"
  def source_rel(source_id, ext), do: "sources/#{source_id}#{ext}"

  @doc "Taille totale (octets) par sous-dossier, pour la supervision."
  def usage do
    root = root()

    ~w(clips thumbs montages sources tmp)
    |> Map.new(fn dir -> {dir, dir_size(Path.join(root, dir))} end)
  end

  defp dir_size(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.reduce(entries, 0, fn entry, acc ->
          full = Path.join(path, entry)

          case File.lstat(full) do
            {:ok, %File.Stat{type: :directory}} -> acc + dir_size(full)
            {:ok, %File.Stat{type: :regular, size: size}} -> acc + size
            _ -> acc
          end
        end)

      _ ->
        0
    end
  end
end
