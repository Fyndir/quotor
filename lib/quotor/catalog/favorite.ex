defmodule Quotor.Catalog.Favorite do
  @moduledoc "Quote mise en favori par un utilisateur connecté."
  use Ecto.Schema

  schema "favorites" do
    belongs_to :user, Quotor.Accounts.User
    belongs_to :quote, Quotor.Catalog.Quote

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
