COMPOSE ?= docker compose
SERVICE ?=

.PHONY: help env ensure-env up down start stop restart pull ps logs config validate update clean

help:
	@echo "Targets disponibles:"
	@echo "  make env       - Cree .env depuis .env.example si absent"
	@echo "  make up        - Lance la stack en arriere-plan"
	@echo "  make down      - Arrete et supprime les conteneurs"
	@echo "  make start     - Demarre les conteneurs (ou fait up si non initialises)"
	@echo "  make stop      - Arrete les conteneurs"
	@echo "  make restart   - Redemarre la stack"
	@echo "  make pull      - Recupere les dernieres images"
	@echo "  make ps        - Affiche l'etat des services"
	@echo "  make logs      - Affiche les logs (SERVICE=<nom> optionnel)"
	@echo "  make config    - Affiche la config Docker Compose resolue"
	@echo "  make validate  - Verifie que la config Compose est valide"
	@echo "  make update    - Pull + recreation des conteneurs"
	@echo "  make clean     - down + suppression des volumes orphelins"

env:
	@if [ -f .env ]; then \
		echo ".env existe deja."; \
	elif [ -f .env.example ]; then \
		cp .env.example .env; \
		echo ".env cree depuis .env.example."; \
	else \
		echo "Erreur: .env.example introuvable."; \
		exit 1; \
	fi

ensure-env:
	@if [ ! -f .env ]; then \
		$(MAKE) env; \
	fi

up: ensure-env
	$(COMPOSE) up -d --no-recreate

down:
	$(COMPOSE) down

start: ensure-env
	@if [ -n "$$($(COMPOSE) ps -a --services 2>/dev/null)" ]; then \
		$(COMPOSE) start; \
	else \
		echo "Aucun conteneur trouve pour ce projet: execution de '$(COMPOSE) up -d'."; \
		$(COMPOSE) up -d; \
	fi

stop:
	$(COMPOSE) stop

restart: ensure-env
	$(COMPOSE) restart

pull: ensure-env
	$(COMPOSE) pull

ps:
	$(COMPOSE) ps

logs:
	@if [ -n "$(SERVICE)" ]; then \
		$(COMPOSE) logs -f $(SERVICE); \
	else \
		$(COMPOSE) logs -f; \
	fi

config: ensure-env
	$(COMPOSE) config

validate: ensure-env
	$(COMPOSE) config -q
	@echo "Configuration Compose valide."

update: ensure-env
	$(COMPOSE) pull
	$(COMPOSE) up -d

clean:
	$(COMPOSE) down --volumes --remove-orphans
