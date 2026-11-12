defmodule Quotor.Catalog.Source do
  @moduledoc """
  Vidéo source d'où sont extraites les quotes.

  Cycle de vie (`status`) :
  `pending` → `downloading` → `cutting` → `ready`, ou `failed` en cas d'erreur.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending downloading cutting ready failed)

  schema "sources" do
    field :origin, :string, default: "youtube"
    field :youtube_id, :string
    field :url, :string
    field :title, :string
    field :uploader, :string
    field :duration_s, :integer
    field :published_on, :date
    field :status, :string, default: "pending"
    field :error, :string
    field :enabled, :boolean, default: true
    field :quotes_count, :integer, default: 0
    field :file_path, :string
    field :subtitle_path, :string
    field :channel_url, :string

    belongs_to :channel, Quotor.Catalog.Channel
    belongs_to :author, Quotor.Catalog.Author
    belongs_to :submitted_by, Quotor.Accounts.User
    has_many :quotes, Quotor.Catalog.Quote

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "Création d'une source YouTube à partir d'une URL."
  def youtube_changeset(source, attrs) do
    source
    |> cast(attrs, [:url, :title, :channel_id, :submitted_by_id, :author_id])
    |> validate_required([:url], message: "URL obligatoire")
    |> put_youtube_id()
    |> put_change(:origin, "youtube")
    |> unique_constraint(:youtube_id, message: "cette vidéo est déjà dans le catalogue")
  end

  @doc "Création d'une source à partir d'un fichier envoyé par un admin."
  def upload_changeset(source, attrs) do
    source
    |> cast(attrs, [
      :title,
      :uploader,
      :url,
      :channel_url,
      :file_path,
      :subtitle_path,
      :submitted_by_id,
      :author_id
    ])
    |> validate_required([:title, :file_path])
    |> put_change(:origin, "upload")
  end

  def update_changeset(source, attrs) do
    source
    |> cast(attrs, [
      :title,
      :uploader,
      :duration_s,
      :published_on,
      :status,
      :error,
      :enabled,
      :quotes_count,
      :file_path,
      :subtitle_path,
      :channel_url,
      :author_id
    ])
    |> validate_inclusion(:status, @statuses)
  end

  defp put_youtube_id(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        case youtube_id(url) do
          nil -> add_error(changeset, :url, "URL YouTube invalide")
          id -> changeset |> put_change(:youtube_id, id) |> put_change(:url, canonical_url(id))
        end
    end
  end

  @doc """
  Extrait l'identifiant d'une URL YouTube.

      iex> Quotor.Catalog.Source.youtube_id("https://youtu.be/dQw4w9WgXcQ?t=3")
      "dQw4w9WgXcQ"
  """
  def youtube_id(url) when is_binary(url) do
    patterns = [
      ~r"youtube\.com/watch\?(?:.*&)?v=([A-Za-z0-9_-]{11})",
      ~r"youtu\.be/([A-Za-z0-9_-]{11})",
      ~r"youtube\.com/(?:shorts|embed|live)/([A-Za-z0-9_-]{11})",
      ~r"^([A-Za-z0-9_-]{11})$"
    ]

    Enum.find_value(patterns, fn re ->
      case Regex.run(re, String.trim(url)) do
        [_, id] -> id
        _ -> nil
      end
    end)
  end

  def youtube_id(_), do: nil

  def canonical_url(id), do: "https://www.youtube.com/watch?v=#{id}"

  @doc "Lien vers l'original à un instant donné (attribution)."
  def original_url(%__MODULE__{youtube_id: id}, start_ms) when is_binary(id) do
    "https://www.youtube.com/watch?v=#{id}&t=#{div(start_ms, 1000)}s"
  end

  def original_url(%__MODULE__{url: url}, _), do: url
end
