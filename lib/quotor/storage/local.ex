defmodule Quotor.Storage.Local do
  @moduledoc "Stockage sur le disque local, sous `MEDIA_DIR`."
  @behaviour Quotor.Storage

  def root, do: Quotor.Media.root()

  def path(key), do: Path.join(root(), key)

  @impl true
  def put(src, key, opts \\ []) do
    dest = path(key)

    cond do
      Path.expand(src) == Path.expand(dest) ->
        :ok

      true ->
        File.mkdir_p!(Path.dirname(dest))

        if Keyword.get(opts, :move, false) do
          case File.rename(src, dest) do
            :ok -> :ok
            {:error, _} -> copy_then_remove(src, dest)
          end
        else
          File.cp!(src, dest)
          :ok
        end
    end
  end

  defp copy_then_remove(src, dest) do
    File.cp!(src, dest)
    File.rm(src)
    :ok
  end

  @impl true
  def get(key, dest) do
    src = path(key)

    cond do
      not File.regular?(src) -> {:error, :not_found}
      Path.expand(src) == Path.expand(dest) -> :ok
      true -> File.mkdir_p!(Path.dirname(dest)) && File.cp!(src, dest) && :ok
    end
  end

  @impl true
  def exists?(key), do: File.regular?(path(key))

  @impl true
  def delete(key) do
    _ = File.rm(path(key))
    :ok
  end

  @impl true
  def delete_prefix(prefix) do
    prefix = String.trim_trailing(prefix, "/")
    _ = File.rm_rf(path(prefix))
    :ok
  end

  @impl true
  def list(prefix) do
    base = path(String.trim_trailing(prefix, "/"))

    if File.dir?(base) do
      base
      |> Path.join("**")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn file -> {Path.relative_to(file, root()), File.stat!(file).size} end)
    else
      []
    end
  end

  @impl true
  def public_url(_key), do: nil
end
