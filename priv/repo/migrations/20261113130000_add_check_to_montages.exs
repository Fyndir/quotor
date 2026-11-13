defmodule Quotor.Repo.Migrations.AddCheckToMontages do
  use Ecto.Migration

  def change do
    alter table(:montages) do
      # contrôle à l'écoute (transcription vocale) avant livraison
      add :asr_score, :float
      add :doubtful, {:array, :string}, null: false, default: []
      # empreinte du plan avant contrôle : un plan déjà contrôlé est servi tel quel
      add :plan_key, :string
    end

    create index(:montages, [:plan_key])
  end
end
