# Netflix Stack - Configuration Guide

![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Language](https://img.shields.io/badge/Language-EN-1f883d)
![Services](https://img.shields.io/badge/Services-Media%20%2B%20Games-6f42c1)

This guide explains:
- connections between applications
- API keys to retrieve
- .env configuration

## Quick Start

```bash
make env
make up
```

Main access points:
- Homarr Dashboard: `http://IP_DU_SERVEUR:${HOMARR_PORT}`
- Requests: `http://IP_DU_SERVEUR:${JELLYSEERR_PORT}`
- Streaming: `http://IP_DU_SERVEUR:${JELLYFIN_PORT}`

---

## Plan

0. [System prerequisites](#section-0)
1. [Connection overview](#section-1)
2. [URLs and hostnames - reference table](#section-2)
3. [.env - variable groups explained](#section-3)
4. [API keys to retrieve](#section-4)
5. [App-to-app setup (recommended order)](#section-5)
6. [Atomic Moves and Hardlinks](#section-6)
7. [Quick validation checklist](#section-7)
8. [Start, Makefile, and updates](#section-8)
9. [Common troubleshooting](#section-9)
10. [Security best practices](#section-10)

---

<a id="section-0"></a>
## 0) System prerequisites

Before starting the stack, make sure the following requirements are met.

**Required software:**
- Docker Engine >= 24.x
- Docker Compose plugin >= 2.x (`docker compose version` to verify)
- `make` installed (`sudo apt install make` on Debian/Ubuntu)

**System:**
- Linux recommended (Debian, Ubuntu, Fedora...)
- `sudo` privileges or membership in the `docker` group
- At least 4 GB of available RAM for all services

**Network:**
- Ensure ports defined in `.env` are not already used on the host:
  ```bash
  ss -tlnp | grep -E "$(grep '_PORT=' .env | cut -d= -f2 | paste -sd'|' -)"
  ```

**VPN account:**
- A Gluetun-compatible VPN provider (Mullvad, ProtonVPN, AirVPN...)
- WireGuard key or OpenVPN credentials ready

**Data layout:**

The following structure should exist (or will be created on first start):
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

> **Important:** `torrents/` and `media/` must be on the same volume for hardlinks to work (see [section 6](#section-6)).

---

<a id="section-1"></a>
## 1) Connection overview

**Main flow:**

```
Jellyseerr --------------------> Radarr (movies)
                 \-------------> Sonarr (series)

Radarr ------------------------> Prowlarr (indexers)
Sonarr ------------------------> Prowlarr
Lidarr ------------------------> Prowlarr

Radarr ------------------------> qBittorrent (via Gluetun)
Sonarr ------------------------> qBittorrent (via Gluetun)
Lidarr ------------------------> qBittorrent (via Gluetun)

Questarr ----------------------> qBittorrent (via Gluetun)

Prowlarr ----------------------> FlareSolverr (Cloudflare indexers only)

qBittorrent -------------------> /data/torrents  (in-progress files)
Jellyfin <---------------------- /data/media     (finalized media)
GameVault <--------------------- /data/media/jeux

Radarr/Sonarr/Lidarr ----------> Jellyfin (import/rename/delete notifications)

Homarr ------------------------> all services (monitoring widgets)
```

**Why `gluetun` and not `qbittorrent` as hostname?**

qBittorrent shares Gluetun's network namespace. From other containers, the reachable endpoint is therefore `gluetun:8080`, not `qbittorrent:8080`.

---

<a id="section-2"></a>
## 2) URLs and hostnames - reference table

| Service | Browser URL (host) | Internal Docker hostname | Internal port |
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
| GameVault DB | *(internal only)* | `gamevault-db` | `5432` |
| FlareSolverr | `http://IP:${FLARESOLVERR_PORT}` | `flaresolverr` | `8191` |

> Always use **Docker hostnames** (column 3) for inter-service connections, never the host IP.

---

<a id="section-3"></a>
## 3) .env - variable groups explained

Create `.env` from the provided template:
```bash
make env
```

### System variables

| Variable | Example | Description |
|---|---|---|
| `PUID` | `1000` | UID of the file owner user |
| `PGID` | `1000` | GID of the file owner group |
| `TZ` | `Europe/Paris` | Timezone (tz database format) |

To get your PUID/PGID: `id $(whoami)`

### Path variables

| Variable | Example | Description |
|---|---|---|
| `CONFIG_DIR` | `/opt/appdata` | Persistent app configuration directory |
| `DATA_DIR` | `/mnt/data` | Data root (torrents + media) |

### VPN variables

| Variable | Example | Description |
|---|---|---|
| `VPN_PROVIDER` | `mullvad` | Gluetun-supported provider |
| `VPN_TYPE` | `wireguard` | Protocol: `wireguard` or `openvpn` |
| `VPN_KEY` | `abc123...` | WireGuard private key |
| `VPN_COUNTRY` | `Netherlands` | VPN exit country |

Check [Gluetun documentation](https://github.com/qdm12/gluetun-wiki) for provider-specific variables.

### GameVault variables

| Variable | Example | Description |
|---|---|---|
| `GAMEVAULT_DB_PASSWORD` | `password` | PostgreSQL password used by GameVault |

### External port variables

Each service exposes a host port via a `*_PORT` variable. Change these only if a conflict exists on your machine.

### Image version variables

`*_VERSION` variables control Docker image tags for each service. In production, prefer pinned versions (`2.4.3`) over `latest` to avoid uncontrolled updates.

---

<a id="section-4"></a>
## 4) API keys to retrieve

> **Important prerequisite:** complete the initial admin setup wizard in each application *before* looking for API keys. Some apps only expose API keys after setup is finished.

> **First startup:** open each web interface at least once after `make up` so the application can generate its `config.xml` and initialize its database. Without this step, API keys may not exist yet.

### Prowlarr
Settings -> General -> **API Key**

### Radarr
Settings -> General -> Security -> **API Key**

### Sonarr
Settings -> General -> Security -> **API Key**

### Lidarr
Settings -> General -> Security -> **API Key**

### Jellyfin (for Jellyseerr)
Dashboard -> Advanced -> API Keys -> **Create new key**

---

<a id="section-5"></a>
## 5) App-to-app setup (recommended order)

### Step A - Verify download client (qBittorrent)

- Complete qBittorrent admin account setup (WebUI -> Options -> Web User Interface)
- Verify WebUI listens on `8080` inside the container
- In all Arr apps, download client should use:
  - **Host:** `gluetun`
  - **Port:** `8080`

### Step B - Connect Prowlarr to Arr apps

In **Prowlarr -> Settings -> Apps -> Add Application**:

**Radarr:**
- Server: `http://radarr:7878`
- API Key: Radarr API key

**Sonarr:**
- Server: `http://sonarr:8989`
- API Key: Sonarr API key

**Lidarr:**
- Server: `http://lidarr:8686`
- API Key: Lidarr API key

For each app: **Test** -> green status -> **Save**.

Once connected, Prowlarr can sync indexers automatically to each app.

### Step C - FlareSolverr in Prowlarr (Cloudflare-protected indexers)

In **Prowlarr -> Settings -> Indexers**:
- Add FlareSolverr with URL: `http://flaresolverr:8191`
- Create a dedicated tag, e.g. `flare`
- Assign this tag only to indexers that need it (e.g. 1337x)

### Step D - Connect Arr apps to qBittorrent

In **Radarr, Sonarr, Lidarr -> Settings -> Download Clients -> Add -> qBittorrent**:

| Field | Value |
|---|---|
| Host | `gluetun` |
| Port | `8080` |
| Username | qBittorrent username |
| Password | qBittorrent password |

Recommended categories:

| App | Category |
|---|---|
| Radarr | `movies` |
| Sonarr | `tv` |
| Lidarr | `music` |

> **Important:** Lidarr must use a distinct category (`music` or `audio`). Otherwise, Lidarr may pick up Radarr/Sonarr downloads if they share the same category.

**Test -> Save** in each app.

### Step E - Questarr to qBittorrent

In Questarr:
- Download client: `gluetun:8080`
- Dedicated category: `games` (to isolate game downloads)
- Import paths: `/data/media/jeux`

If you use Prowlarr for game indexers, add Questarr as an app in Prowlarr (depending on your version), using the same logic as Step B.

### Step F - Jellyseerr

In Jellyseerr, connect Jellyfin first, then Arr services:

**Jellyfin:**
- URL: `http://jellyfin:8096`
- API Key: Jellyfin API key

**Radarr:**
- URL: `http://radarr:7878`
- API Key: Radarr API key
- Set quality profile and root folder

**Sonarr:**
- URL: `http://sonarr:8989`
- API Key: Sonarr API key
- Set quality profile and root folder

> Jellyseerr does not natively manage Lidarr. Music requests are handled directly in Lidarr.

### Step G - Jellyfin libraries

**Add libraries:**

In Jellyfin -> Dashboard -> Libraries -> Add Media Library, point to folders under `/data/media`:

| Library | Path |
|---|---|
| Movies | `/data/media/films` |
| Series | `/data/media/series` |
| Music | `/data/media/musique` |

**Arr -> Jellyfin notifications:**

In **Radarr, Sonarr, and Lidarr -> Settings -> Connect -> + -> Emby/Jellyfin**:
- URL: `http://jellyfin:8096`
- API Key: Jellyfin API key
- Enable events: **Import/Download**, **Rename/Upgrade**, **Delete**
- **Test -> Save**

Result: Jellyfin is notified and refreshes immediately after add/update/delete actions.

### Step H - GameVault

- Verify PostgreSQL connectivity (service `gamevault-db`)
- Verify game library mount is `/games` (from `${DATA_DIR}/media/jeux`)
- Trigger a scan/refresh after first Questarr imports

> **PostgreSQL note:** GameVault runs schema migrations automatically on first start. If a previous DB exists, check container logs to ensure migration finished successfully (`make logs SERVICE=gamevault`).

### Step I - Homarr

In Homarr:
- Add widgets for each service
- Use host IP + external port for browser access
- Or use internal Docker hostnames for direct internal communication

---

<a id="section-6"></a>
## 6) Atomic Moves and Hardlinks

Hardlinks allow Radarr/Sonarr/Lidarr to "move" files from torrent folders to media folders **without physically copying data**. The file uses disk space once while being available from multiple paths.

**Required condition:** `torrents/` and `media/` must be on the **same volume** (same filesystem). Moving across filesystems triggers a full copy, temporarily doubling disk usage and slowing processing.

**Recommended `.env` layout:**
```env
DATA_DIR=/mnt/data
```

**Good structure (same root):**
```
/mnt/data/torrents
/mnt/data/media
```

**Bad structure (different roots):**
```
/mnt/torrents
/srv/media
```

---

<a id="section-7"></a>
## 7) Quick validation checklist

- In Prowlarr, each App integration is green (Test OK)
- In Radarr/Sonarr/Lidarr, qBittorrent download client is green
- In Questarr, qBittorrent download client works
- In GameVault, DB connection is healthy and `/games` is readable
- In Jellyseerr, Jellyfin and Services are green
- A Jellyseerr test request creates a task in Radarr/Sonarr
- Downloads appear in qBittorrent

---

<a id="section-8"></a>
## 8) Start, Makefile, and updates

The project includes a Makefile for common operations.

Initialize environment:

```bash
make env
```

This creates `.env` from `.env.example` if missing.

Start the stack:

```bash
make up
```

Start existing containers:

```bash
make start
```

Important behavior:
- If `.env` is missing, `make start` and `make up` trigger `make env` automatically
- If `make start` runs before containers exist, it falls back to `docker compose up -d`

Stop and remove:

```bash
make down
```

Full update:

```bash
make update
```

Single-service update example (Jellyseerr):

```bash
docker compose pull jellyseerr
docker compose up -d jellyseerr
```

Validate configuration:

```bash
make validate
```

---

<a id="section-9"></a>
## 9) Common troubleshooting

### Volume permissions
If a service fails with `EACCES` or `Permission denied`:
- verify permissions in mounted folders under `CONFIG_DIR`
- ensure `PUID` and `PGID` match file ownership
- grant read/write permissions to that user/group

### GameVault v13 migration (`/images` -> `/media`)
If GameVault loops with an error saying `/images` is deprecated:
- mount media volume to `/media` (not `/images`)
- recreate GameVault so new mount is applied

Example:

```bash
docker compose up -d --force-recreate gamevault
docker compose logs -f gamevault
```

Generic permission fix (adapt path):

```bash
docker run --rm -v /path/to/config/service:/target alpine sh -c 'chown -R 1000:1000 /target && chmod -R u+rwX,g+rwX /target'
```

### Useful checks
- `make validate` to check compose syntax
- `make ps` to inspect service state
- `make logs SERVICE=<service_name>` to troubleshoot one service

---

<a id="section-10"></a>
## 10) Security best practices

- Never commit `.env` with real secrets
- Change default admin passwords
- Prefer pinned image tags over `latest` in production
- Expose only strictly required ports
