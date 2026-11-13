defmodule QuotorWeb.DownloadControllerTest do
  # écrit dans MEDIA_DIR et bascule le stockage en S3 factice : pas d'async
  use QuotorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Quotor.CatalogFixtures

  alias Quotor.{FakeS3, Media, Repo}
  alias Quotor.Montages.Montage
  alias QuotorWeb.DownloadController

  setup do
    [quote] = quotes_fixture(source_fixture(), ["Bonjour à tous !"])
    key = "dl#{System.unique_integer([:positive])}"
    file = "montages/#{key}.mp4"

    montage =
      Repo.insert!(%Montage{
        key: key,
        query: "Ce jeu est complètement nul !",
        status: "ready",
        file_path: file,
        segments: [%{"quote_id" => quote.id, "source_id" => quote.source_id, "text" => "x"}]
      })

    for rel <- [file, quote.clip_path] do
      path = Path.join(Media.root(), rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "mp4:" <> rel)
      on_exit(fn -> File.rm(path) end)
    end

    %{montage: montage, quote: quote}
  end

  test "nom de fichier lisible" do
    assert DownloadController.filename("Ce jeu est complètement nul !") ==
             "quotor-ce-jeu-est-completement-nul.mp4"

    assert DownloadController.filename("?!") == "quotor.mp4"
  end

  test "télécharge un montage en pièce jointe", %{conn: conn, montage: m} do
    conn = get(conn, ~p"/m/#{m.key}/telecharger")

    assert response(conn, 200) == "mp4:" <> m.file_path
    assert get_resp_header(conn, "content-type") == ["video/mp4"]

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="quotor-ce-jeu-est-completement-nul.mp4")]
  end

  test "télécharge un extrait publié", %{conn: conn, quote: q} do
    conn = get(conn, ~p"/q/#{q.id}/telecharger")
    assert response(conn, 200) == "mp4:" <> q.clip_path

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="quotor-bonjour-a-tous.mp4")]
  end

  test "rien pour un montage inconnu ou un extrait masqué", %{conn: conn, quote: q} do
    assert response(get(conn, "/m/inconnu/telecharger"), 404)
    assert response(get(build_conn(), "/q/abc/telecharger"), 404)

    {:ok, _} = Quotor.Catalog.update_quote(q, %{enabled: false})
    assert response(get(build_conn(), ~p"/q/#{q.id}/telecharger"), 404)
  end

  test "depuis un bucket S3, l'archive est relayée", %{conn: conn, montage: m} do
    agent = FakeS3.setup!()
    path = Path.join(System.tmp_dir!(), "dl-#{m.key}.mp4")
    File.write!(path, "depuis le bucket")
    :ok = Quotor.Storage.S3.put(path, m.file_path)
    assert Map.has_key?(FakeS3.objects(agent), m.file_path)

    conn = get(conn, ~p"/m/#{m.key}/telecharger")
    assert response(conn, 200) == "depuis le bucket"
    assert [~s(attachment; filename=) <> _] = get_resp_header(conn, "content-disposition")
  end

  test "boutons présents sur les pages", %{conn: conn, montage: m, quote: q} do
    {:ok, view, _} = live(conn, ~p"/m/#{m.key}")
    assert has_element?(view, "#montage-#{m.key}-download[href='/m/#{m.key}/telecharger']")

    {:ok, view, _} = live(conn, ~p"/q/#{q.id}")
    assert has_element?(view, "#download-quote[href='/q/#{q.id}/telecharger']")
  end
end
