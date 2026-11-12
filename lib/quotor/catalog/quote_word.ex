defmodule Quotor.Catalog.QuoteWord do
  @moduledoc "Mot horodaté d'une quote (temps absolus dans la vidéo source)."
  use Ecto.Schema

  schema "quote_words" do
    field :position, :integer
    field :word, :string
    field :start_ms, :integer
    field :end_ms, :integer

    belongs_to :quote, Quotor.Catalog.Quote
  end
end
