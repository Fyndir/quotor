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
      assert File.exists?(Quotor.Storage.Local.path(q.clip_path))
      assert File.exists?(Quotor.Storage.Local.path(q.thumb_path))
    end

    # Mode avancé : « bonjour » + « on teste un jeu pourri »
    assert {:ok, montage} = Montages.build("bonjour on teste un jeu pourri", nil)
    assert montage.status == "ready"
    assert length(montage.segments) == 2
    assert File.exists?(Quotor.Storage.Local.path(montage.file_path))

    # même phrase, mêmes extraits : montage en cache
    assert {:ok, again} = Montages.build("Bonjour, on teste un jeu pourri !", nil)
    assert again.id == montage.id
  end

  @tag :ffmpeg
  test "sans sous-titres ni transcription : échec définitif" do
    {:ok, source} = Ingest.submit_youtube("https://www.youtube.com/watch?v=nosubsxxxxx", nil)

    assert {:cancel, "Aucun sous-titre français disponible" <> _} =
             perform_job(IngestSource, %{source_id: source.id})

    assert %{status: "failed", error: "Aucun sous-titre français disponible" <> _} =
             Catalog.get_source!(source.id)
  end

  describe "transcription vocale" do
    # (affinage : cf. describe « affinage des clips » plus bas)
    setup do
      previous = Application.get_env(:quotor, :transcription)
      Application.put_env(:quotor, :transcription, enabled: true, min_score: 0.75)

      on_exit(fn ->
        Application.put_env(:quotor, :transcription, previous)
        Application.delete_env(:quotor, :fake_transcript)
      end)
    end

    # ce que « dit » la vidéo de test, décalé de 150 ms par rapport aux sous-titres
    @heard [
      {"Bonjour", 150, 550},
      {"à", 550, 750},
      {"tous,", 750, 1050},
      {"c'est", 1050, 1350},
      {"le", 1350, 1500},
      {"joueur", 1660, 2050},
      {"du", 2050, 2250},
      {"grenier.", 2250, 2600},
      {"Aujourd'hui", 3950, 4450},
      {"on", 4450, 4650},
      {"teste", 4650, 4950},
      {"un", 4950, 5150},
      {"jeu", 5150, 5450},
      {"pourri.", 5450, 5900}
    ]

    defp ingest(url) do
      {:ok, source} = Ingest.submit_youtube(url, nil)
      result = perform_job(IngestSource, %{source_id: source.id})
      {result, Catalog.get_source!(source.id), Catalog.list_quotes_for_source(source.id)}
    end

    @tag :ffmpeg
    test "sous-titres confirmés par la parole : quotes vérifiées et recalées" do
      Application.put_env(:quotor, :fake_transcript, @heard)

      {:ok, source, quotes} = ingest("https://youtu.be/asrokxxxxxx")

      assert %{text_origin: "subtitles", asr_status: "done"} = source
      assert quotes != []
      assert Enum.all?(quotes, &(&1.asr_score == 1.0 and &1.enabled))

      # bornes recalées sur la parole (sous-titres : 0 ms, parole : 150 ms)
      assert hd(quotes).start_ms == 150
    end

    @tag :ffmpeg
    test "texte contredit par la parole : score faible avant découpe" do
      heard =
        Enum.map(@heard, fn
          {_, s, e} when s < 3000 -> {"blabla", s, e}
          word -> word
        end)

      Application.put_env(:quotor, :fake_transcript, heard)

      {:ok, _source, quotes} = ingest("https://youtu.be/asrkoxxxxxx")

      {first, rest} = Enum.split_with(quotes, &(&1.start_ms < 3000))
      assert Enum.all?(first, &(&1.asr_score < 0.4))
      assert Enum.all?(rest, &(&1.asr_score == 1.0))
      # rien n'est encore publié : c'est l'affinage, après découpe, qui décide
      assert Enum.all?(quotes, &(&1.status == "pending"))
    end

    @tag :ffmpeg
    test "sans sous-titres : les quotes viennent de la transcription" do
      Application.put_env(:quotor, :fake_transcript, @heard)

      {:ok, source, quotes} = ingest("https://www.youtube.com/watch?v=nosubsasr01")

      assert %{status: "cutting", text_origin: "transcription", asr_status: "done"} = source

      assert Enum.map(quotes, & &1.text) == [
               "Bonjour à tous, c'est le joueur du grenier.",
               "Aujourd'hui on teste un jeu pourri."
             ]

      assert Enum.all?(quotes, &(&1.asr_score == 0.9))
    end

    @tag :ffmpeg
    test "transcription en échec : les sous-titres suffisent" do
      Application.put_env(:quotor, :fake_transcript, {:error, "whisper-cli (code 1) : boom"})

      {:ok, source, quotes} = ingest("https://youtu.be/asrerrxxxxx")

      assert %{status: "cutting", text_origin: "subtitles", asr_status: "failed"} = source
      assert quotes != []
      assert Enum.all?(quotes, &is_nil(&1.asr_score))
    end

    @tag :ffmpeg
    test "transcription en échec sans sous-titres : nouvel essai" do
      Application.put_env(
        :quotor,
        :fake_transcript,
        {:error, "téléchargement du modèle : HTTP 503"}
      )

      assert {{:error, "téléchargement du modèle" <> _}, %{status: "failed"}, []} =
               ingest("https://www.youtube.com/watch?v=nosubsasr02")
    end
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

  test "historique : une vidéo supprimée n'est pas réimportée par la synchronisation" do
    {:ok, channel} =
      Catalog.create_channel(%{
        name: "Test",
        url: "https://www.youtube.com/@test",
        enabled: true,
        max_videos: 2
      })

    assert {:ok, 2} = Ingest.sync_channel(channel)
    [source | _] = Catalog.list_sources()

    history = Catalog.get_video_history(source.youtube_id)
    assert %{status: "pending", channel_id: channel_id} = history
    assert channel_id == channel.id

    # analysée puis supprimée : elle reste dans l'historique
    {:ok, source} = Catalog.update_source(source, %{status: "ready"})

    assert %{status: "ready", analyzed_at: %DateTime{}} =
             Catalog.get_video_history(source.youtube_id)

    {:ok, _} = Catalog.delete_source(source)

    assert %{status: "deleted", source_id: nil, removed_at: %DateTime{}} =
             Catalog.get_video_history(source.youtube_id)

    assert {:ok, 0} = Ingest.sync_channel(channel)
    assert Catalog.get_source_by_youtube_id(source.youtube_id) == nil

    # une vidéo encore au catalogue ne peut pas être oubliée
    [other] = Catalog.list_sources()

    assert {:error, :still_in_catalog} =
             Catalog.forget_video(Catalog.get_video_history(other.youtube_id))

    # « oubliée » : la synchronisation suivante la reprend
    {:ok, _} = Catalog.forget_video(Catalog.get_video_history(source.youtube_id))
    assert {:ok, 1} = Ingest.sync_channel(channel)
    assert %{status: "pending"} = Catalog.get_video_history(source.youtube_id)
  end

  test "historique : l'admin peut resoumettre à la main une vidéo supprimée" do
    {:ok, source} = Ingest.submit_youtube("https://youtu.be/histomanual", nil)
    {:ok, _} = Catalog.delete_source(source)
    assert Catalog.known_video?("histomanual")

    assert {:ok, again} = Ingest.submit_youtube("https://youtu.be/histomanual", nil)

    assert %{status: "pending", source_id: id, removed_at: nil} =
             Catalog.get_video_history("histomanual")

    assert id == again.id
  end

  describe "affinage des clips" do
    setup do
      previous = Application.get_env(:quotor, :transcription)
      Application.put_env(:quotor, :transcription, enabled: true, min_score: 0.75)

      on_exit(fn ->
        Application.put_env(:quotor, :transcription, previous)
        Application.delete_env(:quotor, :fake_transcript)
        Application.delete_env(:quotor, :fake_clip_transcript)
      end)

      # la vidéo entière : conforme aux sous-titres
      Application.put_env(:quotor, :fake_transcript, [])
    end

    defp ingest_and_cut(url) do
      {:ok, source} = Ingest.submit_youtube(url, nil)
      :ok = perform_job(IngestSource, %{source_id: source.id})
      result = perform_job(CutSource, %{source_id: source.id})
      {result, Catalog.get_source!(source.id), Catalog.list_quotes_for_source(source.id)}
    end

    @tag :ffmpeg
    test "clips complets et fiables : publiés" do
      {:ok, source, quotes} = ingest_and_cut("https://youtu.be/refineokxxx")

      assert source.status == "ready"
      assert quotes != []
      assert Enum.all?(quotes, &(&1.status == "ready" and &1.asr_score == 1.0))
      assert Enum.all?(quotes, &Catalog.get_public_quote(&1.id))
    end

    @tag :ffmpeg
    test "premier mot coupé : clip élargi puis publié" do
      Application.put_env(:quotor, :fake_clip_transcript, fn quote, duration ->
        words = Quotor.FakeTranscriber.echo(quote, duration)
        original = quote.clip_end_ms - quote.clip_start_ms
        # tant que le clip n'est pas élargi, son premier mot est inaudible
        if duration <= original + 100, do: tl(words), else: words
      end)

      {:ok, _source, quotes} = ingest_and_cut("https://youtu.be/refinewidex")

      second = Enum.find(quotes, &(&1.start_ms > 3000))
      assert second.status == "ready"
      # marge normale : 350 ms ; élargi de 500 ms en plus
      assert second.clip_start_ms < second.start_ms - 350
      # jamais avant la fin de la phrase précédente
      first = Enum.find(quotes, &(&1.start_ms < 3000))
      assert second.clip_start_ms >= first.end_ms
    end

    @tag :ffmpeg
    test "clip peu fiable : non publié, à vérifier, puis validé par un admin" do
      Application.put_env(:quotor, :fake_clip_transcript, fn quote, duration ->
        if String.starts_with?(quote.norm, "aujourd"),
          do: [{"autre", 300, 600}, {"chose", 600, 900}],
          else: Quotor.FakeTranscriber.echo(quote, duration)
      end)

      {:ok, source, quotes} = ingest_and_cut("https://youtu.be/refinelowxx")

      assert source.status == "ready"
      {doubtful, fine} = Enum.split_with(quotes, &String.starts_with?(&1.norm, "aujourd"))
      assert [%{status: "review", asr_score: score} = q] = doubtful
      assert score < 0.75
      assert q.clip_path
      assert Enum.all?(fine, &(&1.status == "ready"))

      # invisible au public tant qu'il n'est pas validé
      assert Catalog.get_public_quote(q.id) == nil
      assert Catalog.count_quotes_to_review() == 1

      {:ok, _} = Catalog.mark_quote_reviewed(q)
      assert %{status: "ready"} = Catalog.get_public_quote(q.id)
    end

    @tag :ffmpeg
    test "transcription d'un clip en échec : clip gardé, à vérifier" do
      Application.put_env(:quotor, :fake_clip_transcript, fn _, _ -> {:error, "boom"} end)

      {:ok, _source, quotes} = ingest_and_cut("https://youtu.be/refineerrxx")

      assert Enum.all?(quotes, &(&1.status == "review" and &1.asr_score == 0.0))
    end
  end

  describe "contrôle des montages à l'écoute" do
    setup do
      previous = Application.get_env(:quotor, :transcription)
      Application.put_env(:quotor, :transcription, enabled: true, min_score: 0.75)
      Application.put_env(:quotor, :fake_transcript, [])

      on_exit(fn ->
        Application.put_env(:quotor, :transcription, previous)
        Application.delete_env(:quotor, :fake_transcript)
        Application.delete_env(:quotor, :fake_clip_transcript)
      end)

      # deux vidéos identiques : chaque expression existe dans deux extraits
      sources =
        for url <- ["https://youtu.be/checkaaaaaa", "https://youtu.be/checkbbbbbb"] do
          {:ok, source} = Ingest.submit_youtube(url, nil)
          :ok = perform_job(IngestSource, %{source_id: source.id})
          :ok = perform_job(CutSource, %{source_id: source.id})
          source
        end

      %{sources: sources}
    end

    defp quote_source(quote_id), do: Catalog.get_quote!(quote_id).source_id

    @tag :ffmpeg
    test "montage correct : vérifié, aucun mot douteux" do
      assert {:ok, m} = Montages.build("bonjour on teste un jeu pourri", nil)
      assert m.asr_score == 1.0
      assert m.doubtful == []
      assert m.plan_key
    end

    @tag :ffmpeg
    test "morceau inaudible : remplacé par le même passage d'un autre extrait", %{
      sources: [a, b]
    } do
      Application.put_env(:quotor, :fake_clip_transcript, fn quote, duration ->
        if quote.source_id == a.id, do: [], else: Quotor.FakeTranscriber.echo(quote, duration)
      end)

      assert {:ok, m} = Montages.build("bonjour on teste un jeu pourri", nil)
      assert m.asr_score == 1.0
      assert Enum.all?(m.segments, &(quote_source(&1["quote_id"]) == b.id))
    end

    @tag :ffmpeg
    test "aucun extrait ne dit le mot : livré, avec le mot signalé" do
      Application.put_env(:quotor, :fake_clip_transcript, fn quote, duration ->
        quote |> Quotor.FakeTranscriber.echo(duration) |> Enum.reject(&(elem(&1, 0) == "bonjour"))
      end)

      assert {:ok, m} = Montages.build("bonjour on teste un jeu pourri", nil)
      assert m.status == "ready"
      assert m.doubtful == ["bonjour"]
      assert m.asr_score < 1.0
    end

    @tag :ffmpeg
    test "mot coupé par la découpe : morceau recalé sur la parole" do
      plan = Quotor.Search.plan("on teste un jeu pourri")
      [seg] = plan.segments

      # la parole commence dès le début de l'audio écouté (0,4 s avant le morceau)
      Application.put_env(:quotor, :fake_clip_transcript, fn _quote, _duration ->
        [
          {"on", 0, 200},
          {"teste", 200, 500},
          {"un", 500, 600},
          {"jeu", 600, 800},
          {"pourri", 800, 1200}
        ]
      end)

      assert {:ok, m} = Montages.build("on teste un jeu pourri", nil)
      [checked] = m.segments
      original_offset = seg.from_ms - seg.clip_start_ms
      assert checked["offset_ms"] < original_offset
      assert checked["offset_ms"] >= original_offset - 250
    end

    @tag :ffmpeg
    test "plan déjà contrôlé : servi sans nouvelle écoute" do
      assert {:ok, m} = Montages.build("on teste un jeu pourri", nil)

      Application.put_env(:quotor, :fake_clip_transcript, fn _, _ ->
        raise "ne doit pas être réécouté"
      end)

      assert {:ok, again} = Montages.build("On teste un jeu pourri !", nil)
      assert again.id == m.id
    end

    @tag :ffmpeg
    test "sans transcription : montage livré sans contrôle" do
      Application.put_env(:quotor, :transcription, enabled: false, min_score: 0.75)
      assert {:ok, m} = Montages.build("teste un jeu", nil)
      assert m.asr_score == nil
    end
  end
end
