defmodule Quotor.Catalog.Author do
  @moduledoc """
  Auteur d'une quote : la **personne** qui parle (ex. un vidéaste, un
  personnage) ou, à défaut, la **chaîne** YouTube qui a publié la vidéo.

  Une vidéo source a un auteur par défaut ; une quote peut avoir son propre
  auteur, prioritaire (cf. `Quotor.Catalog.author_of/1`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(person channel)

  schema "authors" do
    field :name, :string
    field :slug, :string
    field :kind, :string, default: "person"
    field :url, :string
    field :description, :string

    has_many :quotes, Quotor.Catalog.Quote
    has_many :sources, Quotor.Catalog.Source

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def kind_label("person"), do: "Personne"
  def kind_label("channel"), do: "Chaîne"
  def kind_label(_), do: "Auteur"

  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name, :kind, :url, :description])
    |> validate_required([:name], message: "obligatoire")
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:kind, @kinds)
    |> validate_format(:url, ~r{^https?://}, message: "doit commencer par http(s)://")
    |> put_slug()
    |> unique_constraint(:slug, message: "un auteur porte déjà ce nom")
  end

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, slugify(name))
    end
  end

  @doc """
      iex> Quotor.Catalog.Author.slugify("Joueur Du Grenier !")
      "joueur-du-grenier"
  """
  def slugify(name) do
    case name |> Quotor.Text.normalize() |> String.replace(" ", "-") do
      "" -> "auteur"
      slug -> String.slice(slug, 0, 80)
    end
  end
end
