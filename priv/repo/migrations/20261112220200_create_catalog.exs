defmodule Quotor.Repo.Migrations.CreateCatalog do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", ""

    # Chaînes YouTube suivies pour l'alimentation automatique
    create table(:channels) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :enabled, :boolean, null: false, default: false
      add :max_videos, :integer, null: false, default: 10
      add :last_synced_at, :utc_datetime
      add :last_error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:url])

    # Vidéos sources (YouTube ou fichier envoyé par un admin)
    create table(:sources) do
      add :channel_id, references(:channels, on_delete: :nilify_all)
      add :submitted_by_id, references(:users, on_delete: :nilify_all)
      add :origin, :string, null: false, default: "youtube"
      add :youtube_id, :string
      add :url, :string
      add :title, :string
      add :uploader, :string
      add :duration_s, :integer
      add :published_on, :date
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :enabled, :boolean, null: false, default: true
      add :quotes_count, :integer, null: false, default: 0
      add :file_path, :string
      add :subtitle_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:youtube_id], where: "youtube_id IS NOT NULL")
    create index(:sources, [:status])
    create index(:sources, [:channel_id])

    # Extraits ("quotes")
    create table(:quotes) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :text, :text, null: false
      add :norm, :text, null: false
      add :start_ms, :integer, null: false
      add :end_ms, :integer, null: false
      add :clip_start_ms, :integer, null: false
      add :clip_end_ms, :integer, null: false
      add :clip_path, :string
      add :thumb_path, :string
      add :status, :string, null: false, default: "pending"
      add :enabled, :boolean, null: false, default: true
      add :views_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    execute(
      """
      ALTER TABLE quotes
        ADD COLUMN tsv tsvector GENERATED ALWAYS AS (to_tsvector('simple', norm)) STORED
      """,
      "ALTER TABLE quotes DROP COLUMN tsv"
    )

    create index(:quotes, [:source_id])
    create index(:quotes, [:status, :enabled])
    create index(:quotes, [:tsv], using: :gin)

    execute(
      "CREATE INDEX quotes_norm_trgm_index ON quotes USING gin (norm gin_trgm_ops)",
      "DROP INDEX quotes_norm_trgm_index"
    )

    # Mots horodatés de chaque extrait (pour les montages)
    create table(:quote_words) do
      add :quote_id, references(:quotes, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :word, :string, null: false
      add :start_ms, :integer, null: false
      add :end_ms, :integer, null: false
    end

    create unique_index(:quote_words, [:quote_id, :position])

    create table(:favorites) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :quote_id, references(:quotes, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:favorites, [:user_id, :quote_id])

    # Montages (mode avancé) mis en cache par empreinte
    create table(:montages) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :key, :string, null: false
      add :query, :text, null: false
      add :segments, {:array, :map}, null: false, default: []
      add :missing, {:array, :string}, null: false, default: []
      add :file_path, :string
      add :status, :string, null: false, default: "pending"
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:montages, [:key])
    create index(:montages, [:user_id])

    # Signalements / demandes de retrait (droit d'auteur, etc.)
    create table(:reports) do
      add :quote_id, references(:quotes, on_delete: :nilify_all)
      add :source_id, references(:sources, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :message, :text, null: false
      add :contact_email, :string
      add :contact_name, :string
      add :status, :string, null: false, default: "open"
      add :resolution, :text

      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:status])
  end
end
