defmodule Quotor.Repo.Migrations.CreateAuthors do
  use Ecto.Migration

  def change do
    # Auteurs des quotes : la personne qui parle, ou la chaîne YouTube à défaut
    create table(:authors) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :kind, :string, null: false, default: "person"
      add :url, :string
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:authors, [:slug])

    alter table(:sources) do
      # auteur par défaut de toutes les quotes de la vidéo
      add :author_id, references(:authors, on_delete: :nilify_all)
      # lien vers la chaîne YouTube d'origine
      add :channel_url, :string
    end

    alter table(:quotes) do
      # auteur propre à une quote (prioritaire sur celui de la vidéo)
      add :author_id, references(:authors, on_delete: :nilify_all)
    end

    create index(:sources, [:author_id])
    create index(:quotes, [:author_id])
  end
end
