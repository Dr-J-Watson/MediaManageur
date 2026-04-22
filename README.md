# MediaManageur

![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-Personal-lightgrey)
![Platforms](https://img.shields.io/badge/Services-Media%20%2B%20Games-6f42c1)
![Stars](https://img.shields.io/github/stars/Dr-J-Watson/MediaManageur?style=social)
![Forks](https://img.shields.io/github/forks/Dr-J-Watson/MediaManageur?style=social)
![Last commit](https://img.shields.io/github/last-commit/Dr-J-Watson/MediaManageur?color=green&label=Last+update)
![Repo size](https://img.shields.io/github/repo-size/Dr-J-Watson/MediaManageur)
![Views](https://vbr.nathanchung.dev/badge?page_id=Dr-J-Watson.MediaManageur)

Stack Docker Compose auto-hébergée pour la gestion, le téléchargement et la diffusion de médias et de jeux vidéo.
Self-hosted Docker Compose stack for managing, downloading and streaming media and video games.

---

## 🌐 Language / Langue

- [Français — Guide complet](README.fr.md)
- [English — Full guide](README.en.md)

---

## Services

| Service | Rôle / Role |
|---|---|
| [Jellyfin](https://jellyfin.org) | Serveur de streaming multimédia / Multimedia streaming server |
| [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) | Portail de demandes de médias / Media request portal |
| [Radarr](https://radarr.video) | Automatisation des films / Movie automation |
| [Sonarr](https://sonarr.tv) | Automatisation des séries / Series automation |
| [Lidarr](https://lidarr.audio) | Automatisation de la musique / Music automation |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | Gestionnaire d'indexers / Indexer manager |
| [qBittorrent](https://www.qbittorrent.org) | Client de téléchargement / Download client |
| [Gluetun](https://github.com/qdm12/gluetun) | Tunnel VPN pour qBittorrent / VPN tunnel for qBittorrent |
| [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) | Bypass Cloudflare pour Prowlarr / Cloudflare bypass for Prowlarr |
| [Questarr](https://github.com/doezer/questarr) | Automatisation des jeux vidéo / Video game automation |
| [GameVault](https://gamevau.lt) | Bibliothèque de jeux vidéo / Video game library |
| [Homarr](https://homarr.dev) | Tableau de bord central / Central dashboard |

---

## Quick Start / Démarrage rapide

```bash
make init
make up
```

`make init` / `make init`:
- creates `.env` from `.env.example` if missing / crée `.env` depuis `.env.example` s'il manque
- generates `docker-compose.override.yml` if missing / génère `docker-compose.override.yml` s'il manque
- launches interactive configuration (usage profiles + Jellyfin GPU) / lance la configuration interactive (profils d'usage + GPU Jellyfin)

---

## Useful Commands / Commandes utiles

| Command / Commande | Description |
|---|---|
| `make init` | Initialisation complète + menu interactif / Full initialization + interactive menu |
| `make interactive` | Reconfigurer usages + GPU / Reconfigure usages + GPU |
| `make configure-services` | Choix par usages (override + .env) / Usage-based selection (override + .env) |
| `make configure-gpu-jellyfin` | Vérification GPU + bloc Jellyfin / GPU checks + Jellyfin block |
| `make start` | Démarre les conteneurs existants / Start existing containers |
| `make down` | Arrête et supprime les conteneurs / Stop and remove containers |
| `make update` | Met à jour les images / Pull images and apply updates |
| `make validate` | Valide la configuration Compose / Validate compose configuration |
| `make ps` | Affiche l'état des services / Show service status |
| `make logs SERVICE=jellyseerr` | Affiche les logs d'un service / Tail logs for one service |