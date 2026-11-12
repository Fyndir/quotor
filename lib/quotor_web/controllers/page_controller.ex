defmodule QuotorWeb.PageController do
  use QuotorWeb, :controller

  def legal(conn, _params) do
    render(conn, :legal, page_title: "Mentions légales", legal: legal_info())
  end

  def terms(conn, _params) do
    render(conn, :terms,
      page_title: "Conditions d'utilisation & droit d'auteur",
      legal: legal_info()
    )
  end

  defp legal_info, do: Map.new(Application.get_env(:quotor, :legal, []))
end
