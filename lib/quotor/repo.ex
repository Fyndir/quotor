defmodule Quotor.Repo do
  use Ecto.Repo,
    otp_app: :quotor,
    adapter: Ecto.Adapters.Postgres
end
