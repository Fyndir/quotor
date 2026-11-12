# Les tests marqués :ffmpeg (découpe réelle de vidéos) sont exclus si ffmpeg
# n'est pas installé sur la machine.
exclude = if System.find_executable("ffmpeg"), do: [], else: [:ffmpeg]

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Quotor.Repo, :manual)
