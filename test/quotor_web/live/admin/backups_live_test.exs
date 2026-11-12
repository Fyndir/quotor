defmodule QuotorWeb.Admin.BackupsLiveTest do
  use QuotorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Quotor.Backup

  @name "quotor-20261113-020000.tar"

  setup %{conn: conn} do
    previous = Application.get_env(:quotor, :backup)

    dir =
      Path.join(System.tmp_dir!(), "quotor_backups_live_#{System.unique_integer([:positive])}")

    Application.put_env(:quotor, :backup, Keyword.put(previous, :dir, dir))
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, @name), "archive")

    on_exit(fn ->
      Application.put_env(:quotor, :backup, previous)
      File.rm_rf(dir)
    end)

    register_and_log_in_admin(%{conn: conn}) |> Map.put(:dir, dir)
  end

  test "liste les sauvegardes et la procédure de restauration", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/sauvegardes")

    assert has_element?(view, "#backup-quotor-20261113-020000-tar")
    assert has_element?(view, "#backup-settings")
    assert view |> element("#restore-help") |> render() =~ @name
  end

  test "lance une sauvegarde en arrière-plan", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/sauvegardes")

    view |> element("#backup-now") |> render_click()

    assert_enqueued(worker: Quotor.Workers.Backup, args: %{manual: true})
    assert has_element?(view, "#backup-now[disabled]")
  end

  test "supprime une sauvegarde", %{conn: conn, dir: dir} do
    {:ok, view, _html} = live(conn, ~p"/admin/sauvegardes")

    render_click(view, "delete", %{"name" => @name})

    refute File.exists?(Path.join(dir, @name))
    assert Backup.list() == []
  end

  test "télécharge une archive, refuse les noms invalides", %{conn: conn} do
    conn = get(conn, ~p"/admin/sauvegardes/#{@name}")
    assert response(conn, 200) == "archive"
    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="#{@name}")]

    assert response(get(recycle(conn), "/admin/sauvegardes/quotor-20990101-000000.tar"), 404)
    assert response(get(recycle(conn), "/admin/sauvegardes/..%2Fsecret"), 404)
  end

  test "le téléchargement est réservé aux administrateurs" do
    conn = build_conn()
    assert redirected_to(get(conn, ~p"/admin/sauvegardes/#{@name}")) == "/"
  end
end
