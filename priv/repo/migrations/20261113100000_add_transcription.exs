defmodule Quotor.Repo.Migrations.AddTranscription do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      # d'où vient le texte des quotes : "subtitles" ou "transcription" (whisper.cpp)
      add :text_origin, :string
      # transcription vocale : nil (pas tentée), "done", "failed", "disabled"
      add :asr_status, :string
    end

    alter table(:quotes) do
      # accord entre le texte et ce qui est réellement dit (0..1) ; nil = non vérifié
      add :asr_score, :float
    end

    create index(:quotes, [:asr_score])
  end
end
