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
    # accord texte / parole (0..1, transcription whisper.cpp) ; nil = non vérifié
    field :asr_score, :float

    belongs_to :source, Quotor.Catalog.Source
    belongs_to :author, Quotor.Catalog.Author
    has_many :words, Quotor.Catalog.QuoteWord, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc "Modification par un admin (correction du texte, activation)."
  def changeset(quote, attrs) do
    quote
    |> cast(attrs, [:text, :enabled, :author_id])
    |> validate_required([:text])
    |> put_norm()
  end

  def media_changeset(quote, attrs) do
    cast(quote, attrs, [
      :clip_path,
      :thumb_path,
      :status,
      :asr_score,
      :clip_start_ms,
      :clip_end_ms
    ])
  end

  defp put_norm(changeset) do
    case get_change(changeset, :text) do
      nil -> changeset
      text -> put_change(changeset, :norm, Quotor.Text.normalize(text))
    end
  end

  @review_threshold 0.8

  @doc "Score en dessous duquel une quote est « à vérifier »."
  def review_threshold, do: @review_threshold

  @doc "Quote à vérifier (texte et parole divergent) ?"
  def needs_review?(%__MODULE__{status: "review"}), do: true

  def needs_review?(%__MODULE__{asr_score: score}) when is_float(score),
    do: score < @review_threshold

  def needs_review?(_), do: false

  def duration_ms(%__MODULE__{clip_start_ms: s, clip_end_ms: e}), do: e - s
end
