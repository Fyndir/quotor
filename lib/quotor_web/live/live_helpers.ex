defmodule QuotorWeb.LiveHelpers do
  @moduledoc "Fonctions communes aux LiveViews."

  alias Quotor.Accounts.Scope

  @doc """
  Calcule (au `mount`, seul moment où `connect_info` est accessible) la clé de
  limitation de débit : l'utilisateur s'il est connecté, sinon l'IP (en
  tenant compte de `x-forwarded-for` derrière le proxy de Render).
  """
  def assign_rate_key(socket) do
    key =
      case Scope.user_id(socket.assigns[:current_scope]) do
        nil -> {:ip, client_ip(socket)}
        id -> {:user, id}
      end

    Phoenix.Component.assign(socket, :rate_key, key)
  end

  defp client_ip(socket) do
    forwarded =
      (Phoenix.LiveView.get_connect_info(socket, :x_headers) || [])
      |> Enum.find_value(fn
        {"x-forwarded-for", value} -> value |> String.split(",") |> List.first() |> String.trim()
        _ -> nil
      end)

    forwarded ||
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: addr} -> addr |> :inet.ntoa() |> to_string()
        _ -> "unknown"
      end
  end
end
