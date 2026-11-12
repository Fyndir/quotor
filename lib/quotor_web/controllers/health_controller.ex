defmodule QuotorWeb.HealthController do
  @moduledoc "Point de contrôle de santé (utilisé par Render et Docker)."
  use QuotorWeb, :controller

  def show(conn, _params) do
    if Quotor.Monitoring.healthy?() do
      json(conn, %{status: "ok", version: to_string(Application.spec(:quotor, :vsn))})
    else
      conn |> put_status(503) |> json(%{status: "error", database: "unreachable"})
    end
  end
end
