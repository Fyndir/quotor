defmodule Quotor.Repo.Migrations.CreateVideoHistory do
  use Ecto.Migration

  # Historique des vidéos YouTube analysées : conservé même quand la vidéo est
  # supprimée du catalogue, pour que la synchronisation des chaînes suivies ne
  # la réimporte pas.
  def up do
    create table(:video_history) do
      add :youtube_id, :string, null: false
      add :title, :string
      add :url, :string
      # dernier état connu : pending, ready, failed, deleted
      add :status, :string, null: false, default: "pending"
      add :analyzed_at, :utc_datetime
      add :removed_at, :utc_datetime
      add :channel_id, references(:channels, on_delete: :nilify_all)
      add :source_id, references(:sources, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:video_history, [:youtube_id])
    create index(:video_history, [:channel_id])

    # vidéos déjà présentes dans le catalogue
    execute """
    INSERT INTO video_history (youtube_id, title, url, status, analyzed_at, channel_id, source_id, inserted_at, updated_at)
    SELECT youtube_id, title, url,
           CASE WHEN status IN ('ready', 'failed') THEN status ELSE 'pending' END,
           CASE WHEN status = 'ready' THEN updated_at END,
           channel_id, id, inserted_at, updated_at
    FROM sources
    WHERE youtube_id IS NOT NULL
    ON CONFLICT DO NOTHING
    """
  end

  def down do
    drop table(:video_history)
  end
end
