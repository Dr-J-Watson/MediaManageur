# =============================================================================
# Makefile — Stack Docker Compose
# =============================================================================
# Premier démarrage après git clone :
#   make init
#
# Utilisation courante :
#   make up                     Lance la stack
#   make logs SERVICE=jellyfin  Logs d'un service
#   make shell SERVICE=jellyfin Shell dans un conteneur
#   make help                   Liste toutes les cibles
# =============================================================================

COMPOSE ?= docker compose
SERVICE ?=

# Couleurs (désactivées si pas de TTY)
ifeq ($(shell tput colors 2>/dev/null | grep -q '^[0-9]' && echo yes),yes)
  BOLD  := $(shell tput bold)
  RESET := $(shell tput sgr0)
  GREEN := $(shell tput setaf 2)
  CYAN  := $(shell tput setaf 6)
else
  BOLD  :=
  RESET :=
  GREEN :=
  CYAN  :=
endif

.DEFAULT_GOAL := help

.PHONY: help init env ensure-env ensure-docker ensure-override \
        up down start stop restart \
        pull update clean \
        ps status logs shell \
        config validate \
        interactive configure-services configure-gpu-jellyfin

# -----------------------------------------------------------------------------
# Aide auto-générée depuis les commentaires ##
# -----------------------------------------------------------------------------
help:
	@printf "\n$(BOLD)Stack Docker Compose$(RESET)\n\n"
	@printf "$(CYAN)Démarrage$(RESET)\n"
	@grep -E '^(init|env)[^:]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS=":.*?## "}; {printf "  $(GREEN)%-28s$(RESET) %s\n", $$1, $$2}'
	@printf "\n$(CYAN)Cycle de vie$(RESET)\n"
	@grep -E '^(up|down|start|stop|restart|pull|update|clean)[^:]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS=":.*?## "}; {printf "  $(GREEN)%-28s$(RESET) %s\n", $$1, $$2}'
	@printf "\n$(CYAN)Observation$(RESET)\n"
	@grep -E '^(ps|status|logs|shell)[^:]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS=":.*?## "}; {printf "  $(GREEN)%-28s$(RESET) %s\n", $$1, $$2}'
	@printf "\n$(CYAN)Validation$(RESET)\n"
	@grep -E '^(config|validate)[^:]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS=":.*?## "}; {printf "  $(GREEN)%-28s$(RESET) %s\n", $$1, $$2}'
	@printf "\n$(CYAN)Configuration$(RESET)\n"
	@grep -E '^(interactive|configure)[^:]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS=":.*?## "}; {printf "  $(GREEN)%-28s$(RESET) %s\n", $$1, $$2}'
	@printf "\nVariables : SERVICE=<nom>   ex: make logs SERVICE=jellyfin\n\n"

# -----------------------------------------------------------------------------
# Prérequis
# -----------------------------------------------------------------------------
ensure-docker:
	@command -v docker >/dev/null 2>&1 \
		|| { echo "Erreur: docker non trouvé dans PATH."; exit 1; }

env: ## Crée .env depuis .env.example si absent
	@if [ -f .env ]; then \
		echo ".env existe déjà."; \
	elif [ -f .env.example ]; then \
		cp .env.example .env; \
		echo ".env créé depuis .env.example."; \
	else \
		echo "Erreur: .env.example introuvable."; exit 1; \
	fi

ensure-env:
	@[ -f .env ] || $(MAKE) --no-print-directory env

ensure-override:
	@[ -f docker-compose.override.yml ] || $(MAKE) --no-print-directory init

# -----------------------------------------------------------------------------
# Premier démarrage
# -----------------------------------------------------------------------------
init: ensure-docker env ## Premier démarrage : génère l'override et configure la stack
	./scripts/stack-interactive.sh init

# -----------------------------------------------------------------------------
# Cycle de vie
# -----------------------------------------------------------------------------
up: ensure-docker ensure-env ensure-override ## Lance la stack en arrière-plan
	$(COMPOSE) up -d --no-recreate

down: ensure-docker ## Arrête et supprime les conteneurs
	$(COMPOSE) down

start: ensure-docker ensure-env ensure-override ## Démarre les conteneurs existants (ou up si absents)
	@if [ -n "$$($(COMPOSE) ps -q 2>/dev/null)" ]; then \
		$(COMPOSE) start; \
	else \
		echo "Aucun conteneur actif — exécution de 'up'."; \
		$(COMPOSE) up -d; \
	fi

stop: ensure-docker ## Arrête les conteneurs sans les supprimer
	$(COMPOSE) stop

restart: ensure-docker ensure-env ## Redémarre la stack
	$(COMPOSE) restart

pull: ensure-docker ensure-env ensure-override ## Récupère les dernières images
	$(COMPOSE) pull

update: ensure-docker ensure-env ensure-override ## Pull + recrée les conteneurs (force-recreate)
	$(COMPOSE) pull
	$(COMPOSE) up -d --force-recreate

clean: ensure-docker ## down + suppression des volumes et orphelins
	$(COMPOSE) down --volumes --remove-orphans

# -----------------------------------------------------------------------------
# Observation
# -----------------------------------------------------------------------------
ps: ensure-docker ## État des services
	$(COMPOSE) ps

status: ensure-docker ## État détaillé — services unhealthy mis en évidence
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" \
		| awk 'NR==1 { print; next } \
		       /unhealthy|Exit|Error/ { print "\033[31m" $$0 "\033[0m"; next } \
		       { print }'

logs: ensure-docker ## Logs en continu (SERVICE=<nom> optionnel)
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE) logs -f "$(SERVICE)"; \
	else \
		$(COMPOSE) logs -f; \
	fi

shell: ensure-docker ## Shell dans un conteneur (SERVICE=<nom> requis)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Usage: make shell SERVICE=<nom_du_service>"; exit 1; \
	fi
	$(COMPOSE) exec "$(SERVICE)" sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
config: ensure-docker ensure-env ensure-override ## Affiche la configuration Compose résolue
	$(COMPOSE) config

validate: ensure-docker ensure-env ensure-override ## Vérifie que la configuration Compose est valide
	@$(COMPOSE) config -q && echo "✓ Configuration Compose valide."

# -----------------------------------------------------------------------------
# Configuration interactive
# -----------------------------------------------------------------------------
interactive: ## Menu interactif complet (services + GPU Jellyfin)
	./scripts/stack-interactive.sh

configure-services: ## Choix interactif des services dans l'override
	./scripts/stack-interactive.sh services

configure-gpu-jellyfin: ## Détection GPU + configuration Jellyfin
	./scripts/stack-interactive.sh gpu