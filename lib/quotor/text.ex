defmodule Quotor.Text do
  @moduledoc """
  Normalisation du texte pour la recherche : minuscules, sans accents, sans
  ponctuation. La même fonction est appliquée aux sous-titres et aux requêtes,
  ce qui garantit des tokens identiques des deux côtés.
  """

  @doc """
  Normalise un texte.

      iex> Quotor.Text.normalize("  L'Été, c'est GÉNIAL !! ")
      "l ete c est genial"

      iex> Quotor.Text.normalize("Cœur & âme")
      "coeur ame"
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(nil), do: ""

  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(["œ", "æ"], fn
      "œ" -> "oe"
      "æ" -> "ae"
    end)
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  @doc "Découpe un texte normalisé en mots."
  @spec tokens(String.t()) :: [String.t()]
  def tokens(text), do: text |> normalize() |> String.split(" ", trim: true)

  @doc "Met une majuscule à la première lettre (affichage des sous-titres auto)."
  def capitalize_first(""), do: ""

  def capitalize_first(text) do
    {first, rest} = String.split_at(text, 1)
    String.upcase(first) <> rest
  end

  @doc "Formate des millisecondes en `m:ss`."
  def format_ms(ms) when is_integer(ms) do
    total = div(ms, 1000)
    h = div(total, 3600)
    m = div(rem(total, 3600), 60)
    s = rem(total, 60) |> Integer.to_string() |> String.pad_leading(2, "0")

    if h > 0,
      do: "#{h}:#{m |> Integer.to_string() |> String.pad_leading(2, "0")}:#{s}",
      else: "#{m}:#{s}"
  end

  def format_ms(_), do: "–"
end
