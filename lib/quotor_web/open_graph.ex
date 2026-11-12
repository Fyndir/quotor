defmodule QuotorWeb.OpenGraph do
  @moduledoc """
  Balises Open Graph pour l'intégration des liens dans Discord (et autres
  messageries) : coller le lien d'une quote ou d'un montage affiche
  directement un lecteur vidéo dans la conversation.

  Les URLs doivent être absolues : elles sont construites à partir de
  l'URL publique de l'endpoint (`PHX_HOST` en production).
  """

  use Phoenix.VerifiedRoutes, endpoint: QuotorWeb.Endpoint, router: QuotorWeb.Router

  alias Quotor.Media

  @doc "Balises pour une quote."
  def for_quote(quote) do
    source = quote.source
    author = Quotor.Catalog.author_of(quote)

    %{
      type: "video.other",
      title:
        "« #{String.slice(quote.text, 0, 150)} »" <>
          if(author, do: " — #{author.name}", else: ""),
      description:
        [source && source.title, source && source.uploader]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.join(" — ")
        |> Kernel.<>(" · extrait parodique sur Quotor"),
      url: url(~p"/q/#{quote.id}"),
      image: absolute(quote.thumb_path),
      video: absolute(quote.clip_path),
      width: 854,
      height: 480
    }
  end

  @doc "Balises pour un montage."
  def for_montage(montage) do
    %{
      type: "video.other",
      title: "« #{String.slice(montage.query, 0, 150)} »",
      description: "Montage parodique de #{length(montage.segments)} extrait(s) · Quotor",
      url: url(~p"/m/#{montage.key}"),
      image: absolute(Quotor.Montages.poster_rel(montage)),
      video: absolute(montage.file_path),
      width: 640,
      height: 360
    }
  end

  @doc "URL absolue d'un fichier média (ou nil)."
  def absolute(nil), do: nil

  def absolute(rel) do
    case Media.url(rel) do
      # URL publique du bucket (déjà absolue)
      "http" <> _ = url -> url
      path -> QuotorWeb.Endpoint.url() <> path
    end
  end
end
