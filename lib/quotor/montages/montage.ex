defmodule Quotor.Montages.Montage do
  @moduledoc "Montage vidéo (mode avancé), mis en cache par empreinte de ses segments."
  use Ecto.Schema

  schema "montages" do
    field :key, :string
    field :query, :string
    field :segments, {:array, :map}, default: []
    field :missing, {:array, :string}, default: []
    field :file_path, :string
    field :status, :string, default: "pending"
    field :error, :string

    belongs_to :user, Quotor.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
