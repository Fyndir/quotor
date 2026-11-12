# Données initiales : `mix run priv/repo/seeds.exs` (appelé par `mix ecto.setup`).
# En production, c'est `Quotor.Release.setup/0` qui s'en charge au démarrage.

# En développement, un admin par défaut si ADMIN_EMAIL n'est pas défini.
if Mix.env() == :dev and System.get_env("ADMIN_EMAIL") in [nil, ""] do
  System.put_env("ADMIN_EMAIL", "admin@quotor.local")
  System.put_env("ADMIN_PASSWORD", "quotor-admin-dev")
  IO.puts("Admin de dev : admin@quotor.local / quotor-admin-dev")
end

Quotor.Seeds.run()
