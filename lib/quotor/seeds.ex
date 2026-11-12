defmodule Quotor.Seeds do
  @moduledoc """
  Données initiales, idempotentes :

    * l'administrateur défini par `ADMIN_EMAIL` / `ADMIN_PASSWORD` ;
    * quelques chaînes françaises connues, **désactivées par défaut** : c'est à
      l'admin de vérifier l'URL et d'activer le suivi.
  """

  require Logger

  alias Quotor.{Accounts, Catalog, Repo}
  alias Quotor.Catalog.Channel

  @channels [
    %{name: "Joueur Du Grenier", url: "https://www.youtube.com/@joueurdugrenier"},
    %{name: "Cyprien", url: "https://www.youtube.com/@cyprien"},
    %{name: "Bref", url: "https://www.youtube.com/@bref"},
    %{name: "Chroma (Karim Debbache)", url: "https://www.youtube.com/@KarimDebbache"}
  ]

  def run do
    seed_admin()
    seed_channels()
    :ok
  end

  def seed_admin do
    email = System.get_env("ADMIN_EMAIL")
    password = System.get_env("ADMIN_PASSWORD")

    cond do
      email in [nil, ""] ->
        :skip

      password in [nil, ""] or String.length(password) < 12 ->
        Logger.warning(
          "ADMIN_PASSWORD absent ou trop court (12 caractères min.) : admin non créé"
        )

      true ->
        case Accounts.ensure_admin(email, password) do
          {:ok, _} -> Logger.info("administrateur #{email} prêt")
          {:error, cs} -> Logger.error("création de l'admin impossible : #{inspect(cs.errors)}")
        end
    end
  end

  def seed_channels do
    Enum.each(@channels, fn attrs ->
      unless Repo.get_by(Channel, url: attrs.url), do: Catalog.create_channel(attrs)
    end)
  end
end
