defmodule Quotor.Repo.Migrations.AddDiscoverToMontages do
  use Ecto.Migration

  def change do
    alter table(:montages) do
      add :views_count, :integer, null: false, default: 0
      # les montages des utilisateurs connectés sont visibles dans « Découvrir »,
      # sauf si leur auteur les en retire
      add :listed, :boolean, null: false, default: true
    end

    create index(:montages, [:user_id, :listed, :status])
  end
end
