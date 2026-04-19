# Netflix Stack - Guide de configuration

![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Langue](https://img.shields.io/badge/Langue-FR-0055A4)
![Services](https://img.shields.io/badge/Services-Media%20%2B%20Jeux-6f42c1)

Ce guide explique :
- les connexions entre les applications
- les clés API à récupérer
- la configuration du fichier `.env`

## Démarrage rapide

```bash
make env
make up
```

Accès principal :
- Dashboard Homarr : `http://IP_DU_SERVEUR:${HOMARR_PORT}`
- Requests : `http://IP_DU_SERVEUR:${JELLYSEERR_PORT}`
- Streaming : `http://IP_DU_SERVEUR:${JELLYFIN_PORT}`

---

## Plan

0. [Prérequis système](#section-0)
1. [Vue d'ensemble des connexions](#section-1)
2. [URLs et hostnames — tableau de référence](#section-2)
3. [.env — signification de chaque groupe](#section-3)
4. [Clés API à récupérer](#section-4)
5. [Connexions à configurer (ordre recommandé)](#section-5)
6. [Atomic Moves et Hardlinks](#section-6)
7. [Vérification rapide après configuration](#section-7)
8. [Démarrage, Makefile et mises à jour](#section-8)
9. [Dépannage courant](#section-9)
10. [Bonnes pratiques de sécurité](#section-10)

---

<a id="section-0"></a>
## 0) Prérequis système

Avant de démarrer la stack, assurez-vous que les éléments suivants sont en place.

**Logiciels requis :**
- Docker Engine ≥ 24.x
- Docker Compose plugin ≥ 2.x (`docker compose version` pour vérifier)
- `make` installé (`sudo apt install make` sur Debian/Ubuntu)

**Système :**
- OS Linux recommandé (Debian, Ubuntu, Fedora…)
- Droits `sudo` ou appartenance au groupe `docker`
- Au moins 4 Go de RAM disponibles pour l'ensemble des services

**Réseau :**
- Vérifier que les ports définis dans `.env` ne sont pas déjà utilisés sur l'hôte :
  ```bash
  ss -tlnp | grep -E "$(grep '_PORT=' .env | cut -d= -f2 | paste -sd'|' -)"
  ```

**Compte VPN :**
- Un abonnement VPN compatible Gluetun (Mullvad, ProtonVPN, AirVPN…)
- La clé WireGuard ou les identifiants OpenVPN à portée

**Arborescence de données :**

La structure suivante doit exister (ou sera créée au premier démarrage) :
```
${DATA_DIR}/
├── torrents/
│   ├── movies/
│   ├── tv/
│   ├── music/
│   └── games/
└── media/
    ├── films/
    ├── series/
    ├── musique/
    └── jeux/
```

> **Important :** `torrents/` et `media/` doivent être sur le même volume pour que les Hardlinks fonctionnent (voir [section 6](#section-6)).

---

<a id="section-1"></a>
## 1) Vue d'ensemble des connexions

**Flux principal :**

```
Jellyseerr ──────────────────► Radarr (films)
                 └───────────► Sonarr (séries)

Radarr ──────────────────────► Prowlarr (indexers)
Sonarr ──────────────────────► Prowlarr
Lidarr ──────────────────────► Prowlarr

Radarr ──────────────────────► qBittorrent (via Gluetun)
Sonarr ──────────────────────► qBittorrent (via Gluetun)
Lidarr ──────────────────────► qBittorrent (via Gluetun)

Questarr ────────────────────► qBittorrent (via Gluetun)

Prowlarr ────────────────────► FlareSolverr (indexers Cloudflare uniquement)

qBittorrent ────────────────► /data/torrents  (fichiers en cours)
Jellyfin ◄──────────────────── /data/media     (médias finalisés)
GameVault ◄─────────────────── /data/media/jeux

Radarr/Sonarr/Lidarr ───────► Jellyfin (notifications import/rename/delete)

Homarr ──────────────────────► tous les services (widgets de monitoring)
```

**Pourquoi `gluetun` et pas `qbittorrent` comme hostname ?**

qBittorrent partage le namespace réseau de Gluetun. Du point de vue des autres conteneurs, l'endpoint joignable est donc `gluetun:8080`, pas `qbittorrent:8080`.

---

<a id="section-2"></a>
## 2) URLs et hostnames — tableau de référence

| Service | URL navigateur (hôte) | Hostname Docker interne | Port interne |
|---|---|---|---|
| qBittorrent | `http://IP:${QBITTORRENT_PORT}` | `gluetun` | `8080` |
| Prowlarr | `http://IP:${PROWLARR_PORT}` | `prowlarr` | `9696` |
| Radarr | `http://IP:${RADARR_PORT}` | `radarr` | `7878` |
| Sonarr | `http://IP:${SONARR_PORT}` | `sonarr` | `8989` |
| Lidarr | `http://IP:${LIDARR_PORT}` | `lidarr` | `8686` |
| Questarr | `http://IP:${QUESTARR_PORT}` | `questarr` | `5000` |
| Jellyseerr | `http://IP:${JELLYSEERR_PORT}` | `jellyseerr` | `5055` |
| Jellyfin | `http://IP:${JELLYFIN_PORT}` | `jellyfin` | `8096` |
| Homarr | `http://IP:${HOMARR_PORT}` | `homarr` | `7575` |
| GameVault | `http://IP:${GAMEVAULT_PORT}` | `gamevault` | `8080` |
| GameVault DB | *(interne uniquement)* | `gamevault-db` | `5432` |
| FlareSolverr | `http://IP:${FLARESOLVERR_PORT}` | `flaresolverr` | `8191` |

> Utilisez toujours les **hostnames Docker** (colonne 3) pour configurer les connexions inter-services, jamais l'IP de l'hôte.

---

<a id="section-3"></a>
## 3) .env — signification de chaque groupe

Créez le fichier `.env` depuis le modèle fourni :
```bash
make env
```

### Variables système

| Variable | Exemple | Description |
|---|---|---|
| `PUID` | `1000` | UID de l'utilisateur propriétaire des fichiers |
| `PGID` | `1000` | GID du groupe propriétaire |
| `TZ` | `Europe/Paris` | Fuseau horaire (format tz database) |

Pour connaître votre PUID/PGID : `id $(whoami)`

### Variables de chemins

| Variable | Exemple | Description |
|---|---|---|
| `CONFIG_DIR` | `/opt/appdata` | Dossier des configurations persistantes |
| `DATA_DIR` | `/mnt/data` | Racine des données (torrents + médias) |

### Variables VPN

| Variable | Exemple | Description |
|---|---|---|
| `VPN_PROVIDER` | `mullvad` | Fournisseur supporté par Gluetun |
| `VPN_TYPE` | `wireguard` | Protocole : `wireguard` ou `openvpn` |
| `VPN_KEY` | `abc123...` | Clé privée WireGuard |
| `VPN_COUNTRY` | `Netherlands` | Pays de sortie VPN |

Consultez la [documentation Gluetun](https://github.com/qdm12/gluetun-wiki) pour les variables spécifiques à votre fournisseur.

### Variables GameVault

| Variable | Exemple | Description |
|---|---|---|
| `GAMEVAULT_DB_PASSWORD` | `motdepasse` | Mot de passe PostgreSQL pour GameVault |

### Variables de ports externes

Chaque service expose un port sur l'hôte via une variable `*_PORT`. Modifiez ces valeurs uniquement en cas de conflit avec un port déjà utilisé sur votre machine.

### Variables de versions d'images

Les variables `*_VERSION` contrôlent le tag Docker de chaque service. En production, préfère des versions fixes (`2.4.3`) plutôt que `latest` pour éviter les mises à jour non maîtrisées.

---

<a id="section-4"></a>
## 4) Clés API à récupérer

> **Prérequis important :** finalise le wizard de création de compte admin sur chaque application *avant* de chercher la clé API. Certaines apps ne l'affichent qu'une fois le setup initial terminé.

> **Premier démarrage :** ouvre chaque interface au moins une fois après `make up` pour que l'application génère son fichier `config.xml` et initialise sa base de données. Sans cette étape, la clé API peut ne pas encore exister.

### Prowlarr
Settings → General → **API Key**

### Radarr
Settings → General → Security → **API Key**

### Sonarr
Settings → General → Security → **API Key**

### Lidarr
Settings → General → Security → **API Key**

### Jellyfin (pour Jellyseerr)
Dashboard → Advanced → API Keys → **Create new key**

---

<a id="section-5"></a>
## 5) Connexions à configurer (ordre recommandé)

### Étape A — Vérifier le client de téléchargement (qBittorrent)

- Finalise le compte admin qBittorrent (onglet WebUI → Options → Web User Interface)
- Vérifiez que la WebUI écoute bien sur le port `8080` à l'intérieur du conteneur
- Dans toutes les apps *Arr, le client de téléchargement devra pointer vers :
  - **Host :** `gluetun`
  - **Port :** `8080`

### Étape B — Connecter Prowlarr aux apps *Arr

Dans **Prowlarr → Settings → Apps → Add Application** :

**Radarr :**
- Server : `http://radarr:7878`
- API Key : clé API Radarr

**Sonarr :**
- Server : `http://sonarr:8989`
- API Key : clé API Sonarr

**Lidarr :**
- Server : `http://lidarr:8686`
- API Key : clé API Lidarr

Pour chaque app : **Test** → voyant vert → **Save**.

Une fois connectées, Prowlarr synchronise automatiquement ses indexers vers chaque application.

### Étape C — FlareSolverr dans Prowlarr (si indexers protégés Cloudflare)

Dans **Prowlarr → Settings → Indexers** :
- Ajoutez FlareSolverr avec l'URL : `http://flaresolverr:8191`
- Crée un tag dédié, par exemple `flare`
- Assigne ce tag uniquement aux indexers qui en ont besoin (ex : 1337x)

### Étape D — Connecter les *Arr à qBittorrent

Dans **Radarr, Sonarr et Lidarr → Settings → Download Clients → Add → qBittorrent** :

| Champ | Valeur |
|---|---|
| Host | `gluetun` |
| Port | `8080` |
| Username | identifiant qBittorrent |
| Password | mot de passe qBittorrent |

Catégories recommandées (à définir dans chaque app) :

| App | Catégorie |
|---|---|
| Radarr | `movies` |
| Sonarr | `tv` |
| Lidarr | `music` |

> **Important :** Lidarr doit impérativement utiliser une catégorie distincte (`music` ou `audio`). Sans ça, Lidarr peut intercepter des téléchargements destinés à Radarr ou Sonarr si tout arrive dans la même catégorie.

**Test → Save** pour chaque application.

### Étape E — Questarr vers qBittorrent

Dans Questarr :
- Client de téléchargement : `gluetun:8080`
- Catégorie dédiée : `games` (pour isoler les téléchargements jeux)
- Chemins d'import : `/data/media/jeux`

Si vous utilisez Prowlarr pour les indexers de jeux, ajoutez Questarr comme application dans Prowlarr (selon la version disponible) en suivant la même logique que l'étape B.

### Étape F — Jellyseerr

Dans Jellyseerr, connecte d'abord Jellyfin, puis les services *Arr :

**Jellyfin :**
- URL : `http://jellyfin:8096`
- API Key : clé API Jellyfin

**Radarr :**
- URL : `http://radarr:7878`
- API Key : clé API Radarr
- Définissez le quality profile et le root folder

**Sonarr :**
- URL : `http://sonarr:8989`
- API Key : clé API Sonarr
- Définissez le quality profile et le root folder

> Jellyseerr ne pilote pas Lidarr nativement. Les demandes de musique se gèrent directement dans l'interface Lidarr.

### Étape G — Bibliothèques Jellyfin

**Ajouter les bibliothèques :**

Dans Jellyfin → Dashboard → Libraries → Add Media Library, pointez vers les dossiers sous `/data/media` :

| Bibliothèque | Chemin |
|---|---|
| Films | `/data/media/films` |
| Séries | `/data/media/series` |
| Musique | `/data/media/musique` |

**Notifications depuis les *Arr vers Jellyfin :**

Dans **Radarr, Sonarr et Lidarr → Settings → Connect → + → Emby/Jellyfin** :
- URL : `http://jellyfin:8096`
- API Key : clé API Jellyfin
- Activez les événements : **Import/Download**, **Rename/Upgrade**, **Delete**
- **Test → Save**

Résultat : à chaque ajout, mise à jour ou suppression de média, Jellyfin est notifié et rafraîchit sa bibliothèque immédiatement.

### Étape H — GameVault

- Vérifiez la connexion à PostgreSQL (service `gamevault-db`)
- Vérifiez que le dossier de bibliothèque monté est bien `/games` (depuis `${DATA_DIR}/media/jeux`)
- Lancez un scan/rafraîchissement de la bibliothèque après les premiers imports Questarr

> **Note PostgreSQL :** GameVault gère la migration de schéma automatiquement au premier démarrage. Si la base existe déjà d'une version précédente, vérifiez les logs du conteneur pour t'assurer que la migration s'est bien déroulée (`make logs SERVICE=gamevault`).

### Étape I — Homarr

Dans Homarr :
- Ajoutez des widgets vers chaque service
- Utilise l'IP du serveur avec le port externe pour l'accès navigateur
- Ou le hostname Docker interne si Homarr communique directement avec le service

---

<a id="section-6"></a>
## 6) Atomic Moves et Hardlinks

Les Hardlinks permettent à Radarr/Sonarr/Lidarr de "déplacer" un fichier depuis le dossier torrent vers le dossier média **sans copie physique des données**. Le fichier n'occupe qu'une seule fois l'espace disque, tout en étant accessible depuis deux chemins différents.

**Condition indispensable :** `torrents/` et `media/` doivent être sur le **même volume** (même système de fichiers). Un déplacement entre deux volumes différents provoque une copie complète, ce qui double temporairement l'espace occupé et ralentit le processus.

**Configuration correcte dans `.env` :**
```env
DATA_DIR=/mnt/data
```

Structure résultante dans le conteneur :
```
/data/torrents/movies/   ← qBittorrent télécharge ici
/data/media/films/       ← Radarr fait un hardlink ici
```

**Vérification :** si `DATA_DIR` pointez vers deux volumes différents pour `torrents` et `media`, les Hardlinks échoueront silencieusement et seront remplacés par des copies. Vérifiez avec :
```bash
df /chemin/torrents /chemin/media
# Les deux lignes doivent afficher le même device (ex: /dev/sda1)
```

---

<a id="section-7"></a>
## 7) Vérification rapide après configuration

| Service | Ce qu'il faut vérifier |
|---|---|
| Prowlarr | Chaque app connectée affiche un indicateur vert dans Settings → Apps |
| Radarr / Sonarr / Lidarr | Le client qBittorrent est vert dans Settings → Download Clients |
| Questarr | Le client qBittorrent est fonctionnel |
| Jellyseerr | Les connexions Jellyfin et *Arr sont vertes |
| GameVault | La base PostgreSQL est connectée, la bibliothèque `/games` est lisible |
| Gluetun | Le VPN est actif (`make logs SERVICE=gluetun` → cherche "connected") |

**Test de bout en bout :**
1. Faites une demande dans Jellyseerr (film ou série)
2. Vérifiez qu'une tâche apparaît dans Radarr ou Sonarr
3. Vérifiez que le téléchargement apparaît dans qBittorrent
4. Une fois terminé, vérifiez que le fichier est bien dans `/data/media`
5. Vérifiez que Jellyfin a rafraîchi sa bibliothèque automatiquement

---

<a id="section-8"></a>
## 8) Démarrage, Makefile et mises à jour

### Commandes principales

| Commande | Description |
|---|---|
| `make env` | Crée `.env` depuis `.env.example` si absent |
| `make up` | Démarre toute la stack (crée + démarre les conteneurs) |
| `make start` | Redémarre les conteneurs existants |
| `make down` | Arrête et supprime les conteneurs |
| `make update` | Mise à jour complète (pull + redémarrage) |
| `make validate` | Valide la syntaxe du fichier Compose |
| `make ps` | Affiche l'état de tous les services |
| `make logs SERVICE=<nom>` | Affiche les logs d'un service spécifique |

> **Comportement automatique :** si `.env` est absent, `make start` et `make up` déclenchent automatiquement `make env`. Si `make start` est lancé sans conteneurs existants, il bascule automatiquement sur `docker compose up -d`.

### Mise à jour d'un seul service

```bash
docker compose pull jellyseerr
docker compose up -d jellyseerr
```

---

<a id="section-9"></a>
## 9) Dépannage courant

### Erreur de permissions (`EACCES`, `Permission denied`)

```bash
# Vérifiez les droits du dossier de config du service concerné
ls -la ${CONFIG_DIR}/nom_du_service

# Correction (adapte le chemin)
docker run --rm \
  -v /chemin/vers/config/service:/target \
  alpine sh -c 'chown -R 1000:1000 /target && chmod -R u+rwX,g+rwX /target'
```

Vérifiez également que `PUID` et `PGID` dans `.env` correspondent bien à l'utilisateur propriétaire des dossiers (`id $(whoami)`).

### VPN non connecté

```bash
make logs SERVICE=gluetun
# Cherche une ligne "connected" ou un message d'erreur d'authentification
```

Si le VPN ne monte pas, qBittorrent ne sera pas joignable depuis les *Arr.

### Service inaccessible depuis le navigateur

```bash
make ps
# Vérifiez que le service est bien "Up" et que le port est bien publié
```

### Prowlarr ne synchronise pas les indexers

- Vérifiez que les apps *Arr sont bien en vert dans Prowlarr → Settings → Apps
- Relancez une synchronisation manuelle : Prowlarr → Indexers → Sync App Indexers

### Clé API non visible

Certaines apps (Prowlarr, Radarr, Sonarr, Lidarr) n'affichent la clé API qu'une fois le wizard de premier démarrage terminé. Assurez-vous d'avoir créé le compte admin et fermé l'écran d'accueil initial.

---

<a id="section-10"></a>
## 10) Bonnes pratiques de sécurité

- Ne jamais commiter `.env` avec de vraies clés (ajoutez `.env` à `.gitignore`)
- Changer les mots de passe admin par défaut sur tous les services dès le premier démarrage
- Préférer des tags de version fixes plutôt que `latest` en production
- Exposer uniquement les ports strictement nécessaires (pas de `0.0.0.0` inutile)
- Régénérer les clés API si vous suspectez une compromission (chaque app permet de regénérer depuis Settings → General)
- Vérifier régulièrement les logs Gluetun pour confirmer que le VPN est actif avant tout téléchargement :
  ```bash
  make logs SERVICE=gluetun | grep -i "connected\|error\|ip address"
  ```
- Ne pas exposer les ports des services sur internet sans reverse proxy et authentification (Nginx Proxy Manager, Caddy, Authelia…)