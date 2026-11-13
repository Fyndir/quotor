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

    # vues de la page du montage, et présence dans « Découvrir »
    field :views_count, :integer, default: 0
    field :listed, :boolean, default: true
    # contrôle à l'écoute : part des mots de la phrase entendus (nil = non contrôlé)
    # et mots restés douteux
    field :asr_score, :float
    field :doubtful, {:array, :string}, default: []
    field :plan_key, :string

    belongs_to :user, Quotor.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
