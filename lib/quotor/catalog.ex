defmodule Quotor.Catalog do
  @moduledoc """
  Catalogue : chaînes suivies, vidéos sources, quotes, favoris et signalements.
  """

  import Ecto.Query, warn: false

  alias Quotor.Repo
  alias Quotor.Media
  alias Quotor.Accounts.Scope
  alias Quotor.Catalog.{Author, Channel, Source, Quote, QuoteWord, Favorite, Report}

  @topic "catalog"

  def subscribe, do: Phoenix.PubSub.subscribe(Quotor.PubSub, @topic)

  def broadcast(event),
    do: Phoenix.PubSub.broadcast(Quotor.PubSub, @topic, {__MODULE__, event})

  ## Chaînes

  def list_channels, do: Repo.all(from c in Channel, order_by: c.name)
  def list_enabled_channels, do: Repo.all(from c in Channel, where: c.enabled)
  def get_channel!(id), do: Repo.get!(Channel, id)
  def change_channel(%Channel{} = c, attrs \\ %{}), do: Channel.changeset(c, attrs)
  def create_channel(attrs), do: %Channel{} |> Channel.changeset(attrs) |> Repo.insert()
  def update_channel(%Channel{} = c, attrs), do: c |> Channel.changeset(attrs) |> Repo.update()
  def delete_channel(%Channel{} = c), do: Repo.delete(c)

  def mark_channel_synced(%Channel{} = c, error \\ nil) do
    c
    |> Channel.sync_changeset(%{last_synced_at: DateTime.utc_now(:second), last_error: error})
    |> Repo.update()
  end

  ## Auteurs

  def list_authors, do: Repo.all(from a in Author, order_by: fragment("lower(?)", a.name))

  def get_author!(id), do: Repo.get!(Author, id)
  def get_author_by_slug(slug), do: Repo.get_by(Author, slug: slug)

  def change_author(%Author{} = author, attrs \\ %{}), do: Author.changeset(author, attrs)

  def create_author(attrs), do: %Author{} |> Author.changeset(attrs) |> Repo.insert()

  def update_author(%Author{} = author, attrs),
    do: author |> Author.changeset(attrs) |> Repo.update()

  def delete_author(%Author{} = author), do: Repo.delete(author)

  @doc """
  Retrouve un auteur par son nom (insensible à la casse et aux accents) ou le
  crée. Utilisé à l'ingestion pour rattacher automatiquement une vidéo à sa
  chaîne YouTube.
  """
  def find_or_create_author(attrs) do
    name = attrs |> Map.get(:name, "") |> to_string() |> String.trim()

    case name != "" && get_author_by_slug(Author.slugify(name)) do
      %Author{} = author ->
        {:ok, author}

      _ ->
        case create_author(Map.put(attrs, :name, name)) do
          {:ok, author} ->
            {:ok, author}

          # course entre deux ingestions : l'auteur vient d'être créé
          {:error, _} = error ->
            get_author_by_slug(Author.slugify(name)) |> then(&if(&1, do: {:ok, &1}, else: error))
        end
    end
  end

  @doc """
  Auteurs ayant au moins une quote visible, avec leur nombre de quotes
  (une quote compte pour son auteur effectif).
  """
  def list_public_authors do
    from(q in subquery(effective_authors_query()),
      join: a in Author,
      on: a.id == q.author_id,
      group_by: a.id,
      order_by: [desc: count(q.id), asc: a.name],
      select: {a, count(q.id)}
    )
    |> Repo.all()
  end

  @doc "Nombre de quotes (toutes) par auteur effectif, pour l'admin."
  def count_quotes_by_author do
    from(q in Quote,
      join: s in assoc(q, :source),
      group_by: fragment("coalesce(?, ?)", q.author_id, s.author_id),
      select: {fragment("coalesce(?, ?)", q.author_id, s.author_id), count(q.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp effective_authors_query do
    visible_quotes()
    |> select([q, s], %{id: q.id, author_id: fragment("coalesce(?, ?)", q.author_id, s.author_id)})
  end

  @doc "Quotes visibles d'un auteur (les siennes et celles des vidéos dont il est l'auteur)."
  def author_quotes(%Author{id: id}, limit \\ 24, offset \\ 0) do
    visible_quotes()
    |> where([q, s], q.author_id == ^id or (is_nil(q.author_id) and s.author_id == ^id))
    |> order_by([q], desc: q.views_count, desc: q.id)
    |> limit(^limit)
    |> offset(^offset)
    |> with_display()
    |> Repo.all()
  end

  @doc "Auteurs dont le nom correspond à une recherche (suggestions)."
  def search_authors(query, limit \\ 4) do
    norm = Quotor.Text.normalize(query)

    if String.length(norm) < 3 do
      []
    else
      slug_part = String.replace(norm, " ", "-")

      Repo.all(
        from a in Author,
          where: like(a.slug, ^"%#{slug_part}%"),
          order_by: [asc: fragment("length(?)", a.slug)],
          limit: ^limit
      )
    end
  end

  ## Sources

  def list_sources(opts \\ []) do
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    Source
    |> then(fn q -> if status in [nil, ""], do: q, else: where(q, [s], s.status == ^status) end)
    |> then(fn q ->
      if search in [nil, ""],
        do: q,
        else: where(q, [s], ilike(s.title, ^"%#{search}%") or s.youtube_id == ^search)
    end)
    |> order_by([s], desc: s.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 200))
    |> preload(:channel)
    |> Repo.all()
  end

  def get_source!(id), do: Repo.get!(Source, id)
  def get_source(id), do: Repo.get(Source, id)
  def get_source_by_youtube_id(id), do: Repo.get_by(Source, youtube_id: id)

  def change_youtube_source(attrs \\ %{}), do: Source.youtube_changeset(%Source{}, attrs)

  def create_youtube_source(attrs) do
    %Source{} |> Source.youtube_changeset(attrs) |> Repo.insert() |> tap_broadcast()
  end

  def create_upload_source(attrs) do
    %Source{} |> Source.upload_changeset(attrs) |> Repo.insert() |> tap_broadcast()
  end

  def update_source(%Source{} = source, attrs) do
    source |> Source.update_changeset(attrs) |> Repo.update() |> tap_broadcast()
  end

  @doc "Supprime une source, ses quotes et tous les fichiers associés."
  def delete_source(%Source{} = source) do
    Media.delete_prefix("clips/#{source.id}")
    Media.delete_prefix("thumbs/#{source.id}")
    Media.delete(source.file_path)
    Media.delete(source.subtitle_path)
    Repo.delete(source) |> tap_broadcast()
  end

  def count_sources_by_status do
    from(s in Source, group_by: s.status, select: {s.status, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp tap_broadcast({:ok, %Source{} = s} = result) do
    broadcast({:source_updated, s})
    result
  end

  defp tap_broadcast(other), do: other

  ## Quotes

  @doc "Requête de base : quotes visibles par le public."
  def visible_quotes do
    from q in Quote,
      as: :quote,
      join: s in assoc(q, :source),
      as: :source,
      where: q.status == "ready" and q.enabled and s.enabled
  end

  @doc """
  Précharge ce qu'il faut pour afficher une quote : sa source et les auteurs
  (de la quote et de la source). À utiliser sur une requête issue de
  `visible_quotes/0`.
  """
  def with_display(query) do
    preload(query, [q, s], [:author, source: {s, :author}])
  end

  @doc """
  Auteur effectif d'une quote : le sien s'il est défini, sinon celui de sa
  vidéo source (souvent la chaîne YouTube). Nécessite `with_display/1`.
  """
  def author_of(%Quote{author: %Author{} = author}), do: author
  def author_of(%Quote{source: %Source{author: %Author{} = author}}), do: author
  def author_of(_), do: nil

  @doc "Récupère une quote visible (ou `nil`)."
  def get_public_quote(id) do
    visible_quotes()
    |> where([q], q.id == ^id)
    |> with_display()
    |> Repo.one()
  end

  def get_quote!(id),
    do: Quote |> Repo.get!(id) |> Repo.preload([:author, :words, source: :author])

  def list_quote_words(quote_id) do
    Repo.all(from w in QuoteWord, where: w.quote_id == ^quote_id, order_by: w.position)
  end

  def list_quotes_for_source(source_id) do
    Repo.all(from q in Quote, where: q.source_id == ^source_id, order_by: q.start_ms)
  end

  def pending_quotes_for_source(source_id) do
    Repo.all(
      from q in Quote,
        where: q.source_id == ^source_id and q.status != "ready",
        order_by: q.start_ms
    )
  end

  @doc "Quotes aléatoires pour la page d'accueil."
  def random_quotes(limit \\ 12) do
    visible_quotes()
    |> order_by(fragment("random()"))
    |> limit(^limit)
    |> with_display()
    |> Repo.all()
  end

  def latest_quotes(limit \\ 12, offset \\ 0) do
    visible_quotes()
    |> order_by([q], desc: q.inserted_at, desc: q.id)
    |> limit(^limit)
    |> offset(^offset)
    |> with_display()
    |> Repo.all()
  end

  @doc "Quotes les plus vues (onglet Découvrir)."
  def popular_quotes(limit \\ 12, offset \\ 0) do
    visible_quotes()
    |> order_by([q], desc: q.views_count, desc: q.id)
    |> limit(^limit)
    |> offset(^offset)
    |> with_display()
    |> Repo.all()
  end

  def list_admin_quotes(opts \\ []) do
    search = Keyword.get(opts, :search)
    source_id = Keyword.get(opts, :source_id)

    Quote
    |> then(fn q ->
      if search in [nil, ""],
        do: q,
        else: where(q, [q], ilike(q.norm, ^"%#{Quotor.Text.normalize(search)}%"))
    end)
    |> then(fn q -> if source_id, do: where(q, [q], q.source_id == ^source_id), else: q end)
    |> order_by([q], desc: q.id)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> preload([:author, source: :author])
    |> Repo.all()
  end

  def count_quotes do
    from(q in Quote, group_by: q.status, select: {q.status, count(q.id)})
    |> Repo.all()
    |> Map.new()
  end

  def change_quote(%Quote{} = q, attrs \\ %{}), do: Quote.changeset(q, attrs)

  def update_quote(%Quote{} = q, attrs), do: q |> Quote.changeset(attrs) |> Repo.update()

  def update_quote_media(%Quote{} = q, attrs),
    do: q |> Quote.media_changeset(attrs) |> Repo.update()

  def increment_views(quote_id) do
    from(q in Quote, where: q.id == ^quote_id) |> Repo.update_all(inc: [views_count: 1])
  end

  @padding_before 120
  @padding_after 250

  @doc """
  Remplace toutes les quotes d'une source par les segments fournis
  (cf. `Quotor.Ingest.Segmenter`). Les anciens fichiers sont supprimés.
  """
  def replace_quotes(%Source{} = source, segments, source_duration_ms \\ nil) do
    now = DateTime.utc_now(:second)
    max_end = source_duration_ms || :infinity

    Repo.transaction(fn ->
      Repo.delete_all(from q in Quote, where: q.source_id == ^source.id)

      Enum.each(segments, fn seg ->
        clip_end = seg.end_ms + @padding_after
        clip_end = if max_end == :infinity, do: clip_end, else: min(clip_end, max_end)

        quote =
          Repo.insert!(%Quote{
            source_id: source.id,
            text: seg.text,
            norm: seg.norm,
            start_ms: seg.start_ms,
            end_ms: seg.end_ms,
            clip_start_ms: max(seg.start_ms - @padding_before, 0),
            clip_end_ms: max(clip_end, seg.start_ms + 300),
            status: "pending",
            inserted_at: now,
            updated_at: now
          })

        words =
          Enum.map(seg.words, fn w ->
            %{
              quote_id: quote.id,
              position: w.position,
              word: String.slice(w.word, 0, 255),
              start_ms: w.start_ms,
              end_ms: w.end_ms
            }
          end)

        words
        |> Enum.chunk_every(1000)
        |> Enum.each(&Repo.insert_all(QuoteWord, &1))
      end)

      length(segments)
    end)
    |> tap(fn _ ->
      Media.delete_prefix("clips/#{source.id}")
      Media.delete_prefix("thumbs/#{source.id}")
    end)
  end

  ## Favoris (utilisateurs connectés)

  def toggle_favorite(%Scope{user: user}, quote_id) when not is_nil(user) do
    case Repo.get_by(Favorite, user_id: user.id, quote_id: quote_id) do
      nil ->
        Repo.insert(%Favorite{user_id: user.id, quote_id: quote_id}, on_conflict: :nothing)
        :added

      fav ->
        Repo.delete(fav)
        :removed
    end
  end

  def favorite_ids(scope, quote_ids) do
    case Scope.user_id(scope) do
      nil ->
        MapSet.new()

      user_id ->
        from(f in Favorite,
          where: f.user_id == ^user_id and f.quote_id in ^quote_ids,
          select: f.quote_id
        )
        |> Repo.all()
        |> MapSet.new()
    end
  end

  def list_favorites(%Scope{user: user}) do
    visible_quotes()
    |> join(:inner, [q], f in Favorite, on: f.quote_id == q.id and f.user_id == ^user.id)
    |> order_by([q, s, f], desc: f.inserted_at)
    |> with_display()
    |> Repo.all()
  end

  ## Signalements

  def change_report(attrs \\ %{}), do: Report.changeset(%Report{}, attrs)

  def create_report(attrs) do
    with {:ok, report} <- %Report{} |> Report.changeset(attrs) |> Repo.insert() do
      broadcast({:report_created, report})
      {:ok, report}
    end
  end

  def list_reports(status \\ nil) do
    Report
    |> then(fn q -> if status, do: where(q, [r], r.status == ^status), else: q end)
    |> order_by([r], desc: r.inserted_at)
    |> preload(quote: :source, source: [])
    |> limit(200)
    |> Repo.all()
  end

  def get_report!(id), do: Report |> Repo.get!(id) |> Repo.preload(quote: :source, source: [])

  def resolve_report(%Report{} = report, attrs),
    do: report |> Report.resolve_changeset(attrs) |> Repo.update()

  def count_open_reports, do: Repo.aggregate(from(r in Report, where: r.status == "open"), :count)
end
