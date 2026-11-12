defmodule Quotor.BackupTest do
  # dossier de sauvegardes et configuration partagés : pas d'async
  use Quotor.DataCase, async: false

  alias Quotor.{Backup, FakeS3, Media}
  alias Quotor.Workers.Backup, as: BackupWorker

  setup do
    previous = Application.get_env(:quotor, :backup)
    dir = Path.join(System.tmp_dir!(), "quotor_backup_test_#{System.unique_integer([:positive])}")
    Application.put_env(:quotor, :backup, Keyword.put(previous, :dir, dir))

    on_exit(fn ->
      Application.put_env(:quotor, :backup, previous)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  defp put_media(key, content) do
    path = Path.join(Media.root(), key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp tar_list(path) do
    {out, 0} = System.cmd("tar", ["-tf", path])
    String.split(out, "\n", trim: true)
  end

  # archive « à la main », sans pg_dump
  defp fake_archive(dir, name, files) do
    src = Path.join(dir, "src-#{System.unique_integer([:positive])}")

    for {rel, content} <- files do
      File.mkdir_p!(Path.dirname(Path.join(src, rel)))
      File.write!(Path.join(src, rel), content)
    end

    File.mkdir_p!(dir)
    archive = Path.join(dir, name)
    {_, 0} = System.cmd("tar", ["-cf", archive, "-C", src | Enum.map(files, &elem(&1, 0))])
    File.rm_rf!(src)
    archive
  end

  describe "noms" do
    test "seuls les noms générés sont acceptés" do
      assert Backup.valid_name?("quotor-20261113-020000.tar")
      refute Backup.valid_name?("../quotor-20261113-020000.tar")
      refute Backup.valid_name?("quotor-20261113-020000.tar/../../etc/passwd")
      refute Backup.valid_name?("autre.tar")
      refute Backup.valid_name?(nil)
    end
  end

  describe "création" do
    @describetag :pg_dump

    test "archive la base et les médias locaux", %{dir: dir} do
      put_media("clips/9/1.mp4", "clip")
      put_media("thumbs/9/1.jpg", "vignette")

      assert {:ok, %{name: name, size: size, media_files: n}} =
               Backup.run(now: ~U[2026-11-13 02:00:00Z])

      assert name == "quotor-20261113-020000.tar"
      assert n >= 2
      assert size > 0

      entries = tar_list(Path.join(dir, name))
      assert "manifest.json" in entries
      assert "db.dump" in entries
      assert "clips/9/1.mp4" in entries
      assert "thumbs/9/1.jpg" in entries
      refute Enum.any?(entries, &String.starts_with?(&1, "tmp"))

      assert [%{name: ^name, at: ~U[2026-11-13 02:00:00Z]}] = Backup.list()
    end

    test "sans les médias si demandé", %{dir: dir} do
      put_media("clips/9/2.mp4", "clip")
      assert {:ok, %{name: name, media_files: 0}} = Backup.run(media: false)
      refute Enum.any?(tar_list(Path.join(dir, name)), &String.starts_with?(&1, "clips"))
    end

    test "le worker sauvegarde puis applique la rétention", %{dir: dir} do
      for d <- ~w(20261101 20261102 20261103) do
        fake_archive(dir, "quotor-#{d}-020000.tar", [{"manifest.json", "{}"}])
      end

      Application.put_env(
        :quotor,
        :backup,
        Keyword.put(Application.get_env(:quotor, :backup), :keep, 2)
      )

      assert :ok = perform_job(BackupWorker, %{"manual" => true})

      assert [%{name: newest}, %{name: "quotor-20261103-020000.tar"}] = Backup.list()
      assert newest > "quotor-20261103-020000.tar"
    end
  end

  describe "liste, rétention et suppression" do
    test "triées de la plus récente à la plus ancienne, fichiers étrangers ignorés", %{dir: dir} do
      fake_archive(dir, "quotor-20261110-020000.tar", [{"manifest.json", "{}"}])
      fake_archive(dir, "quotor-20261112-020000.tar", [{"manifest.json", "{}"}])
      File.write!(Path.join(dir, "notes.txt"), "x")
      File.write!(Path.join(dir, "quotor-20261113-020000.tar.part"), "x")

      assert ["quotor-20261112-020000.tar", "quotor-20261110-020000.tar"] =
               Enum.map(Backup.list(), & &1.name)

      assert Backup.prune(1) == 1
      assert ["quotor-20261112-020000.tar"] = Enum.map(Backup.list(), & &1.name)

      Backup.delete("quotor-20261112-020000.tar")
      assert Backup.list() == []
    end
  end

  describe "restauration" do
    test "réécrit les médias de l'archive (sans toucher à la base)", %{dir: dir} do
      archive =
        fake_archive(dir, "quotor-20261113-030000.tar", [
          {"manifest.json", ~s({"app":"quotor"})},
          {"clips/77/1.mp4", "clip restauré"}
        ])

      dest = Path.join(Media.root(), "clips/77/1.mp4")
      on_exit(fn -> File.rm_rf(Path.join(Media.root(), "clips/77")) end)

      assert {:ok, %{media_files: 1}} = Backup.restore(archive, database: false)
      assert File.read!(dest) == "clip restauré"

      # par nom, depuis la destination
      File.write!(dest, "modifié")
      assert {:ok, _} = Backup.restore("quotor-20261113-030000.tar", database: false)
      assert File.read!(dest) == "clip restauré"
    end

    test "refuse une archive qui n'est pas une sauvegarde Quotor", %{dir: dir} do
      archive = fake_archive(dir, "quotor-20261113-040000.tar", [{"autre.txt", "x"}])
      assert {:error, msg} = Backup.restore(archive)
      assert msg =~ "manifest"
      assert {:error, _} = Backup.restore("quotor-20991231-000000.tar")
      assert {:error, _} = Backup.restore("/etc/../nimporte-quoi")
    end
  end

  describe "destination S3" do
    setup do
      agent = FakeS3.setup!()

      Application.put_env(
        :quotor,
        :backup,
        Keyword.put(Application.get_env(:quotor, :backup), :s3_bucket, "quotor-backups-test")
      )

      %{agent: agent}
    end

    test "liste, télécharge, restaure et supprime depuis un bucket distinct", %{
      agent: agent,
      dir: dir
    } do
      assert {:s3, "quotor-backups-test"} = Backup.destination()

      archive =
        fake_archive(dir, "quotor-20261113-050000.tar", [
          {"manifest.json", ~s({"app":"quotor"})},
          {"clips/78/1.mp4", "clip s3"}
        ])

      :ok =
        Quotor.Storage.S3.put(archive, "backups/quotor-20261113-050000.tar",
          bucket: "quotor-backups-test"
        )

      assert [%{name: "quotor-20261113-050000.tar"}] = Backup.list()

      # rien dans le bucket des médias (qui peut être public)
      assert FakeS3.objects(agent) == %{}

      # la restauration renvoie les médias vers le stockage S3 des médias
      assert {:ok, %{media_files: 1}} =
               Backup.restore("quotor-20261113-050000.tar", database: false)

      assert %{"clips/78/1.mp4" => {"clip s3", _}} = FakeS3.objects(agent)

      Backup.delete("quotor-20261113-050000.tar")
      assert Backup.list() == []
      assert FakeS3.objects(agent, "quotor-backups-test") == %{}
    end
  end

  describe "tâche" do
    test "lancement manuel unique" do
      assert {:ok, :started} = BackupWorker.enqueue()
      assert {:ok, :already_running} = BackupWorker.enqueue()
      assert_enqueued(worker: BackupWorker, args: %{manual: true})
      assert %{running?: true, failure: nil} = BackupWorker.status()
    end

    test "la sauvegarde planifiée peut être désactivée" do
      Application.put_env(
        :quotor,
        :backup,
        Keyword.put(Application.get_env(:quotor, :backup), :enabled, false)
      )

      assert {:cancel, _} = perform_job(BackupWorker, %{})
    end
  end
end
