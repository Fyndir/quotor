defmodule Quotor.CatalogFixtures do
  @moduledoc "Données de test pour le catalogue (sans passer par ffmpeg)."

  alias Quotor.{Catalog, Repo}
  alias Quotor.Catalog.{Quote, Source}
  alias Quotor.Ingest.{Segmenter, Subtitles}

  import Ecto.Query

  def unique_youtube_id do
    "t" <>
      (System.unique_integer([:positive]) |> Integer.to_string() |> String.pad_leading(10, "0"))
  end

  def source_fixture(attrs \\ %{}) do
    id = unique_youtube_id()

    %Source{
      origin: "youtube",
      youtube_id: id,
      url: Source.canonical_url(id),
      title: "Source de test",
      uploader: "Vidéaste",
      status: "ready"
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  @doc """
  Crée une quote prête par phrase (une phrase = une cue de 2 s, séparées
  d'une seconde). Renvoie les quotes dans l'ordre.
  """
  def quotes_fixture(%Source{} = source, sentences) do
    srt =
      sentences
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {text, i} ->
        start = i * 3000
        "#{i + 1}\n#{ts(start)} --> #{ts(start + 2000)}\n#{text}\n"
      end)

    segments = srt |> Subtitles.parse() |> Segmenter.segment()
    {:ok, _} = Catalog.replace_quotes(source, segments)

    Repo.update_all(
      from(q in Quote, where: q.source_id == ^source.id),
      set: [status: "ready"]
    )

    quotes = Catalog.list_quotes_for_source(source.id)

    Enum.map(quotes, fn q ->
      {:ok, q} =
        Catalog.update_quote_media(q, %{
          clip_path: "clips/#{source.id}/#{q.id}.mp4",
          thumb_path: "thumbs/#{source.id}/#{q.id}.jpg"
        })

      q
    end)
  end

  defp ts(ms) do
    h = div(ms, 3_600_000)
    m = div(rem(ms, 3_600_000), 60_000)
    s = div(rem(ms, 60_000), 1000)
    r = rem(ms, 1000)
    :io_lib.format("~2..0B:~2..0B:~2..0B,~3..0B", [h, m, s, r]) |> to_string()
  end
end
