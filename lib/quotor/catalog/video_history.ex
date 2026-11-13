defmodule Quotor.Catalog.VideoHistory do
  @moduledoc """
  Une vidéo YouTube déjà soumise au catalogue (à la main ou par une chaîne
  suivie). L'entrée est conservée quand la vidéo est supprimée (`status:
  "deleted"`) : la synchronisation des chaînes ne la réimporte pas, sauf si
  l'admin l'« oublie ».
  """
  use Ecto.Schema

  schema "video_history" do
    field :youtube_id, :string
    field :title, :string
    field :url, :string
    field :status, :string, default: "pending"
    field :analyzed_at, :utc_datetime
    field :removed_at, :utc_datetime

    belongs_to :channel, Quotor.Catalog.Channel
    belongs_to :source, Quotor.Catalog.Source

    timestamps(type: :utc_datetime)
  end
end
