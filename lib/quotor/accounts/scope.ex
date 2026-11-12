defmodule Quotor.Accounts.Scope do
  @moduledoc """
  Portée (scope) de l'appelant.

  Trois profils existent dans Quotor :

    * **anonyme** — aucun scope (`nil`) ou scope sans utilisateur : recherche,
      lecture des extraits, montages, signalements ;
    * **utilisateur** — en plus : favoris et historique de ses montages ;
    * **admin** — en plus : supervision, gestion des sources / chaînes / extraits,
      utilisateurs et signalements.
  """

  alias Quotor.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc "Profil de l'appelant : `:anonymous`, `:user` ou `:admin`."
  def profile(%__MODULE__{user: %User{role: "admin"}}), do: :admin
  def profile(%__MODULE__{user: %User{}}), do: :user
  def profile(_), do: :anonymous

  def admin?(scope), do: profile(scope) == :admin
  def user?(scope), do: profile(scope) in [:user, :admin]

  def user_id(%__MODULE__{user: %User{id: id}}), do: id
  def user_id(_), do: nil
end
