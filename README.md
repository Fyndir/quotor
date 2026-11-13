# Quotor

> Trouve **la** réplique. Des extraits vidéo **avec le son**, des vidéastes français, façon Giphy —
> et un mode montage pour leur faire dire n'importe quoi.

![Accueil de Quotor](docs/screenshots/accueil.png)

Quotor découpe des vidéos (YouTube ou fichiers fournis par un admin) en courtes répliques, les
« quotes », grâce à leurs sous-titres vérifiés par transcription vocale (ou à la seule
transcription quand il n'y a pas de sous-titres). On les retrouve en tapant une phrase, on les partage (Discord
compris), et on peut assembler plusieurs extraits pour composer une phrase qui n'a jamais été dite.

**Stack** : Elixir 1.19 · Phoenix 1.8 (LiveView) · PostgreSQL · Oban · ffmpeg · yt-dlp · whisper.cpp · Docker.

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
- [Sauvegardes](#sauvegardes)
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

Accessible à tous depuis l'en-tête (`/decouvrir`), il présente les **montages créés par les
utilisateurs**, et non les extraits bruts du catalogue, selon trois tris :

- **Au hasard**, avec un bouton « Mélanger » ;
- **Nouveautés** ;
- **Populaires**, d'après le nombre de vues de la page du montage.

Les nouveautés et les populaires se chargent 24 par 24 (« Voir plus »). Y figurent les montages
des utilisateurs connectés (les montages anonymes, purgés après 7 jours, n'y sont pas). Un
montage disparaît de Découvrir dès qu'un de ses extraits est masqué (signalement, retrait de la
vidéo…). Son auteur peut le retirer de Découvrir depuis la page du montage, le lien restant
partageable.

![Onglet Découvrir](docs/screenshots/decouvrir.png)

### Mode avancé : le montage

On tape n'importe quelle phrase. Quotor la découpe en **plus longs morceaux possibles** trouvés dans
le catalogue (au mot près), puis les assemble en une seule vidéo. Les morceaux utilisés sont
affichés (chaque pastille renvoie vers l'extrait d'origine), les mots introuvables sont signalés, et
« Autre version » propose d'autres extraits. Les montages sont mis en cache et ont une page
partageable, avec un bouton **Télécharger** (fichier `quotor-<phrase>.mp4`).

**Contrôle à l'écoute avant livraison** (si la transcription vocale est active sur le site) :
chaque morceau du montage est réécouté par whisper.cpp, avec 0,4 s de contexte. Tous les
morceaux sont mis bout à bout dans un seul fichier audio, transcrit en une passe. Ensuite :

- un mot coupé par la découpe fait recaler le morceau sur la parole (250 ms au plus) ;
- un morceau qui ne dit pas ses mots est remplacé par le même passage pris dans un autre extrait
  (deux essais au plus) ;
- le montage est livré avec son résultat (« vérifié à l'écoute », ou les mots restés douteux).

Un plan déjà contrôlé est resservi sans nouvelle écoute.

**Idées de phrases** : en mode avancé, le champ vide propose des phrases toutes faites, par
**greffe** de deux répliques publiées sur un mot commun. « Bonjour à tous, c'est… » plus « …c'est
que j'ai payé pour ça » donne « Bonjour à tous, c'est que j'ai payé pour ça ». Chaque moitié existe
dans un extrait affiné, donc l'idée est toujours montable. Les greffes entre vidéastes différents
passent en premier. Un clic lance le montage, et « Autres idées » en tire de nouvelles.

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
un fichier vidéo, avec ou sans sous-titres. Il suit le traitement en direct, relance, masque ou supprime
une vidéo. Les **chaînes suivies** (JDG, Cyprien, Bref, Chroma pré-enregistrées, désactivées par
défaut) sont synchronisées chaque nuit. Un **historique** garde la trace de chaque vidéo YouTube
soumise, même supprimée depuis : la synchronisation ne réimporte jamais une vidéo déjà vue. La
page **Historique** liste ces vidéos (analysées, en échec, supprimées) ; une vidéo supprimée peut
y être réanalysée tout de suite, ou « oubliée » pour que la synchronisation la reprenne.

![Vidéos sources](docs/screenshots/admin-sources.png)

**Transcription vocale (whisper.cpp)** : le worker transcrit l'audio de chaque vidéo et le compare
aux sous-titres, quote par quote :

- chaque quote reçoit un **score d'accord** entre son texte et ce qui est réellement dit ;
- ses **bornes sont recalées** sur la parole, avec une marge (0,35 s avant, 0,45 s après) qui
  ne déborde jamais sur la phrase voisine ;
- **affinage avant publication** : les clips découpés sont « bruts » et ne sont pas publiés. Chacun
  est réécouté (tous les clips d'une vidéo en un seul passage de whisper.cpp). S'il manque le
  premier ou le dernier mot, le clip est élargi de 0,5 s de ce côté et redécoupé, jusqu'à deux
  fois. Seuls les clips complets dont la **fiabilité** (part des mots entendus) atteint
  `TRANSCRIBE_MIN_SCORE` (75 %) sont publiés ;
- les autres sont **« à vérifier »** : **Quotes → À vérifier** les liste avec leur score, et l'admin
  les publie en un clic ou corrige le texte ;
- **une vidéo sans sous-titres** est traitée quand même : le texte vient de la transcription.

La page **Vidéos sources** indique d'où vient le texte de chaque vidéo (sous-titres vérifiés à la
voix, transcription seule…), et la supervision le moteur utilisé.

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

**Sauvegardes** : état des sauvegardes (planification, rétention, destination, dernier échec,
alerte si la dernière a plus de 36 h), lancement immédiat, téléchargement et suppression des
archives, et commande de restauration prête à copier. Voir [Sauvegardes](#sauvegardes).

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
- Les médias (clips, vignettes, montages) sont dans le volume Docker `quotor_media`, la base dans
  `quotor_pgdata_dev` : rien n'est perdu en recréant les conteneurs (`down`, `up --build`). Seul
  `docker compose … down -v` les supprime.

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
ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD='un-mot-de-passe-long' docker compose up -d --build
```

(équivalent sans compose : `docker run -p 4000:4000 -v quotor_data:/data -e ADMIN_EMAIL=… -e ADMIN_PASSWORD=… quotor`
— **ne pas oublier `-v`**, sinon les données vont dans un volume anonyme perdu à la recréation.)

Sans `DATABASE_URL`, l'image **initialise et démarre son propre PostgreSQL** (dans
`/data/postgres`) et génère `SECRET_KEY_BASE` (conservé dans `/data`). Base, extraits et montages
sont dans le volume nommé `quotor_data`, indépendant du conteneur : mises à jour et redémarrages ne
perdent rien. Sauvegarde :

```bash
docker run --rm -v quotor_data:/data -v "$PWD":/backup alpine tar czf /backup/quotor-data.tgz -C /data .
```

Accédez-y via `http://localhost:4000` : les autres hôtes sont
redirigés en HTTPS.

### Architecture de production en local (site + workers + S3)

```bash
docker compose -f docker-compose.roles.yml up --build              # http://localhost:4100
docker compose -f docker-compose.roles.yml up -d --scale worker=3  # 3 workers en parallèle
```

Lance PostgreSQL, un stockage S3 local (RustFS), le site (`ROLE=web`) et des workers
(`ROLE=worker`), comme en production. L'admin est `admin@quotor.local` / `quotor-admin-roles`.

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

### 3. Stockage des médias sur Cloudflare R2

Les clips, vignettes et montages sont stockés dans un bucket compatible S3. Le site et les workers
y accèdent tous les deux, et aucun disque persistant n'est nécessaire.

1. Dashboard Cloudflare → **R2** → **Create bucket**, nommé par exemple `quotor`.
2. **R2 → Manage API tokens → Create API token**, avec la permission **Object Read & Write**
   limitée à ce bucket. Notez :
   - l'**Access Key ID**, à mettre dans `S3_ACCESS_KEY_ID` ;
   - le **Secret Access Key**, à mettre dans `S3_SECRET_ACCESS_KEY` ;
   - l'endpoint `https://<ID-compte>.r2.cloudflarestorage.com`, à mettre dans `S3_ENDPOINT`.
3. Choisissez comment les vidéos sont servies :
   - **bucket public** (recommandé) : activez l'accès public (domaine `r2.dev` ou domaine
     personnalisé) et renseignez son URL dans `S3_PUBLIC_URL`. Les navigateurs et Discord lisent
     alors les vidéos directement sur R2, sans passer par le site ;
   - **bucket privé** : laissez `S3_PUBLIC_URL` vide. Le site relaie les fichiers sous `/media/…`.

4. Créez un **second bucket, privé**, pour les sauvegardes (`quotor-backups`, valeur par défaut
   de `BACKUP_S3_BUCKET` dans le blueprint) et étendez-lui le jeton. Ne le rendez jamais public :
   les sauvegardes contiennent la base, comptes compris.

Tout autre fournisseur compatible S3 convient (AWS S3, Scaleway…). Sans `S3_BUCKET`, Quotor
utilise le disque local (`MEDIA_DIR`).

### 4. Application sur Render : un site et un worker

1. Dashboard Render → **New → Blueprint** → sélectionnez le dépôt. `render.yaml` crée deux
   services à partir de la même image Docker :
   - `quotor` (`ROLE=web`) : le site, avec health check `/health` ;
   - `quotor-worker` (`ROLE=worker`) : téléchargements, découpes ffmpeg et tâches planifiées.

   Ils partagent un groupe de variables, `quotor-shared`.
2. Renseignez les variables demandées :
   - `DATABASE_URL` (Neon) ;
   - les variables `S3_*` (R2) ;
   - `ADMIN_EMAIL` et `ADMIN_PASSWORD` (12 caractères minimum) ;
   - les variables `LEGAL_*`.

   `SECRET_KEY_BASE` est généré par Render, et `PHX_HOST` est déduit de l'URL Render.
3. Déployez. Au démarrage, chaque service exécute les migrations et crée ou promeut l'admin, ce qui
   est sans risque même en parallèle. Le site met les tâches en file, le worker les exécute.
4. *(Si YouTube bloque les téléchargements)* :
   1. exportez un `cookies.txt` d'un compte YouTube ;
   2. ajoutez-le comme **Secret File** du worker ;
   3. définissez `YTDLP_COOKIES=/etc/secrets/cookies.txt`.

   Vous pouvez aussi faire tourner le worker chez vous (voir ci-dessous).
5. *(Domaine personnalisé)* Ajoutez-le dans Render et définissez `PHX_HOST=quotor.example.fr`.

**Plus de puissance** :

- augmentez `WORKER_MEDIA_CONCURRENCY`, qui fixe le nombre de découpes simultanées par worker
  (environ un par cœur) ;
- ou ajoutez des instances au service worker. Les workers se partagent automatiquement les tâches
  via PostgreSQL.

**Une seule machine** : sans `ROLE` (valeur `all`), un seul service fait tout. C'est suffisant pour
démarrer, mais le site ralentit pendant les découpes.

#### Option : un worker chez soi

YouTube bloque rarement les connexions de particuliers. Un worker lancé sur un PC ou un Raspberry Pi
télécharge donc bien plus fiablement qu'un serveur Render. Il suffit de lui donner accès à la même
base et au même bucket :

```bash
docker run -d --restart unless-stopped --name quotor-worker \
  -e ROLE=worker \
  -e DATABASE_URL='postgresql://…neon.tech/neondb?sslmode=require' \
  -e SECRET_KEY_BASE='<même valeur que sur Render>' \
  -e S3_ENDPOINT=https://<ID-compte>.r2.cloudflarestorage.com -e S3_BUCKET=quotor \
  -e S3_ACCESS_KEY_ID=… -e S3_SECRET_ACCESS_KEY=… \
  quotor
```

Supprimez alors le service `quotor-worker` de Render, ou laissez les deux se partager le travail.

### 5. Premiers pas en production

1. Connectez-vous avec `ADMIN_EMAIL`, puis ouvrez **Admin → Supervision**. Vérifiez trois choses :
   - le rôle du nœud est `web` ;
   - le stockage indiqué est `S3 · quotor` ;
   - ffmpeg et yt-dlp sont détectés (et la transcription vocale, sur un worker qui l'a activée).
2. **Admin → Vidéos sources** : collez quelques URLs YouTube, de préférence avec des sous-titres
   français. Suivez
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
| `ROLE` | `all` (site + tâches), `web` (site seul), `worker` (tâches seules, sans serveur HTTP) | `all` |
| `WORKER_MEDIA_CONCURRENCY` | découpes ffmpeg simultanées sur un worker | `2` |
| `S3_BUCKET` | active le stockage objet (sinon disque local) | – |
| `S3_ENDPOINT` | endpoint S3 (R2 : `https://<ID-compte>.r2.cloudflarestorage.com`) | – |
| `S3_REGION` | région S3 (`auto` pour R2) | `auto` |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | clés d'accès au bucket | – |
| `S3_PUBLIC_URL` | URL publique du bucket ; vide : le site relaie les fichiers (bucket privé) | – |
| `S3_CREATE_BUCKET` | crée le bucket au démarrage s'il manque (serveur S3 local) | `false` |
| `MEDIA_DIR` | stockage local ; avec S3, espace de travail et cache | `/data/media` |
| `KEEP_SOURCES` | conserver les vidéos sources après découpe | `false` |
| `BACKUP_ENABLED` | sauvegarde automatique chaque nuit (2 h UTC) | `true` |
| `BACKUP_KEEP` | nombre de sauvegardes conservées | `7` |
| `BACKUP_MEDIA` | `auto` (médias inclus s'ils sont sur disque local), `always` (aussi depuis S3), `never` | `auto` |
| `BACKUP_S3_BUCKET` | bucket **privé** des sauvegardes (mêmes `S3_ENDPOINT` et clés) ; sinon `BACKUP_DIR` | – |
| `BACKUP_DIR` | dossier des sauvegardes, à placer sur un volume distinct | `/data/backups` |
| `TRANSCRIBE` | transcription vocale : `auto` (active si whisper.cpp est installé), `true`, `false` | `auto` |
| `TRANSCRIBE_MIN_SCORE` | fiabilité minimale d'un clip affiné (part des mots entendus) pour être publié | `0.75` |
| `WHISPER_MODEL` | modèle whisper.cpp : `base`, `small`, `medium`, `large-v3-turbo`… ou chemin d'un `.bin` | `small` |
| `WHISPER_THREADS` | threads de transcription | nb de cœurs (max. 8) |
| `WHISPER_LANGUAGE` | langue parlée | `fr` |
| `WHISPER_VAD` | détecteur de voix (ignore musique et silences, mais dégrade les horodatages) | `false` |
| `WHISPER_MODELS_DIR` | dossier des modèles, téléchargés au premier usage | `/data/models` |
| `WHISPER_PATH` | binaire whisper.cpp | `whisper-cli` |
| `YTDLP_PATH` / `YTDLP_COOKIES` / `YTDLP_EXTRA_ARGS` | options de yt-dlp | – |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` | emails (liens de connexion, changement d'email) ; sans SMTP, ils sont seulement journalisés | – |
| `LEGAL_EDITOR_NAME`, `LEGAL_EDITOR_ADDRESS`, `LEGAL_CONTACT_EMAIL`, `LEGAL_PUBLICATION_DIRECTOR` | contenu des mentions légales | valeurs à remplacer |
| `LOG_LEVEL` | `debug`, `info`, `warning`, `error` | `info` |

---

## Sauvegardes

Chaque nuit à 2 h UTC (et à la demande depuis **Admin → Sauvegardes**), Quotor crée une archive
`quotor-AAAAMMJJ-HHMMSS.tar` :

| Contenu | Détail |
| --- | --- |
| `db.dump` | `pg_dump` compressé de toute la base, sans la file de tâches Oban |
| `clips/`, `thumbs/`, `montages/`, `sources/` | les médias, s'ils sont sur disque local (ou avec `BACKUP_MEDIA=always`) |
| `manifest.json` | date, version, nombre de médias |

Les `BACKUP_KEEP` plus récentes sont gardées, les autres supprimées.

**Où vont les archives :**

- avec `BACKUP_S3_BUCKET` → dans ce bucket privé (préfixe `backups/`). C'est le cas du blueprint
  Render, où les conteneurs n'ont pas de disque persistant ;
- sinon → dans `BACKUP_DIR`. Les fichiers compose montent ce dossier sur son propre volume :
  `quotor_backups` en développement, `quotor_backups_prod` pour l'image de production. Pour se
  protéger d'une panne de la machine, copiez régulièrement ce volume ailleurs, ou téléchargez les
  archives depuis l'admin.

**Restaurer** : la restauration **remplace** la base (`pg_restore --clean`, en une transaction) et
réécrit les médias présents dans l'archive. Arrêtez de préférence les workers, puis :

```bash
# image de production (docker exec -it <conteneur> …, ou Shell du service sur Render)
bin/quotor eval 'Quotor.Release.backups()'                                 # lister
bin/quotor eval 'Quotor.Release.restore("quotor-20261113-020000.tar")'     # base + médias
bin/quotor eval 'Quotor.Release.restore("/tmp/archive.tar", media: false)' # archive locale, base seule
bin/quotor eval 'Quotor.Release.backup()'                                  # sauvegarder maintenant

# développement
docker compose -f docker-compose.dev.yml exec app mix run -e 'Quotor.Backup.restore("quotor-20261113-020000.tar") |> IO.inspect()'
```

Redémarrez ensuite l'application. Une archive téléchargée depuis l'admin se restaure après
`docker cp archive.tar <conteneur>:/tmp/`. Avec un stockage S3, les médias de l'archive sont
renvoyés dans le bucket des médias.

En complément, Neon garde son propre historique (restauration à un instant donné, durée selon
l'offre).

---

## Architecture

```
        ┌──────────── nœud web (ROLE=web) ────────────┐
        │ site LiveView, recherche, montages          │
        │ admin : URL YouTube / fichier ─► file Oban  │
        └──────────────┬──────────────────────────────┘
                       │ tâches en file (PostgreSQL)
        ┌──────────────▼── nœud(s) worker (ROLE=worker) ─────────────┐
        │ IngestSource (file "ingest")                               │
        │   yt-dlp : vidéo ≤ 480p + sous-titres FR → quotes, mots    │
        │   whisper.cpp : transcription → score + recalage des quotes │
        │   (ou quotes depuis la transcription, sans sous-titres)    │
        │ CutSource (file "media", WORKER_MEDIA_CONCURRENCY)         │
        │   ffmpeg : un clip mp4 + une vignette par quote            │
        │ Cron 04:00 UTC : chaînes suivies ; 03:30 : nettoyage       │
        │ Cron 02:00 UTC : sauvegarde (pg_dump + médias) ─► bucket   │
        │   privé BACKUP_S3_BUCKET, ou dossier BACKUP_DIR            │
        └──────────────┬─────────────────────────────────────────────┘
                       ▼
     Stockage objet S3 / R2 (clips, vignettes, montages, sources)
            ▲ lu directement par les navigateurs (bucket public)
            │ ou relayé par le site sous /media/… (bucket privé)
```

- Recherche : plein texte PostgreSQL (tsvector « simple » et pg_trgm).
- Montage : plan glouton sur les mots horodatés, puis concaténation par ffmpeg sur le nœud web, à
  partir des clips mis en cache localement.
- En mode `ROLE=all` avec stockage local, tout tourne dans un seul conteneur.

| Dossier | Contenu |
| --- | --- |
| `lib/quotor/catalog/` | schémas : sources, quotes, mots horodatés, auteurs, favoris, signalements |
| `lib/quotor/ingest/` | téléchargement (yt-dlp), analyse des sous-titres, segmentation, transcription (whisper.cpp) et alignement texte / parole |
| `lib/quotor/search.ex` | recherche standard et plan de montage |
| `lib/quotor/montages.ex` | rendu et cache des montages |
| `lib/quotor/media.ex`, `lib/quotor/storage/` | accès aux fichiers : disque local ou S3/R2 (signature SigV4 via Req), cache local |
| `lib/quotor/workers/` | tâches Oban (ingestion, découpe, synchronisation des chaînes, nettoyage, sauvegarde) |
| `lib/quotor/backup.ex` | sauvegarde et restauration (pg_dump / pg_restore, archive tar des médias) |
| `lib/quotor/logs.ex`, `monitoring.ex` | buffer de logs, indicateurs de supervision |
| `lib/quotor_web/live/` | pages LiveView publiques et admin |
| `docker/entrypoint.sh` | PostgreSQL interne, secret, migrations, démarrage |

En stockage local ou avec un bucket privé, les fichiers médias sont servis par `/media/…`, avec
prise en charge des requêtes `Range` (nécessaire à la lecture vidéo sur Safari et iOS).

---

## Tests et CI

249 tests couvrent :

- l'analyse des sous-titres (y compris le format mot à mot de YouTube) et la segmentation ;
- l'alignement texte / parole (score, recalage, mots approchants, quotes depuis la seule
  transcription), la lecture du JSON de whisper.cpp et le pipeline avec transcription (confirmée,
  contredite, en échec, sans sous-titres) ;
- la recherche et le plan de montage ;
- le catalogue ;
- le **pipeline complet** d'ingestion, avec un faux téléchargeur et une vraie découpe ffmpeg ;
- les auteurs (attribution automatique à la chaîne, priorité de l'auteur d'une réplique, pages
  publiques, gestion admin) ;
- l'accueil, l'onglet Découvrir (tris, favoris) et le contrôle d'accès des trois profils ;
- les mentions de propriété (pied de page, mentions légales) ;
- les pages légales et les balises Discord ;
- le service des médias ;
- le stockage S3, contre un faux bucket en mémoire qui vérifie la signature des requêtes :
  pipeline complet sans fichier restant sur le worker, envoi de fichier, relais d'un bucket privé
  avec `Range` ;
- les sauvegardes : vrai `pg_dump`, archive des médias, rétention, restauration depuis le disque ou
  un bucket distinct, téléchargement réservé aux admins, noms d'archive validés ;
- les logs.

Les tests marqués `:ffmpeg` (ou `:pg_dump`) sont ignorés si ffmpeg (ou le client PostgreSQL) est
absent. La CI installe `pg_dump` 17, de la même version que le serveur.

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
- **Transcription vocale (whisper.cpp)** :
  - **coût CPU** : avec le modèle `small`, compter de l'ordre d'un quart de la durée de la vidéo
    sur 4 à 8 cœurs (5 min pour 20 min de vidéo), et ~1 Go de RAM. Impossible sur un worker
    Render Starter (512 Mo) : le blueprint la désactive (`TRANSCRIBE=false`). Il faut une offre
    Standard ou un worker chez soi ;
  - **premier usage** : le modèle (~500 Mo pour `small`) est téléchargé ; sur un disque éphémère
    (Render), il l'est à chaque redéploiement ;
  - **qualité** : bonne en français courant, moins sur l'argot, les noms propres (« JDG »), les voix
    qui se chevauchent et la musique, où Whisper peut inventer du texte. Le score repère ces cas,
    sans les corriger. Sans sous-titres, le texte n'est relu par personne : les quotes douteuses
    tombent dans « À vérifier » ;
  - **pas d'identification des voix** : une quote n'est pas attribuée automatiquement à la
    personne qui parle ;
  - sans transcription active, une vidéo sans sous-titres passe en échec, comme avant.
- **Les sous-titres automatiques** n'ont ni ponctuation ni majuscules et contiennent des erreurs de
  reconnaissance. Les textes des quotes peuvent être corrigés à la main dans l'admin.
- **Avec des sous-titres manuels sans transcription**, le temps de chaque mot est interpolé : les
  montages sont moins précis. Avec la transcription, les mots reconnus prennent leur temps réel.

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

- **Contrôle des montages** : il ajoute 2 à 5 s au rendu d'un montage (une passe de whisper.cpp,
  modèle `small`, 8 cœurs), et ne tourne que si le nœud web a la transcription. Sur Render, le
  site (Starter) ne l'a pas : les montages y sont livrés sans contrôle. Les morceaux d'un seul mot
  très court restent les moins bien reconnus.
- **Idées de phrases** : générées sans IA, par greffe de répliques réelles. Certaines sont
  bancales (« Trois que ça marche… ») ; « Autres idées » en tire d'autres.
- **Affinage** : il réécoute chaque clip, ce qui ajoute environ 50 % au temps de transcription
  d'une vidéo. Sans transcription active, les clips sont publiés bruts, sans vérification. Un clip
  dont le premier mot est mal reconnu (et non coupé) est élargi inutilement, puis part « à
  vérifier ».
- **Les montages sont rendus par le site**, pas par les workers : pendant un rendu, le nœud web
  consomme du CPU, et télécharge les clips depuis le bucket s'ils ne sont pas en cache.
- **La découpe d'une vidéo se fait sur un seul worker** : plusieurs workers traitent plusieurs vidéos
  en parallèle, mais une vidéo n'est pas répartie entre eux.
- **Un seul nœud web** : le limiteur de débit et le buffer de logs sont en mémoire, propres à chaque
  nœud. Plusieurs nœuds web fonctionneraient, mais sans limite de débit commune.
- **Sans stockage S3**, il faut un disque persistant (offre payante Render) et un seul conteneur :
  les rôles `web`/`worker` séparés supposent un stockage partagé.
- **Derrière un pooler** (`DATABASE_POOLER=true`), les workers ne reçoivent pas de notification
  immédiate et découvrent les nouvelles tâches par interrogation, avec quelques secondes de délai.
- **Neon** : Oban interroge la base en continu, ce qui l'empêche de se mettre en veille et consomme
  des heures de calcul.
- **Render gratuit** : le site s'endort après 15 min d'inactivité. Les workers Render sont toujours
  payants ; un worker chez soi est l'alternative gratuite.
- **Logs** : le buffer admin est perdu au redémarrage, et il n'y a pas d'alerting externe (Sentry,
  Prometheus…).
- **Sauvegardes** : chaque archive est complète (pas d'incrémental) et non chiffrée, d'où un
  bucket privé. En S3, les médias ne sont pas inclus par défaut : `BACKUP_MEDIA=always` les
  télécharge tous à chaque sauvegarde, ce qui devient lourd quand le catalogue grossit. La
  restauration se fait en ligne de commande, pas depuis l'interface.
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
