# Données de démonstration (dev uniquement) : `mix run priv/repo/demo.exs`
#
# Génère avec ffmpeg trois fausses vidéos « cartons » (répliques originales,
# aucun contenu tiers) avec leurs sous-titres, les fait passer par le vrai
# pipeline d'ingestion (Oban), puis crée un utilisateur, des favoris, un
# montage et un signalement. Utilisé pour les captures d'écran du README.

alias Quotor.{Accounts, Catalog, Ingest, Media, Montages, Repo}
alias Quotor.Accounts.Scope

if Mix.env() != :dev, do: raise("demo.exs est réservé à l'environnement de développement")

font = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
unless File.exists?(font), do: raise("police introuvable : #{font} (paquet fonts-dejavu-core)")

admin =
  case Accounts.get_user_by_email("admin@quotor.local") do
    nil -> elem(Accounts.ensure_admin("admin@quotor.local", "quotor-admin-dev"), 1)
    user -> user
  end

admin_scope = Scope.for_user(admin)

demo_user =
  Accounts.get_user_by_email("demo@quotor.local") ||
    elem(
      Accounts.register_user_with_password(%{
        email: "demo@quotor.local",
        password: "quotor-demo-pass"
      }),
      1
    )

user_scope = Scope.for_user(demo_user)

sources = [
  %{
    title: "Démo — Le testeur de jeux pourris",
    uploader: "Chaîne démo Alpha",
    color: "0x1d3557",
    freq: 220,
    lines: [
      "Bonjour à tous et bienvenue dans cette vidéo.",
      "Aujourd'hui on va tester un jeu complètement nul.",
      "Franchement, je n'en peux plus de ce jeu.",
      "Le pire, c'est que j'ai payé pour ça.",
      "On se retrouve la semaine prochaine !"
    ]
  },
  %{
    title: "Démo — Une soirée qui tourne mal",
    uploader: "Chaîne démo Bravo",
    color: "0x6a040f",
    freq: 330,
    lines: [
      "Bref, j'ai organisé une soirée.",
      "Je ne suis pas venu ici pour rigoler.",
      "C'est la meilleure idée de la journée.",
      "Personne n'a compris ce qui se passait.",
      "Et là, tout le monde est parti."
    ]
  },
  %{
    title: "Démo — Critique de cinéma",
    uploader: "Chaîne démo Charlie",
    color: "0x2d6a4f",
    freq: 440,
    lines: [
      "Ce film est une véritable catastrophe.",
      "Mais je vais quand même vous en parler.",
      "Il y a une idée géniale dans ce film.",
      "Bonjour la subtilité !",
      "Merci d'avoir regardé, à bientôt."
    ]
  }
]

wrap = fn text ->
  text
  |> String.split(" ")
  |> Enum.reduce([""], fn word, [line | rest] ->
    if String.length(line) + String.length(word) > 26 and line != "",
      do: [word, line | rest],
      else: [String.trim(line <> " " <> word) | rest]
  end)
  |> Enum.reverse()
  |> Enum.join("\n")
end

ts = fn ms ->
  :io_lib.format("~2..0B:~2..0B:~2..0B,~3..0B", [
    div(ms, 3_600_000),
    div(rem(ms, 3_600_000), 60_000),
    div(rem(ms, 60_000), 1000),
    rem(ms, 1000)
  ])
  |> to_string()
end

for src <- sources, is_nil(Repo.get_by(Catalog.Source, title: src.title)) do
  dir = Media.tmp_dir!("demo-#{System.unique_integer([:positive])}")
  duration = length(src.lines) * 3

  srt =
    src.lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, i} ->
      "#{i + 1}\n#{ts.(i * 3000 + 300)} --> #{ts.(i * 3000 + 2700)}\n#{line}\n"
    end)

  File.write!(Path.join(dir, "video.srt"), srt)

  texts =
    src.lines
    |> Enum.with_index()
    |> Enum.map_join(",", fn {line, i} ->
      file = Path.join(dir, "t#{i}.txt")
      File.write!(file, wrap.(line))

      "drawtext=fontfile=#{font}:textfile=#{file}:fontcolor=white:fontsize=40:line_spacing=10:" <>
        "x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,#{i * 3},#{i * 3 + 3})'"
    end)

  File.write!(Path.join(dir, "uploader.txt"), src.uploader)

  filter =
    "[0:v]#{texts},drawtext=fontfile=#{font}:textfile=#{Path.join(dir, "uploader.txt")}:" <>
      "fontcolor=white@0.6:fontsize=22:x=w-text_w-30:y=30[v]"

  video = Path.join(dir, "video.mp4")

  {out, 0} =
    System.cmd(
      "ffmpeg",
      [
        "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "color=c=#{src.color}:s=854x480:r=25:d=#{duration}",
        "-f", "lavfi", "-i", "sine=frequency=#{src.freq}:duration=#{duration}",
        "-filter_complex", filter, "-map", "[v]", "-map", "1:a",
        "-af", "volume=0.15",
        "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest", video
      ],
      stderr_to_stdout: true
    )

  IO.write(out)

  {:ok, source} =
    Ingest.submit_upload(
      %{"title" => src.title, "uploader" => src.uploader},
      video,
      Path.join(dir, "video.srt"),
      admin_scope
    )

  IO.puts("source #{source.id} envoyée : #{src.title}")
end

# Attendre la fin du traitement par Oban
Enum.reduce_while(1..120, nil, fn _, _ ->
  counts = Catalog.count_sources_by_status()
  pending = Map.drop(counts, ["ready", "failed"]) |> Map.values() |> Enum.sum()

  if pending == 0 do
    {:halt, :ok}
  else
    Process.sleep(1000)
    {:cont, nil}
  end
end)

IO.puts("sources : #{inspect(Catalog.count_sources_by_status())}")

# Une vidéo en échec, pour illustrer la supervision
unless Repo.get_by(Catalog.Source, youtube_id: "demoFAILxyz") do
  {:ok, failed} =
    Catalog.create_youtube_source(%{
      url: "https://www.youtube.com/watch?v=demoFAILxyz",
      title: "Démo — vidéo sans sous-titres"
    })

  Catalog.update_source(failed, %{status: "failed", error: "Aucun sous-titre français disponible"})
end

# Favoris, montage et signalement
quotes = Quotor.Search.search("bonjour") ++ Quotor.Search.search("soirée")
Enum.each(quotes, &Catalog.toggle_favorite(user_scope, &1.id))

{:ok, montage} = Montages.build("Bonjour à tous, je ne suis pas venu ici pour ce film", user_scope)
IO.puts("montage : /m/#{montage.key}")

if Catalog.count_open_reports() == 0 do
  [q | _] = Quotor.Search.search("catastrophe")

  Catalog.create_report(%{
    reason: "copyright",
    message: "Je suis l'auteur de cette vidéo et je souhaite son retrait.",
    contact_name: "Auteur Démo",
    contact_email: "auteur@example.com",
    quote_id: q.id,
    source_id: q.source_id
  })
end

IO.puts("démo prête : admin@quotor.local / quotor-admin-dev — demo@quotor.local / quotor-demo-pass")
