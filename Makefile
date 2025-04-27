WORKFLOW_DIR := workflows
N8N_PORT := 5678
N8N_IMAGE := n8nio/n8n:latest
CONTAINER_NAME := n8n-dev
GH_TOKEN_FILE := secrets/.gh_token
GH_WORKFLOW_SYNC_SECRETS_NAME := "Sync Secrets"
GH_WORKFLOW_FILE := sync-secrets.yml
GH_ARTIFACT_NAME := "secrets-files"

# Main command to run a specific workflow
run:
	@if [ -z "$(workflow)" ]; then \
		echo "Uso: make run workflow=<nome-do-workflow>"; \
		exit 1; \
	fi; \
	if [ ! -f "$(WORKFLOW_DIR)/$(workflow).json" ]; then \
		echo "Erro: Workflow '$(workflow).json' não encontrado em $(WORKFLOW_DIR)/"; \
		exit 1; \
	fi; \
	echo "Iniciando n8n com o workflow: $(workflow)"; \
	docker-compose -f docker/docker-compose.yml up -d; \
	sleep 5; \
	docker exec -i $(CONTAINER_NAME) n8n import:workflow --input /home/node/.n8n/workflows/$(workflow).json

# Start the n8n environment without importing workflows
start:
	@echo "Iniciando ambiente n8n..."
	@docker-compose -f docker/docker-compose.yml up -d

# Stop the environment
stop:
	@echo "Parando ambiente n8n..."
	@docker-compose -f docker/docker-compose.yml down

# Restart the environment
restart: stop start

# Clean the environment (remove volumes)
clean:
	@echo "Cleaning up n8n environment..."
	@docker-compose -f docker/docker-compose.yml down -v

# Generate encryption key for n8n
generate-n8n-key:
	@echo "Generating N8N_ENCRYPTION_KEY..."
	@mkdir -p secrets
	@if command -v node > /dev/null; then \
		KEY=$$(node -e "console.log(require('crypto').randomBytes(24).toString('hex'))"); \
	elif command -v openssl > /dev/null; then \
		KEY=$$(openssl rand -hex 24); \
	else \
		echo "Error: Neither Node.js nor OpenSSL are available to generate a secure key."; \
		exit 1; \
	fi; \
	echo "Generated key: $$KEY"; \
	if [ -f secrets/.env ]; then \
		sed -i.bak "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$$KEY/" secrets/.env && rm -f secrets/.env.bak || true; \
		echo "File secrets/.env updated with the new key."; \
	else \
		echo "N8N_ENCRYPTION_KEY=$$KEY" > secrets/.env; \
		echo "File secrets/.env created with the new key."; \
	fi; \
	echo ""; \
	echo "IMPORTANT: If you already have saved credentials, this new key will invalidate all of them."; \
	echo "To use with GitHub Actions, add the key as a secret:"; \
	echo "gh secret set N8N_ENCRYPTION_KEY -b \"$$KEY\"";


# Install development dependencies
setup:
	@echo "Setting up development environment..."
	@cp --update=none secrets/.env.example secrets/.env || true
	@cp --update=none secrets/credentials.json.example secrets/credentials.json || true
	@echo "Configuration files created. Please edit them with your secrets."

# Synchronize GitHub secrets
sync-secrets:
	echo "Triggering GitHub Actions workflow '$(GH_WORKFLOW_SYNC_SECRETS_NAME)' on branch main…"; 
	gh workflow run $(GH_WORKFLOW_SYNC_SECRETS_NAME) --ref main; 
	
	@echo "🔎 Waiting for workflow to start..."; \
	sleep 5

	@echo "Fetching latest run ID for '$(GH_WORKFLOW_SYNC_SECRETS_NAME)'…"; \
	RUN_ID=$$(gh run list --workflow=$(GH_WORKFLOW_SYNC_SECRETS_NAME) --limit 1 --json databaseId --jq '.[0].databaseId'); \
	if [ -z "$$RUN_ID" ]; then \
		echo "❌ Failed to get run ID"; \
		exit 1; \
	fi; \
	echo "▶️ Watching run $$RUN_ID…"; \
	gh run watch $$RUN_ID --exit-status

	@echo "⬇️ Downloading secrets..."
	@mkdir -p secrets 
	@gh run download $$RUN_ID --name $(GH_ARTIFACT_NAME) --dir secrets  || \
	(echo "⚠️ Could not download artifact $(GH_ARTIFACT_NAME), trying alternative names..." && \
	gh run download $$RUN_ID --dir secrets --pattern '.env')  # Tenta alternativas
	
	@if [ -f "secrets/.env" ]; then \
		echo "✅ Secrets downloaded successfully"; \
	elif [ -d "secrets/secrets" ]; then \
		mv secrets/secrets/.env secrets/; \
		rm -rf secrets/secrets; \
		echo "✅ Secrets reorganized and downloaded"; \
	else \
		echo "❌ No .env file found in artifacts"; \
		exit 1; \
	fi


# List available workflows
list:
	@echo "Available workflows:"
	@ls -1 $(WORKFLOW_DIR)/*.json | sed 's|^$(WORKFLOW_DIR)/||' | sed 's/.json$$//'

# Create a new workflow
create:
	@if [ -z "$(name)" ]; then \
		echo "Usage: make create name=<workflow-name>"; \
		exit 1; \
	fi; \
	touch $(WORKFLOW_DIR)/$(name).json; \
	echo "Workflow $(name).json created in $(WORKFLOW_DIR)/"

help:
	@echo "Available commands:"
	@echo "  make run workflow=<name>   - Runs a specific workflow"
	@echo "  make start                 - Starts the n8n environment"
	@echo "  make stop                  - Stops the n8n environment"
	@echo "  make restart               - Restarts the n8n environment"
	@echo "  make clean                 - Removes containers and volumes"
	@echo "  make setup                 - Sets up the development environment"
	@echo "  make sync-secrets          - Synchronizes GitHub secrets"
	@echo "  make setup-github-sync     - Sets up automatic synchronization via GitHub Actions"
	@echo "  make list                  - Lists available workflows"
	@echo "  make create name=<name>    - Creates a new workflow"
