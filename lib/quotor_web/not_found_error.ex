defmodule QuotorWeb.NotFoundError do
  @moduledoc "Levée quand une ressource publique n'existe pas (rendue en 404)."
  defexception message: "introuvable", plug_status: 404
end
