defmodule QuotorWeb.MediaControllerTest do
  use QuotorWeb.ConnCase, async: false

  alias Quotor.Media

  setup do
    path = Media.prepare!("clips/test/sample.mp4")
    File.write!(path, "0123456789")
    on_exit(fn -> File.rm(path) end)
    :ok
  end

  test "sert un fichier entier", %{conn: conn} do
    conn = get(conn, "/media/clips/test/sample.mp4")
    assert conn.status == 200
    assert conn.resp_body == "0123456789"
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert [ct] = get_resp_header(conn, "content-type")
    assert ct =~ "video/mp4"
  end

  test "requête Range (lecture vidéo Safari)", %{conn: conn} do
    conn = conn |> put_req_header("range", "bytes=2-5") |> get("/media/clips/test/sample.mp4")
    assert conn.status == 206
    assert conn.resp_body == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]
  end

  test "range invalide", %{conn: conn} do
    conn = conn |> put_req_header("range", "bytes=50-60") |> get("/media/clips/test/sample.mp4")
    assert conn.status == 416
  end

  test "refuse les traversées de répertoire et les dossiers privés", %{conn: conn} do
    assert get(conn, "/media/clips/../../etc/passwd").status == 404
    assert get(conn, "/media/sources/1.mp4").status == 404
    assert get(conn, "/media/clips/test/absent.mp4").status == 404
  end

  test "parse_range/2" do
    assert QuotorWeb.MediaController.parse_range(["bytes=-3"], 10) == {:ok, 7, 9}
    assert QuotorWeb.MediaController.parse_range(["bytes=4-"], 10) == {:ok, 4, 9}
    assert QuotorWeb.MediaController.parse_range([], 10) == :none
  end
end
