# Les tests marqués :ffmpeg (découpe réelle de vidéos) sont exclus si ffmpeg
# n'est pas installé sur la machine, de même que :pg_dump (sauvegardes réelles
# de la base) sans client PostgreSQL.
exclude =
  for {tag, exe} <- [ffmpeg: "ffmpeg", pg_dump: "pg_dump"], !System.find_executable(exe), do: tag

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Quotor.Repo, :manual)
