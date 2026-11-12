defmodule Quotor.StorageS3Test do
  # Change la configuration globale du stockage : pas d'exécution en parallèle
  use QuotorWeb.ConnCase, async: false

  import Quotor.AccountsFixtures

  alias Quotor.{Catalog, FakeS3, Ingest, Media, Montages}
  alias Quotor.Storage.S3
  alias Quotor.Workers.{CutSource, IngestSource}

  setup do
    File.rm_rf!(Media.root())
    File.mkdir_p!(Media.root())
    %{bucket: FakeS3.setup!()}
  end

  describe "adaptateur S3" do
    test "envoi, présence, téléchargement, liste et suppression", %{bucket: bucket} do
      src = Path.join(Media.tmp_dir!("t"), "a.mp4")
      File.write!(src, "video-bytes")

      assert :ok = Media.store(src, "clips/1/a.mp4")
      refute File.exists?(src), "le fichier local est déplacé"
      assert %{"clips/1/a.mp4" => {"video-bytes", "video/mp4"}} = FakeS3.objects(bucket)

      assert Media.exists?("clips/1/a.mp4")
      refute Media.exists?("clips/1/absent.mp4")

      # téléchargé une fois dans le cache local
      assert {:ok, path} = Media.fetch("clips/1/a.mp4")
      assert File.read!(path) == "video-bytes"
      assert String.contains?(path, "/cache/clips/1/a.mp4")
      assert {:error, :not_found} = Media.fetch("clips/1/absent.mp4")

      assert [{"clips/1/a.mp4", 11}] = S3.list("clips/1/")
      assert %{"clips" => 11, "montages" => 0} = Media.usage()

      :ok = Media.delete_prefix("clips/1")
      assert FakeS3.objects(bucket) == %{}
      refute File.exists?(path), "le cache local est purgé aussi"
    end

    test "URL : relayée par le site, ou publique si configurée" do
      assert Media.url("clips/1/a.mp4") == "/media/clips/1/a.mp4"

      Application.put_env(
        :quotor,
        :s3,
        Keyword.put(Application.get_env(:quotor, :s3), :public_url, "https://media.example.com/")
      )

      assert Media.url("clips/1/a.mp4") == "https://media.example.com/clips/1/a.mp4"

      assert QuotorWeb.OpenGraph.absolute("clips/1/a.mp4") ==
               "https://media.example.com/clips/1/a.mp4"
    end

    test "le site relaie un bucket privé, requêtes Range comprises", %{conn: conn} do
      src = Path.join(Media.tmp_dir!("t"), "b.mp4")
      File.write!(src, "0123456789")
      :ok = Media.store(src, "clips/2/b.mp4")

      resp = get(conn, "/media/clips/2/b.mp4")
      assert resp.status == 200
      assert resp.resp_body == "0123456789"

      ranged = build_conn() |> put_req_header("range", "bytes=2-5") |> get("/media/clips/2/b.mp4")
      assert ranged.status == 206
      assert ranged.resp_body == "2345"
      assert get_resp_header(ranged, "content-range") == ["bytes 2-5/10"]

      assert get(build_conn(), "/media/clips/2/absent.mp4").status == 404
      assert get(build_conn(), "/media/sources/1.mp4").status == 404
    end
  end

  @tag :ffmpeg
  test "pipeline complet avec stockage objet : rien ne reste sur le disque du worker", %{
    bucket: bucket
  } do
    scope = Quotor.Accounts.Scope.for_user(admin_fixture())
    {:ok, source} = Ingest.submit_youtube("https://youtu.be/s3s3s3s3s3s", scope)

    assert :ok = perform_job(IngestSource, %{source_id: source.id})
    source = Catalog.get_source!(source.id)
    assert Map.has_key?(FakeS3.objects(bucket), source.file_path)

    # la découpe se fait sur « un autre worker » : cache local vidé
    File.rm_rf!(Path.join(Media.root(), "cache"))
    assert :ok = perform_job(CutSource, %{source_id: source.id})

    source = Catalog.get_source!(source.id)
    assert source.status == "ready"
    objects = FakeS3.objects(bucket)

    for q <- Catalog.list_quotes_for_source(source.id) do
      assert q.status == "ready"
      assert {_, "video/mp4"} = objects[q.clip_path]
      assert {_, "image/jpeg"} = objects[q.thumb_path]
    end

    # vidéo source supprimée du bucket après découpe, aucun clip sur le disque
    refute Enum.any?(Map.keys(objects), &String.starts_with?(&1, "sources/#{source.id}.mp4"))
    assert Path.wildcard(Path.join([Media.root(), "{clips,thumbs}", "**", "*.*"])) == []
    # ni vidéo ni sous-titres laissés dans le cache du worker
    assert Path.wildcard(Path.join([Media.root(), "cache", "**", "*.*"])) == []

    # montage : clips récupérés depuis le bucket, résultat renvoyé au bucket
    assert {:ok, montage} = Montages.build("bonjour on teste un jeu pourri", nil)
    assert Map.has_key?(FakeS3.objects(bucket), montage.file_path)
  end

  @tag :ffmpeg
  test "un fichier envoyé par l'admin est rangé dans le bucket pour les workers", %{
    bucket: bucket
  } do
    tmp = Media.tmp_dir!("upload-test")
    video = Path.join(tmp, "v.mp4")
    subs = Path.join(tmp, "v.srt")
    :ok = Quotor.FakeDownloader.generate_video(video, 4)
    File.write!(subs, "1\n00:00:00,500 --> 00:00:02,000\nSalut tout le monde.\n")

    {:ok, source} = Ingest.submit_upload(%{"title" => "Envoi"}, video, subs, nil)
    objects = FakeS3.objects(bucket)
    assert Map.has_key?(objects, source.file_path)
    assert Map.has_key?(objects, source.subtitle_path)
    refute File.exists?(video)
  end
end
