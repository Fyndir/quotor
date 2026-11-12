# Quotor

> Trouve **la** réplique. Des extraits vidéo **avec le son**, des vidéastes français, façon Giphy —
> et un mode montage pour leur faire dire n'importe quoi.

![Accueil de Quotor](docs/screenshots/accueil.png)

Quotor découpe des vidéos (YouTube ou fichiers fournis par un admin) en courtes répliques, les
« quotes », grâce à leurs sous-titres. On les retrouve en tapant une phrase, on les partage (Discord
compris), et on peut assembler plusieurs extraits pour composer une phrase qui n'a jamais été dite.

**Stack** : Elixir 1.19 · Phoenix 1.8 (LiveView) · PostgreSQL · Oban · ffmpeg · yt-dlp · Docker.

**Auteur** : concept, design et code © 2026 **Antoine Gamain** — tous droits réservés
([LICENSE](LICENSE)). Voir [Auteur et propriété](#auteur-et-propriété).

> Les captures ci-dessous utilisent les **données de démonstration** (`priv/repo/demo.exs`) : des
> vidéos « cartons » générées par ffmpeg avec des répliques originales, aucun contenu tiers.

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Démarrage rapide](#démarrage-rapide)
- [Déploiement](#déploiement)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Tests et CI](#tests-et-ci)
- [Limites connues](#limites-connues)
- [Droit d'auteur des contenus](#droit-dauteur-des-contenus)
- [Auteur et propriété](#auteur-et-propriété)

---

## Fonctionnalités

### Accueil : la recherche, et rien d'autre

La page d'accueil est volontairement dépouillée : un champ de recherche, le choix du mode
(standard ou montage) et un lien vers l'onglet **Découvrir** pour qui n'a pas d'idée. Aucun extrait
n'est chargé tant qu'on n'a rien cherché.

### Recherche standard

On tape une phrase, Quotor renvoie les extraits où elle est prononcée. La recherche ignore la casse,
les accents et la ponctuation, tolère les fautes de frappe, et classe l'expression exacte en
premier. Cliquer sur une carte lit l'extrait **avec le son**.

![Résultats de recherche](docs/screenshots/recherche.png)

### Onglet Découvrir

Accessible à tous depuis l'en-tête (`/decouvrir`), il permet de parcourir le catalogue sans
chercher, selon trois tris :

- **Au hasard**, avec un bouton « Mélanger » ;
- **Nouveautés** ;
- **Populaires**, d'après le nombre de vues.

Les nouveautés et les populaires se chargent 24 par 24 (« Voir plus »). Les utilisateurs connectés
peuvent y mettre des extraits en favori.

![Onglet Découvrir](docs/screenshots/decouvrir.png)

### Mode avancé : le montage

On tape n'importe quelle phrase. Quotor la découpe en **plus longs morceaux possibles** trouvés dans
le catalogue (au mot près), puis les assemble en une seule vidéo. Les morceaux utilisés sont
affichés (chaque pastille renvoie vers l'extrait d'origine), les mots introuvables sont signalés, et
« Autre version » propose d'autres extraits. Les montages sont mis en cache et ont une page
partageable.

![Montage partageable](docs/screenshots/montage-partage.png)

### Page d'un extrait et partage

Chaque extrait indique **qui parle**, la **chaîne** qui a publié la vidéo (avec un lien vers elle)
et la **source** (titre de la vidéo, instant, date de publication), et renvoie vers **l'original à
l'instant exact**. Les liens
`/q/…` et `/m/…` contiennent des balises Open Graph : collés dans **Discord**, ils s'affichent avec
un lecteur vidéo. Un second bouton copie le lien direct du `.mp4`.

![Page d'un extrait](docs/screenshots/extrait.png)

### Auteurs

Chaque réplique est attribuée à un **auteur** : la **personne** qui parle ou, à défaut, la
**chaîne** YouTube qui a publié la vidéo.

- **Attribution automatique** : à l'ingestion, chaque vidéo est rattachée à sa chaîne, créée comme
  auteur de type « chaîne » avec son lien.
- **Deux niveaux d'attribution** : l'admin peut désigner l'auteur d'une **vidéo entière**
  (« toute cette vidéo est dite par X »), ou d'une **réplique précise**, ce qui est prioritaire.
- **Partout dans l'interface** : l'auteur apparaît sur chaque carte et sur la page de l'extrait,
  ainsi que dans le titre de l'aperçu Discord.
- **Pages publiques** : `/auteurs` liste les auteurs avec leur nombre de répliques, et chaque
  auteur a sa page (`/auteurs/<nom>`) avec ses répliques, les plus vues d'abord.
- **Recherche** : taper le nom d'un auteur propose un lien direct vers sa page.

<p>
  <img src="docs/screenshots/auteurs.png" alt="Liste des auteurs" width="49%" />
  <img src="docs/screenshots/auteur.png" alt="Page d'un auteur" width="49%" />
</p>

### Trois profils

| Profil          | Ce qu'il peut faire                                                                  |
| --------------- | ------------------------------------------------------------------------------------ |
| **Anonyme**     | recherche, onglet Découvrir, pages auteurs, montages, pages d'extraits et de montages, partage, signalement |
| **Utilisateur** | en plus : **favoris**, historique « **Mes montages** », paramètres du compte         |
| **Admin**       | en plus : back-office `/admin` (voir ci-dessous), Oban Web, Phoenix LiveDashboard     |

L'inscription se fait par email + mot de passe. L'interface est responsive, en thème clair ou sombre.

<p>
  <img src="docs/screenshots/mobile-recherche.png" alt="Recherche sur mobile" width="260" />
  <img src="docs/screenshots/mobile-favoris.png" alt="Favoris sur mobile" width="260" />
</p>

### Back-office admin

**Supervision** : état de la base (latence, taille), mémoire et processus, présence de ffmpeg et
yt-dlp, files de tâches et derniers échecs (avec relance), compteurs du catalogue, erreurs de la
dernière heure, signalements en attente, espace disque des médias. Actualisation toutes les 5 s.

![Supervision](docs/screenshots/admin-supervision.png)

**Vidéos sources** : l'admin ajoute des URLs YouTube particulières (plusieurs à la fois) ou envoie
un fichier vidéo avec ses sous-titres. Il suit le traitement en direct, relance, masque ou supprime
une vidéo. Les **chaînes suivies** (JDG, Cyprien, Bref, Chroma pré-enregistrées, désactivées par
défaut) sont synchronisées chaque nuit.

![Vidéos sources](docs/screenshots/admin-sources.png)

**Auteurs** : l'admin crée et modifie les auteurs (nom, type personne ou chaîne, lien,
description), puis les attribue à une vidéo depuis « Vidéos sources » (colonne *Auteur*, ou à
l'envoi d'un fichier), ou à une réplique précise depuis « Quotes ».

![Gestion des auteurs](docs/screenshots/admin-auteurs.png)

**Signalements** : les demandes de retrait (formulaire public `/signaler`, présent sous chaque
extrait) se traitent en un clic : masquer l'extrait, masquer toute la vidéo, marquer traité, rejeter.
Les pages **Quotes** (corriger un texte, masquer) et **Utilisateurs** (promouvoir admin, bannir)
complètent la modération.

![Signalements](docs/screenshots/admin-signalements.png)

**Logs** : les 2 000 derniers événements en mémoire, filtrables par niveau et par texte, en direct.
Les logs complets partent sur la sortie standard (Docker / Render).

![Logs](docs/screenshots/admin-logs.png)

### Pages légales

Mentions légales (propriété de l'application, LCEN, hébergeurs, RGPD, cookies), conditions
d'utilisation (exception de parodie, droit moral, procédure de retrait, propriété de Quotor) et, en
pied de page, le copyright de l'application et la mention sur les extraits.

![Mentions légales](docs/screenshots/mentions-legales.png)

---

## Démarrage rapide

### Développement (seul Docker est nécessaire)

```bash
docker compose -f docker-compose.dev.yml up            # http://localhost:4000
```

- Admin de développement : `admin@quotor.local` / `quotor-admin-dev`.
- PostgreSQL de dev exposé sur le port **5433**.

Données de démonstration (3 vidéos, 15 extraits, un montage, un signalement, un utilisateur
`demo@quotor.local` / `quotor-demo-pass`) :

```bash
docker compose -f docker-compose.dev.yml exec app mix run priv/repo/demo.exs
```

Tests :

```bash
docker compose -f docker-compose.dev.yml run --rm app mix test
```

Avec Elixir installé localement (et ffmpeg, yt-dlp, PostgreSQL) : `mix setup && mix phx.server`.

### Image de production en local

```bash
docker build -t quotor .
docker run -p 4000:4000 -v quotor_data:/data \
  -e ADMIN_EMAIL=admin@example.com -e ADMIN_PASSWORD='un-mot-de-passe-long' \
  quotor
```

Sans `DATABASE_URL`, l'image **initialise et démarre son propre PostgreSQL** (dans
`/data/postgres`) et génère `SECRET_KEY_BASE` (conservé dans `/data`). Tout est persistant tant que
le volume `/data` est conservé. Accédez-y via `http://localhost:4000` : les autres hôtes sont
redirigés en HTTPS.

---

## Déploiement

### 1. GitHub et CI

```bash
git add . && git commit -m "Quotor"
git remote add origin git@github.com:<compte>/quotor.git
git push -u origin main
```

La CI (`.github/workflows/ci.yml`) se lance à chaque push et pull request :

- compilation sans avertissement ;
- formatage ;
- tests, avec PostgreSQL 17 et ffmpeg ;
- build de l'image Docker.

### 2. Base de données Neon

1. Créez un projet sur [neon.tech](https://neon.tech), de préférence en région UE (Francfort).
2. Copiez la chaîne de connexion **directe**, avec un hôte **sans** `-pooler`, par exemple :
   `postgresql://user:pass@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require`

TLS (avec vérification du certificat) est activé automatiquement grâce à `sslmode=require`. Si vous
utilisez l'hôte `-pooler`, ajoutez `DATABASE_POOLER=true`. Les extensions nécessaires (`citext`,
`pg_trgm`) sont créées par les migrations.

### 3. Application sur Render

1. Dashboard Render → **New → Blueprint** → sélectionnez le dépôt : `render.yaml` décrit le service
   (Docker, région Francfort, health check `/health`, disque persistant de 10 Go).
2. Renseignez les variables demandées :
   - `DATABASE_URL` (Neon) ;
   - `ADMIN_EMAIL` et `ADMIN_PASSWORD` (12 caractères minimum) ;
   - `LEGAL_EDITOR_NAME`, `LEGAL_EDITOR_ADDRESS`, `LEGAL_CONTACT_EMAIL`, `LEGAL_PUBLICATION_DIRECTOR`.

   `SECRET_KEY_BASE` est généré par Render, et `PHX_HOST` est déduit de l'URL Render.
3. Déployez. À chaque démarrage, l'image exécute les migrations, crée ou promeut l'admin, puis lance
   l'application.
4. *(Recommandé)* Si YouTube bloque les téléchargements (voir [limites](#limites-connues)) :
   1. exportez un `cookies.txt` d'un compte YouTube ;
   2. ajoutez-le comme **Secret File** Render ;
   3. définissez `YTDLP_COOKIES=/etc/secrets/cookies.txt`.
5. *(Domaine personnalisé)* Ajoutez-le dans Render et définissez `PHX_HOST=quotor.example.fr`.

> **Offre gratuite Render** : supprimez le bloc `disk` du `render.yaml` et passez à `plan: free`.
> Les clips seront alors perdus à chaque redéploiement ou redémarrage.

### 4. Premiers pas en production

1. Connectez-vous avec `ADMIN_EMAIL`, puis ouvrez **Admin → Supervision** : ffmpeg et yt-dlp doivent
   être détectés.
2. **Admin → Vidéos sources** : collez quelques URLs YouTube ayant des sous-titres français. Suivez
   leur passage par les statuts *téléchargement*, *découpe* puis *prête*.
3. **Admin → Chaînes suivies** : vérifiez l'URL de chaque chaîne, ajustez le nombre de vidéos, puis
   activez-la.

---

## Configuration

| Variable | Description | Défaut |
| --- | --- | --- |
| `DATABASE_URL` | URL PostgreSQL (`sslmode=require` active TLS) | base interne au conteneur |
| `DATABASE_SSL` | force TLS | `false` |
| `DATABASE_POOLER` | `true` derrière PgBouncer / pooler Neon | `false` |
| `POOL_SIZE` | connexions à la base | `10` |
| `SECRET_KEY_BASE` | clé de signature (`mix phx.gen.secret`) | générée dans `/data` |
| `PHX_HOST` | nom d'hôte public | `RENDER_EXTERNAL_HOSTNAME`, sinon `localhost` |
| `PORT` | port HTTP | `4000` |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | admin créé ou promu au démarrage (≥ 12 caractères) | – |
| `MEDIA_DIR` | dossier des médias | `/data/media` |
| `KEEP_SOURCES` | conserver les vidéos sources après découpe | `false` |
| `YTDLP_PATH` / `YTDLP_COOKIES` / `YTDLP_EXTRA_ARGS` | options de yt-dlp | – |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` | emails (liens de connexion, changement d'email) ; sans SMTP, ils sont seulement journalisés | – |
| `LEGAL_EDITOR_NAME`, `LEGAL_EDITOR_ADDRESS`, `LEGAL_CONTACT_EMAIL`, `LEGAL_PUBLICATION_DIRECTOR` | contenu des mentions légales | valeurs à remplacer |
| `LOG_LEVEL` | `debug`, `info`, `warning`, `error` | `info` |

---

## Architecture

```
Admin : URL YouTube / fichier          Cron 04:00 UTC : chaînes suivies activées
              │                                         │
              └──────────────┬──────────────────────────┘
                             ▼
   IngestSource  (file Oban "ingest", 1 à la fois)
     yt-dlp : vidéo ≤ 480p + sous-titres FR (manuels, sinon automatiques)
     → analyse VTT/SRT, découpage en phrases, mots horodatés
                             ▼
   CutSource  (file "media", 2 en parallèle)
     ffmpeg : un clip mp4 (H.264/AAC) + une vignette par quote
     → la vidéo source est ensuite supprimée
                             ▼
   Recherche plein texte Postgres (tsvector « simple » + pg_trgm)
   Montage : plan glouton sur les mots horodatés → ffmpeg concat
```

| Dossier | Contenu |
| --- | --- |
| `lib/quotor/catalog/` | schémas : sources, quotes, mots horodatés, auteurs, favoris, signalements |
| `lib/quotor/ingest/` | téléchargement (yt-dlp), analyse des sous-titres, segmentation |
| `lib/quotor/search.ex` | recherche standard et plan de montage |
| `lib/quotor/montages.ex` | rendu et cache des montages |
| `lib/quotor/workers/` | tâches Oban (ingestion, découpe, synchronisation des chaînes, nettoyage) |
| `lib/quotor/logs.ex`, `monitoring.ex` | buffer de logs, indicateurs de supervision |
| `lib/quotor_web/live/` | pages LiveView publiques et admin |
| `docker/entrypoint.sh` | PostgreSQL interne, secret, migrations, démarrage |

Les fichiers médias sont servis par `/media/…` avec prise en charge des requêtes `Range`
(nécessaire à la lecture vidéo sur Safari et iOS).

---

## Tests et CI

191 tests couvrent :

- l'analyse des sous-titres (y compris le format mot à mot de YouTube) et la segmentation ;
- la recherche et le plan de montage ;
- le catalogue ;
- le **pipeline complet** d'ingestion, avec un faux téléchargeur et une vraie découpe ffmpeg ;
- les auteurs (attribution automatique à la chaîne, priorité de l'auteur d'une réplique, pages
  publiques, gestion admin) ;
- l'accueil, l'onglet Découvrir (tris, favoris) et le contrôle d'accès des trois profils ;
- les mentions de propriété (pied de page, mentions légales) ;
- les pages légales et les balises Discord ;
- le service des médias ;
- les logs.

Les tests marqués `:ffmpeg` sont ignorés si ffmpeg est absent.

Les captures du README se régénèrent avec `scripts/screenshots.mjs` (Playwright, instructions en tête
du fichier).

---

## Limites connues

### Alimentation du catalogue

- **YouTube bloque souvent les IP de datacenters** (« Sign in to confirm you're not a bot ») : sur
  Render, les téléchargements peuvent échouer sans cookies (`YTDLP_COOKIES`). Télécharger depuis
  YouTube est aussi contraire à ses conditions d'utilisation.
- **yt-dlp est figé au moment du build** de l'image. Quand YouTube change, il faut reconstruire
  l'image pour obtenir une version récente.
- **Des sous-titres français sont obligatoires** : il n'y a pas de transcription automatique
  (Whisper, par exemple). Une vidéo sans sous-titres passe en échec.
- **Les sous-titres automatiques** n'ont ni ponctuation ni majuscules et contiennent des erreurs de
  reconnaissance. Les textes des quotes peuvent être corrigés à la main dans l'admin.
- **Avec des sous-titres manuels**, le temps de chaque mot est interpolé : les montages sont moins
  précis qu'avec les sous-titres automatiques.

### Recherche et montage

- La recherche ne fait **pas de racinisation** (« mangé » ne trouve pas « manger ») et ne gère pas
  les synonymes. Elle est conçue pour le français uniquement.
- Le plan de montage est **glouton** (plus long morceau d'abord), donc pas toujours optimal. Les
  pastilles affichent le texte normalisé (sans accents).
- Le rendu d'un montage se fait **pendant la requête**, ce qui consomme du CPU : quelques centaines
  de ms en démo, plusieurs secondes sur une petite instance. Il est limité à 20 montages par
  10 minutes par utilisateur ou IP.
- Les montages anonymes sont supprimés après 7 jours.

### Hébergement et exploitation

- **Stockage sur disque local** : il faut un disque persistant (offre payante Render). Il n'y a pas
  encore de stockage objet (S3/R2) ni de CDN.
- **Une seule instance** : médias sur disque, limiteur de débit et buffer de logs en mémoire. Pas de
  mise à l'échelle horizontale en l'état.
- **Neon** : Oban interroge la base en continu, ce qui l'empêche de se mettre en veille et consomme
  des heures de calcul.
- **Render gratuit** : le service s'endort après 15 min d'inactivité. La synchronisation nocturne
  des chaînes ne s'exécute pas s'il dort.
- **Logs** : le buffer admin est perdu au redémarrage, et il n'y a pas d'alerting externe (Sentry,
  Prometheus…).
- L'image Docker pèse environ 1,2 Go (ffmpeg et PostgreSQL inclus).
- En local, l'image de production n'est accessible que via `localhost` : `force_ssl` redirige les
  autres hôtes vers HTTPS.

### Comptes

- Les adresses email ne sont pas vérifiées à l'inscription.
- **Sans SMTP, pas de récupération de mot de passe** : la connexion par lien email sert de
  réinitialisation.

### Intégration Discord

- Elle nécessite une URL publique en HTTPS (un lien `localhost` ne s'intègre pas).
- Discord garde l'aperçu d'un lien en cache après le premier partage.

---

## Droit d'auteur des contenus

Les extraits restent la propriété de leurs auteurs. Quotor revendique un usage relevant de
l'exception de **parodie, pastiche et caricature** (art. L. 122-5, 4° CPI) :

- extraits courts, crédités et liés à l'original ;
- usage humoristique et non commercial ;
- procédure de retrait (formulaire `/signaler`, traitement dans `/admin/signalements`).

Cette exception couvre surtout les **montages** humoristiques. Une base qui découpe en masse le
catalogue de créateurs n'est pas, en elle-même, une parodie. Les textes de `/mentions-legales` et
`/conditions` sont un point de départ : **faites-les relire par un juriste** avant une ouverture au
public, et privilégiez l'accord des créateurs concernés.

---

## Auteur et propriété

**Quotor a été imaginé, conçu et développé par Antoine Gamain**, qui en est l'auteur et le seul
titulaire des droits. Cela couvre le concept de l'application (moteur de recherche d'extraits vidéo
sonores et montages à partir de ces extraits), son code source, son architecture, son interface, ses
textes, son nom et son logo.

© 2026 Antoine Gamain — **tous droits réservés**. Aucune licence d'utilisation n'est concédée : la
consultation de ce dépôt ne vaut pas autorisation de copier, modifier, redistribuer ou exploiter tout
ou partie du projet sans accord écrit préalable. Voir [LICENSE](LICENSE).

Ces mentions figurent aussi :

- dans le pied de page de toutes les pages ;
- dans les mentions légales (section « Propriété de l'application ») ;
- dans les conditions d'utilisation ;
- en tête de `mix.exs` et dans la documentation du module `Quotor`.

Le nom affiché est défini par `config :quotor, :owner` dans `config/config.exs`.

Les composants open source utilisés (Elixir, Phoenix, PostgreSQL, FFmpeg, yt-dlp…) restent régis par
leurs propres licences : voir [NOTICE.md](NOTICE.md).
