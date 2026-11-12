defmodule Quotor.Catalog.Channel do
  @moduledoc "Chaîne (ou playlist) YouTube suivie pour l'alimentation automatique."
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    field :url, :string
    field :enabled, :boolean, default: false
    field :max_videos, :integer, default: 10
    field :last_synced_at, :utc_datetime
    field :last_error, :string

    has_many :sources, Quotor.Catalog.Source

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :url, :enabled, :max_videos])
    |> validate_required([:name, :url])
    |> validate_format(:url, ~r{^https://(www\.|m\.)?youtube\.com/},
      message: "doit être une URL youtube.com"
    )
    |> validate_number(:max_videos, greater_than: 0, less_than_or_equal_to: 200)
    |> unique_constraint(:url)
  end

  def sync_changeset(channel, attrs) do
    cast(channel, attrs, [:last_synced_at, :last_error])
  end
end
