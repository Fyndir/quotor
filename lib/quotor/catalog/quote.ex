defmodule Quotor.Catalog.Quote do
  @moduledoc """
  Un extrait vidéo avec son (« quote »).

  `start_ms`/`end_ms` sont les bornes de la phrase dans la vidéo source,
  `clip_start_ms`/`clip_end_ms` celles du fichier découpé (avec une petite
  marge). `norm` est le texte normalisé utilisé pour la recherche.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "quotes" do
    field :text, :string
    field :norm, :string
    field :start_ms, :integer
    field :end_ms, :integer
    field :clip_start_ms, :integer
    field :clip_end_ms, :integer
    field :clip_path, :string
    field :thumb_path, :string
    field :status, :string, default: "pending"
    field :enabled, :boolean, default: true
    field :views_count, :integer, default: 0

    belongs_to :source, Quotor.Catalog.Source
    has_many :words, Quotor.Catalog.QuoteWord, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc "Modification par un admin (correction du texte, activation)."
  def changeset(quote, attrs) do
    quote
    |> cast(attrs, [:text, :enabled])
    |> validate_required([:text])
    |> put_norm()
  end

  def media_changeset(quote, attrs) do
    cast(quote, attrs, [:clip_path, :thumb_path, :status])
  end

  defp put_norm(changeset) do
    case get_change(changeset, :text) do
      nil -> changeset
      text -> put_change(changeset, :norm, Quotor.Text.normalize(text))
    end
  end

  def duration_ms(%__MODULE__{clip_start_ms: s, clip_end_ms: e}), do: e - s
end
