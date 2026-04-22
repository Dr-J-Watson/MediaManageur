#!/usr/bin/env bash
# stack-interactive.sh — Configuration interactive de la stack
#
# Ce script modifie :
#   - docker-compose.override.yml  (commenter/décommenter les blocs services)
#   - .env                         (commenter/décommenter les variables associées)
#
# Usage :
#   ./scripts/stack-interactive.sh            → menu interactif complet
#   ./scripts/stack-interactive.sh init       → génère l'override si absent, puis menu
#   ./scripts/stack-interactive.sh services   → choix des usages uniquement
#   ./scripts/stack-interactive.sh gpu        → configuration GPU uniquement
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Chemins
# ---------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.yml}"
OVERRIDE_FILE="${OVERRIDE_FILE:-$ROOT_DIR/docker-compose.override.yml}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
ENV_EXAMPLE_FILE="${ENV_EXAMPLE_FILE:-$ROOT_DIR/.env.example}"

# ---------------------------------------------------------------------------
# Signal & utilitaires
# ---------------------------------------------------------------------------
trap 'printf "\nInterrompu.\n"; exit 130' INT

die()  { printf "Erreur: %s\n" "$*" >&2; exit 1; }
info() { printf "  %s\n" "$*"; }
ok()   { printf "✓ %s\n" "$*"; }
warn() { printf "⚠ %s\n" "$*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "commande requise manquante: $1"; }
require_cmd awk
require_cmd mktemp

check_compose()  { [[ -f "$COMPOSE_FILE"  ]] || die "fichier introuvable: $COMPOSE_FILE"; }
check_override() { [[ -f "$OVERRIDE_FILE" ]] || die "fichier introuvable: $OVERRIDE_FILE — lancez: make init"; }
check_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    [[ -f "$ENV_EXAMPLE_FILE" ]] || die "fichier introuvable: $ENV_FILE"
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    ok "$(basename "$ENV_FILE") créé depuis $(basename "$ENV_EXAMPLE_FILE")."
  fi
}

# ---------------------------------------------------------------------------
# Validation post-écriture
# ---------------------------------------------------------------------------
validate_compose() {
  if command -v docker >/dev/null 2>&1; then
    if docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" config -q 2>/dev/null; then
      ok "Configuration Compose valide."
    else
      warn "La configuration Compose semble invalide — vérifiez avec: make validate"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Génération de l'override depuis docker-compose.yml
# ---------------------------------------------------------------------------
generate_override() {
  check_compose

  if [[ -f "$OVERRIDE_FILE" ]]; then
    warn "$(basename "$OVERRIDE_FILE") existe déjà, génération annulée."
    return 0
  fi

  local tmp; tmp="$(mktemp)"

  cat > "$tmp" << 'EOF'
# =============================================================================
# docker-compose.override.yml — Généré depuis docker-compose.yml
#
# Ce fichier est géré par scripts/stack-interactive.sh. 
# Il est ignoré par git (.gitignore) — ne pas le versionner.
#
# Pour régénérer depuis zéro : supprimez ce fichier puis lancez : make init
# Pour reconfigurer          : make interactive
# 
# /
# 
# docker-compose.override.yml — Generated from docker-compose.yml
#
# This file is managed by scripts/stack-interactive.sh.
# It is ignored by git (.gitignore) — do not version it.
#
# To regenerate from scratch: delete this file then run: make init
# To reconfigure          : make interactive
# =============================================================================

EOF

  awk '
    !past_header {
      if (/^services:[[:space:]]*$/) { past_header = 1; print; next }
      next
    }
    {
      n = $0; sub(/^#[[:space:]]?/, "", n)
      if (!in_jf && n ~ /^  jellyfin:[[:space:]]*$/) { in_jf = 1; gpu_done = 0 }
      if (in_jf) {
        if (n ~ /^  [a-zA-Z0-9_.-]+:[[:space:]]*$/ && n !~ /^  jellyfin:[[:space:]]*$/) in_jf = 0
        if (!gpu_done && n ~ /^    restart:/) {
          print "    # >>> GPU_AUTO_CONFIG_START"
          print "    # Pas de configuration GPU dédiée."
          print "    # <<< GPU_AUTO_CONFIG_END"
          gpu_done = 1
        }
      }
      print $0
    }
    END {
      if (in_jf && !gpu_done) {
        print "    # >>> GPU_AUTO_CONFIG_START"
        print "    # Pas de configuration GPU dédiée."
        print "    # <<< GPU_AUTO_CONFIG_END"
      }
    }
  ' "$COMPOSE_FILE" >> "$tmp"

  mv "$tmp" "$OVERRIDE_FILE"
  ok "$(basename "$OVERRIDE_FILE") généré depuis $(basename "$COMPOSE_FILE")."
}

# ---------------------------------------------------------------------------
# Gestion bas niveau des services dans l'override
# ---------------------------------------------------------------------------
is_enabled() {
  grep -Eq "^  ${1}:[[:space:]]*$" "$OVERRIDE_FILE"
}

set_service_state() {
  local service="$1" state="$2"
  local tmp; tmp="$(mktemp)"

  awk -v svc="$service" -v state="$state" '
    function norm(s,    r) { r = s; sub(/^#[[:space:]]?/, "", r); return r }
    function is_svc(s,  n) { n = norm(s); return (n ~ /^  [a-zA-Z0-9_.-]+:[[:space:]]*$/) }
    {
      n = norm($0)
      if (!in_block && n ~ ("^  " svc ":[[:space:]]*$"))                        in_block = 1
      else if (in_block && is_svc($0) && n !~ ("^  " svc ":[[:space:]]*$"))     in_block = 0
      if (in_block) {
        if (state == "disable") { print ($0 ~ /^#/) ? $0 : "# " $0 }
        else { sub(/^#[[:space:]]?/, "", $0); print $0 }
      } else { print $0 }
    }
  ' "$OVERRIDE_FILE" > "$tmp"

  mv "$tmp" "$OVERRIDE_FILE"
}

# ---------------------------------------------------------------------------
# Gestion des variables .env
#
# Une variable n'est commentée que si AUCUN service actif ne la référence.
# ---------------------------------------------------------------------------

# Retourne les services qui utilisent une variable donnée
# Format : "VAR svc1 svc2 ..."  — défini dans la table VAR_OWNERS ci-dessous
declare -A VAR_OWNERS
_init_var_owners() {
  # Variables exclusives à un seul service
  VAR_OWNERS[GLUETUN_VERSION]="gluetun"
  VAR_OWNERS[VPN_PROVIDER]="gluetun"
  VAR_OWNERS[VPN_TYPE]="gluetun"
  VAR_OWNERS[VPN_KEY]="gluetun"
  VAR_OWNERS[VPN_COUNTRY]="gluetun"
  VAR_OWNERS[QBITTORRENT_VERSION]="qbittorrent"
  VAR_OWNERS[QBITTORRENT_PORT]="qbittorrent"
  VAR_OWNERS[PROWLARR_VERSION]="prowlarr"
  VAR_OWNERS[PROWLARR_PORT]="prowlarr"
  VAR_OWNERS[RADARR_VERSION]="radarr"
  VAR_OWNERS[RADARR_PORT]="radarr"
  VAR_OWNERS[SONARR_VERSION]="sonarr"
  VAR_OWNERS[SONARR_PORT]="sonarr"
  VAR_OWNERS[LIDARR_VERSION]="lidarr"
  VAR_OWNERS[LIDARR_PORT]="lidarr"
  VAR_OWNERS[QUESTARR_VERSION]="questarr"
  VAR_OWNERS[QUESTARR_PORT]="questarr"
  VAR_OWNERS[JELLYFIN_VERSION]="jellyfin"
  VAR_OWNERS[JELLYFIN_PORT]="jellyfin"
  VAR_OWNERS[JELLYSEERR_VERSION]="jellyseerr"
  VAR_OWNERS[JELLYSEERR_PORT]="jellyseerr"
  VAR_OWNERS[HOMARR_VERSION]="homarr"
  VAR_OWNERS[HOMARR_PORT]="homarr"
  VAR_OWNERS[FLARESOLVERR_VERSION]="flaresolverr"
  VAR_OWNERS[FLARESOLVERR_PORT]="flaresolverr"
  # Variables partagées entre plusieurs services
  VAR_OWNERS[GAMEVAULT_DB_PASSWORD]="gamevault-db gamevault"
  VAR_OWNERS[GAMEVAULT_VERSION]="gamevault"
  VAR_OWNERS[GAMEVAULT_PORT]="gamevault"
}

# Retourne toutes les variables associées à un service
_vars_for_service() {
  local svc="$1"
  local var owners
  for var in "${!VAR_OWNERS[@]}"; do
    owners="${VAR_OWNERS[$var]}"
    for owner in $owners; do
      if [[ "$owner" == "$svc" ]]; then
        echo "$var"
        break
      fi
    done
  done
}

# Détermine si une variable doit être activée (au moins un de ses owners est actif)
_should_var_be_enabled() {
  local var="$1"
  local owners="${VAR_OWNERS[$var]:-}"
  [[ -z "$owners" ]] && return 0   # variable inconnue : ne pas toucher
  local owner
  for owner in $owners; do
    # On vérifie dans desired[] si ce service sera actif
    if [[ "${desired[$owner]:-0}" == "1" ]]; then
      return 0
    fi
  done
  return 1
}

set_env_var_state() {
  local key="$1" enabled="$2"
  local tmp; tmp="$(mktemp)"

  awk -v k="$key" -v enabled="$enabled" '
    function norm(s,    out) { out = s; sub(/^#[[:space:]]?/, "", out); return out }
    {
      n = norm($0)
      if (n ~ ("^" k "=")) {
        val = substr(n, length(k) + 2)
        if (enabled == "1") print k "=" val
        else                print "# " k "=" val
      } else {
        print $0
      }
    }
  ' "$ENV_FILE" > "$tmp"

  mv "$tmp" "$ENV_FILE"
}

# ---------------------------------------------------------------------------
# Table des usages → services associés
#
# flaresolverr est couplé automatiquement à tout usage qui active prowlarr.
# homarr est géré comme un usage indépendant.
# ---------------------------------------------------------------------------

# Retourne les services requis par un usage (hors flaresolverr géré séparément)
_services_for_usage() {
  case "$1" in
    movies)     echo "gluetun qbittorrent prowlarr radarr" ;;
    series)     echo "gluetun qbittorrent prowlarr sonarr" ;;
    music)      echo "gluetun qbittorrent prowlarr lidarr" ;;
    games)      echo "gluetun qbittorrent questarr gamevault-db gamevault" ;;
    jellyfin)   echo "jellyfin" ;;
    jellyseerr) echo "jellyseerr" ;;
    homarr)     echo "homarr" ;;
    *)          echo "" ;;
  esac
}

# Détermine l'état par défaut d'un usage d'après l'override existant
_usage_default() {
  local probe
  case "$1" in
    movies)     probe="radarr" ;;
    series)     probe="sonarr" ;;
    music)      probe="lidarr" ;;
    games)      probe="questarr" ;;
    jellyfin)   probe="jellyfin" ;;
    jellyseerr) probe="jellyseerr" ;;
    homarr)     probe="homarr" ;;
    *)          echo "n"; return ;;
  esac
  is_enabled "$probe" && echo "y" || echo "n"
}

# ---------------------------------------------------------------------------
# Application d'une sélection d'usages
# Reçoit un tableau associatif usage→0/1 (passé via les variables globales)
# ---------------------------------------------------------------------------
declare -A desired   # service → 0|1, calculé par apply_usage_selection

apply_usage_selection() {
  # Réinitialise tous les services connus à 0
  local all_services="gluetun qbittorrent prowlarr radarr sonarr lidarr questarr gamevault-db gamevault jellyfin jellyseerr homarr flaresolverr"
  local svc
  for svc in $all_services; do desired["$svc"]=0; done

  # Active les services requis par chaque usage sélectionné
  local usage
  for usage in movies series music games jellyfin jellyseerr homarr; do
    local var="enable_${usage//-/_}"
    if [[ "${!var:-0}" == "1" ]]; then
      for svc in $(_services_for_usage "$usage"); do
        desired["$svc"]=1
      done
    fi
  done

  # flaresolverr : actif si prowlarr est actif
  [[ "${desired[prowlarr]:-0}" == "1" ]] && desired["flaresolverr"]=1

  # Applique l'état dans l'override
  for svc in $all_services; do
    if [[ "${desired[$svc]}" == "1" ]]; then
      set_service_state "$svc" "enable"
    else
      set_service_state "$svc" "disable"
    fi
  done

  # Applique l'état dans .env (logique partagée : commentée seulement si tous owners inactifs)
  local var
  for var in "${!VAR_OWNERS[@]}"; do
    if _should_var_be_enabled "$var"; then
      set_env_var_state "$var" "1"
    else
      set_env_var_state "$var" "0"
    fi
  done
}

# ---------------------------------------------------------------------------
# Configuration interactive des usages
# ---------------------------------------------------------------------------
configure_services_interactive() {
  check_override
  check_env
  _init_var_owners

  printf "\n=== Configuration par usage ===\n"
  printf "Active/désactive automatiquement les services et variables .env associés.\n\n"

  local usage label default
  declare -A labels=(
    [movies]="Téléchargement de films          (Radarr)"
    [series]="Téléchargement de séries         (Sonarr)"
    [music]="Téléchargement de musique        (Lidarr)"
    [games]="Téléchargement de jeux  [BETA]   (Questarr + GameVault)"
    [jellyfin]="Lecture via Jellyfin"
    [jellyseerr]="Portail de demandes              (Jellyseerr)"
    [homarr]="Tableau de bord central          (Homarr)"
  )

  printf "Usages stables :\n"
  for usage in movies series music jellyfin jellyseerr homarr; do
    default="$(_usage_default "$usage")"
    label="${labels[$usage]}"

    local var="enable_${usage//-/_}"
    if prompt_yes_no "  $label" "$default"; then
      declare -g "$var=1"
    else
      declare -g "$var=0"
    fi
  done

  printf "\n"
  warn "Le téléchargement de jeux est en phase de test (services Questarr + GameVault), à n'activer que si vous êtes prêt à rencontrer des bugs et à contribuer à leur résolution.\n"
  printf "\n"

  usage="games"
  default="$(_usage_default "$usage")"
  label="${labels[$usage]}"
  local var="enable_${usage//-/_}"
  if prompt_yes_no "  $label" "$default"; then
    declare -g "$var=1"
  else
    declare -g "$var=0"
  fi

  apply_usage_selection

  printf "\n=== Résumé ===\n"
  local state
  for usage in movies series music games jellyfin jellyseerr homarr; do
    local var="enable_${usage//-/_}"
    state="$([[ "${!var}" == "1" ]] && echo "actif" || echo "inactif")"
    info "${labels[$usage]} : $state"
  done
  info "FlareSolverr (Prowlarr bypass)   : $([[ "${desired[flaresolverr]:-0}" == "1" ]] && echo "actif (couplé)" || echo "inactif")"

  printf "\n"
  ok "Override mis à jour : $(basename "$OVERRIDE_FILE")"
  ok ".env mis à jour     : $(basename "$ENV_FILE")"
  validate_compose
}

# ---------------------------------------------------------------------------
# Détection GPU
# ---------------------------------------------------------------------------
detect_nvidia() {
  _nvidia_found=0; _nvidia_usable=0
  if command -v nvidia-smi >/dev/null 2>&1; then
    _nvidia_found=1
    nvidia-smi -L >/dev/null 2>&1 && _nvidia_usable=1 || true
  fi
}

detect_dri() {
  _dri_found=0
  ls /dev/dri/renderD* >/dev/null 2>&1 && _dri_found=1 || true
}

check_nvidia_docker_runtime() {
  command -v docker >/dev/null 2>&1 || { echo "no-docker"; return; }
  docker info 2>/dev/null | grep -Eq '^ *Runtimes:.*\bnvidia\b' && echo "ok" || echo "missing"
}

print_gpu_summary() {
  printf "\n=== Vérification GPU / drivers ===\n"
  if [[ "$_nvidia_found" == 1 ]]; then
    info "NVIDIA détecté       : oui"
    if [[ "$_nvidia_usable" == 1 ]]; then
      info "Driver NVIDIA (smi)  : ok"
      case "$(check_nvidia_docker_runtime)" in
        ok)        info "Runtime Docker nvidia: présent" ;;
        missing)   warn "Runtime Docker nvidia: absent → installer nvidia-container-toolkit" ;;
        no-docker) warn "Docker non trouvé dans PATH" ;;
      esac
      [[ -e /dev/nvidiactl ]] && info "/dev/nvidiactl       : présent" \
                               || warn "/dev/nvidiactl       : absent"
    else
      warn "Driver NVIDIA (smi)  : non utilisable"
    fi
  else
    info "NVIDIA détecté       : non"
  fi

  if [[ "$_dri_found" == 1 ]]; then
    info "/dev/dri renderD*    : présents"
    ls -1 /dev/dri/renderD* 2>/dev/null | sed 's/^/      /'
  else
    info "/dev/dri renderD*    : absents"
  fi

  if command -v lspci >/dev/null 2>&1; then
    local gpus; gpus="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
    if [[ -n "$gpus" ]]; then
      info "GPU via lspci        :"; echo "$gpus" | sed 's/^/      /'
    else
      info "GPU via lspci        : aucun détecté"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Bloc GPU YAML
# ---------------------------------------------------------------------------
build_gpu_block() {
  local mode="$1" ids="$2"
  case "$mode" in
    nvidia)
      if [[ "$ids" == "all" ]]; then
        printf '    deploy:\n'
        printf '      resources:\n'
        printf '        reservations:\n'
        printf '          devices:\n'
        printf '            - driver: nvidia\n'
        printf '              count: all\n'
        printf '              capabilities: [gpu]\n'
      else
        local ids_json
        ids_json="$(awk -v v="$ids" 'BEGIN {
          n = split(v, a, ","); s = "["
          for (i=1;i<=n;i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/,"",a[i])
            if (a[i]=="") continue
            s = s (s=="[" ? "" : ", ") "\"" a[i] "\""
          }
          print s "]"
        }')"
        printf '    deploy:\n'
        printf '      resources:\n'
        printf '        reservations:\n'
        printf '          devices:\n'
        printf '            - driver: nvidia\n'
        printf '              device_ids: %s\n' "$ids_json"
        printf '              capabilities: [gpu]\n'
      fi ;;
    dri)
      printf '    devices:\n'
      printf '      - /dev/dri:/dev/dri\n' ;;
    none)
      printf '    # Pas de configuration GPU dédiée.\n' ;;
  esac
}

apply_gpu_block() {
  local mode="$1" ids="$2"
  local new_block; new_block="$(build_gpu_block "$mode" "$ids")"
  local tmp; tmp="$(mktemp)"

  awk -v new_block="$new_block" '
    function norm(s,    r) { r=s; sub(/^#[[:space:]]?/,"",r); return r }
    function is_svc(s,  n) { n=norm(s); return (n ~ /^  [a-zA-Z0-9_.-]+:[[:space:]]*$/) }
    function emit(prefix,    i,n,arr,line) {
      n = split(new_block, arr, "\n")
      print prefix "    # >>> GPU_AUTO_CONFIG_START"
      for (i=1;i<=n;i++) { line=arr[i]; if (line!="") print prefix line }
      print prefix "    # <<< GPU_AUTO_CONFIG_END"
    }
    {
      n = norm($0)
      if (!in_jf && n ~ /^  jellyfin:[[:space:]]*$/) {
        in_jf=1; jf_prefix=($0~/^#/) ? "# " : ""; done=0
      }
      if (in_jf && is_svc($0) && n !~ /^  jellyfin:[[:space:]]*$/) {
        if (!done) { emit(jf_prefix); done=1 }
        in_jf=0
      }
      if (in_jf) {
        if (n ~ /^[[:space:]]*# >>> GPU_AUTO_CONFIG_START[[:space:]]*$/) {
          in_old=1; if (!done) { emit(jf_prefix); done=1 }; next
        }
        if (in_old) {
          if (n ~ /^[[:space:]]*# <<< GPU_AUTO_CONFIG_END[[:space:]]*$/) in_old=0
          next
        }
        if (!done && norm($0) ~ /^    restart:/) { emit(jf_prefix); done=1 }
      }
      print $0
    }
    END { if (in_jf && !done) emit(jf_prefix) }
  ' "$OVERRIDE_FILE" > "$tmp"

  mv "$tmp" "$OVERRIDE_FILE"
}

configure_gpu_interactive() {
  check_override
  detect_nvidia; detect_dri
  print_gpu_summary

  local suggested="none"
  [[ "$_nvidia_found" == 1 && "$_nvidia_usable" == 1 ]] && suggested="nvidia"
  [[ "$suggested" == "none" && "$_dri_found" == 1 ]]    && suggested="dri"

  printf "\n=== Configuration GPU pour Jellyfin ===\n"
  printf "  1) Auto-détecté  (recommandé : %s)\n" "$suggested"
  printf "  2) NVIDIA\n"
  printf "  3) Intel / AMD   (/dev/dri)\n"
  printf "  4) Aucun GPU\n\n"

  local choice mode
  read -r -p "Votre choix [1-4] (défaut: 1) : " choice || true
  choice="${choice:-1}"
  case "$choice" in
    1) mode="$suggested" ;; 2) mode="nvidia" ;;
    3) mode="dri"        ;; 4) mode="none"   ;;
    *) warn "Choix invalide, mode auto appliqué."; mode="$suggested" ;;
  esac

  local ids="all"
  if [[ "$mode" == "nvidia" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    local gpu_list; gpu_list="$(nvidia-smi --query-gpu=index,name --format=csv,noheader 2>/dev/null || true)"
    if [[ -n "$gpu_list" ]]; then
      printf "\nGPU NVIDIA disponibles :\n"; echo "$gpu_list" | sed 's/^/  - /'
      read -r -p "NVIDIA_VISIBLE_DEVICES (all ou ex: 0,1) [all] : " ids || true
      ids="${ids:-all}"
    else
      warn "Impossible de lister les GPU via nvidia-smi, utilisation de 'all'."
    fi
  fi

  apply_gpu_block "$mode" "$ids"

  printf "\n"; ok "Configuration GPU Jellyfin appliquée : mode=$mode"
  [[ "$mode" == "nvidia" ]] && info "NVIDIA_VISIBLE_DEVICES=$ids"
  if [[ "$mode" == "nvidia" && "$(check_nvidia_docker_runtime)" != "ok" ]]; then
    warn "Runtime nvidia Docker non détecté — le transcodage GPU risque d'échouer."
    info "→ Installez nvidia-container-toolkit puis relancez Docker."
  fi
  validate_compose
}

# ---------------------------------------------------------------------------
# Prompt oui / non
# ---------------------------------------------------------------------------
prompt_yes_no() {
  local prompt="$1" default="$2" answer
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "$prompt [O/n] : " answer || { printf "\n"; return 1; }
      answer="${answer:-O}"
    else
      read -r -p "$prompt [o/N] : " answer || { printf "\n"; return 1; }
      answer="${answer:-N}"
    fi
    case "${answer,,}" in
      o|oui|y|yes) return 0 ;;
      n|non|no)    return 1 ;;
      *) info "Réponse invalide, répondre o ou n." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Menu principal
# ---------------------------------------------------------------------------
main_menu() {
  while true; do
    printf "\n"
    printf "╔══════════════════════════════════════╗\n"
    printf "║     Configuration de la stack        ║\n"
    printf "╠══════════════════════════════════════╣\n"
    printf "║  1) Usages actifs (override + .env)  ║\n"
    printf "║  2) GPU Jellyfin                     ║\n"
    printf "║  3) Tout configurer (1 puis 2)       ║\n"
    printf "║  4) Quitter                          ║\n"
    printf "╚══════════════════════════════════════╝\n"
    local choice
    read -r -p "Votre choix [1-4] : " choice || break
    case "${choice:-}" in
      1) configure_services_interactive ;;
      2) configure_gpu_interactive ;;
      3) configure_services_interactive; configure_gpu_interactive ;;
      4) break ;;
      *) warn "Choix invalide." ;;
    esac
  done
  printf "\nTerminé. Pour vérifier : make validate\n"
}

# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------
case "${1:-}" in
  init)     generate_override; main_menu ;;
  services) configure_services_interactive ;;
  gpu)      configure_gpu_interactive ;;
  "")       main_menu ;;
  *)        die "Usage: $0 [init|services|gpu]" ;;
esac