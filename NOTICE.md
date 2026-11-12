# Composants tiers

Quotor (© 2026 Antoine Gamain, tous droits réservés — voir [LICENSE](LICENSE)) utilise les
composants open source suivants. Chacun reste soumis à sa propre licence ; ces licences ne
s'étendent pas au code de Quotor, et la licence de Quotor ne s'applique pas à eux.

## Principales dépendances

| Composant | Rôle | Licence |
| --- | --- | --- |
| [Elixir](https://elixir-lang.org) / Erlang/OTP | langage et machine virtuelle | Apache-2.0 |
| [Phoenix](https://www.phoenixframework.org), Phoenix LiveView | framework web | MIT |
| [Ecto](https://github.com/elixir-ecto/ecto), Postgrex | accès à la base de données | Apache-2.0 |
| [Oban](https://github.com/oban-bg/oban), Oban Web | tâches de fond | Apache-2.0 |
| [Bandit](https://github.com/mtrudel/bandit) | serveur HTTP | MIT |
| [Tailwind CSS](https://tailwindcss.com), [daisyUI](https://daisyui.com) | styles | MIT |
| [Heroicons](https://heroicons.com) | icônes | MIT |
| [PostgreSQL](https://www.postgresql.org) | base de données (image Docker) | PostgreSQL License |
| [FFmpeg](https://ffmpeg.org) | découpe et montage vidéo (image Docker, paquet Debian) | LGPL-2.1+ / GPL-2.0+ |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | téléchargement des vidéos (image Docker) | Unlicense |

Les autres dépendances Elixir (Swoosh, Req, Jason, bcrypt_elixir, gen_smtp, telemetry…) sont
distribuées sous licences permissives (MIT, Apache-2.0, BSD). La liste exacte et les versions
figurent dans `mix.lock` ; le texte de chaque licence se trouve dans `deps/<nom>/` après
`mix deps.get`.

Le squelette initial du projet a été généré avec les générateurs de Phoenix (`mix phx.new`,
`mix phx.gen.auth`), dont le code produit peut être librement réutilisé.
