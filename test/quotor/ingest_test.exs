defmodule Quotor.IngestTest do
  # Écrit dans MEDIA_DIR : pas d'exécution en parallèle
  use Quotor.DataCase, async: false

  import Quotor.AccountsFixtures

  alias Quotor.{Catalog, Ingest, Media, Montages}
  alias Quotor.Workers.{CutSource, IngestSource, SyncChannels}

  setup do
    File.rm_rf!(Media.root())
    File.mkdir_p!(Media.root())
    %{scope: Quotor.Accounts.Scope.for_user(admin_fixture())}
  end

  test "la soumission met la vidéo en file d'attente", %{scope: scope} do
    {:ok, source} = Ingest.submit_youtube("https://youtu.be/aaaaaaaaaaa", scope)
    assert source.status == "pending"
    assert source.submitted_by_id == scope.user.id
    assert_enqueued(worker: IngestSource, args: %{source_id: source.id})
  end

  @tag :ffmpeg
  test "pipeline complet : téléchargement, quotes, découpe, montage", %{scope: scope} do
    {:ok, source} = Ingest.submit_youtube("https://youtu.be/bbbbbbbbbbb", scope)

    assert :ok = perform_job(IngestSource, %{source_id: source.id})
    source = Catalog.get_source!(source.id)
    assert source.status == "cutting"
    assert source.title == "Vidéo de test"
    assert source.quotes_count == 2

    # la vidéo est rattachée automatiquement à sa chaîne YouTube
    assert source.channel_url == "https://www.youtube.com/@chainetest"
    author = Catalog.get_author!(source.author_id)
    assert author.name == "Chaîne test"
    assert author.kind == "channel"
    assert author.url == "https://www.youtube.com/@chainetest"
    assert_enqueued(worker: CutSource, args: %{source_id: source.id})

    assert :ok = perform_job(CutSource, %{source_id: source.id})
    source = Catalog.get_source!(source.id)
    assert source.status == "ready"
    # la vidéo source est supprimée après découpe
    assert source.file_path == nil

    quotes = Catalog.list_quotes_for_source(source.id)
    assert Enum.all?(quotes, &(&1.status == "ready"))

    for q <- quotes do
      assert File.exists?(Media.abs_path(q.clip_path))
      assert File.exists?(Media.abs_path(q.thumb_path))
    end

    # Mode avancé : « bonjour » + « on teste un jeu pourri »
    assert {:ok, montage} = Montages.build("bonjour on teste un jeu pourri", nil)
    assert montage.status == "ready"
    assert length(montage.segments) == 2
    assert File.exists?(Media.abs_path(montage.file_path))

    # même phrase, mêmes extraits : montage en cache
    assert {:ok, again} = Montages.build("Bonjour, on teste un jeu pourri !", nil)
    assert again.id == montage.id
  end

  @tag :ffmpeg
  test "sans sous-titres : échec définitif" do
    {:ok, source} = Ingest.submit_youtube("https://www.youtube.com/watch?v=nosubsxxxxx", nil)

    assert {:cancel, "Aucun sous-titre français disponible"} =
             perform_job(IngestSource, %{source_id: source.id})

    assert %{status: "failed", error: "Aucun sous-titre français disponible"} =
             Catalog.get_source!(source.id)
  end

  test "erreur de téléchargement : le job sera réessayé" do
    {:ok, source} = Ingest.submit_youtube("https://www.youtube.com/watch?v=failxxxxxxx", nil)

    assert {:error, "HTTP Error 403: Forbidden"} =
             perform_job(IngestSource, %{source_id: source.id})

    assert %{status: "failed"} = Catalog.get_source!(source.id)

    {:ok, _} = Ingest.retry(Catalog.get_source!(source.id))
    assert %{status: "pending", error: nil} = Catalog.get_source!(source.id)
  end

  test "synchronisation d'une chaîne : seules les nouvelles vidéos sont ajoutées" do
    {:ok, channel} =
      Catalog.create_channel(%{
        name: "Test",
        url: "https://www.youtube.com/@test",
        enabled: true,
        max_videos: 2
      })

    assert {:ok, 2} = Ingest.sync_channel(channel)
    assert {:ok, 0} = Ingest.sync_channel(channel)
    assert length(Catalog.list_sources()) == 2

    assert :ok = perform_job(SyncChannels, %{})
    assert %{last_synced_at: %DateTime{}} = Catalog.get_channel!(channel.id)
  end
end
