# AWS Bootstrap Configuration
# Docker + AWS CLI based bootstrap for AWS infrastructure and GitHub Actions OIDC

.PHONY: help build bootstrap plan destroy clean check test

# Default target
.DEFAULT_GOAL := help

# Variables
DOCKER_IMAGE := aws-bootstrap
AWS_REGION ?= us-east-1
GITHUB_ORG ?= $(shell git remote get-url origin 2>/dev/null | sed -n 's#.*[:/]\([^/]*\)/[^/]*\.git.*#\1#p')

# Colors for output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

help: ## Show this help message
	@echo "$(BLUE) AWS Bootstrap Configuration$(RESET)"
	@echo ""
	@echo "$(YELLOW)Usage:$(RESET) make [target]"
	@echo ""
	@echo "$(YELLOW)Targets:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Environment Variables:$(RESET)"
	@echo "  AWS_ACCESS_KEY_ID      - Your AWS access key"
	@echo "  AWS_SECRET_ACCESS_KEY  - Your AWS secret key"
	@echo "  AWS_REGION            - AWS region (default: us-east-1)"
	@echo "  GITHUB_ORG            - GitHub organization (auto-detected: $(GITHUB_ORG))"
	@echo ""
	@echo "$(YELLOW)Quick Start:$(RESET)"
	@echo "  1. Copy and edit environment: cp .env.example .env"
	@echo "  2. Load environment: source .env"
	@echo "  3. Run bootstrap: make bootstrap"
	@echo ""
	@echo "$(YELLOW)Examples:$(RESET)"
	@echo "  make check       # Validate configuration and credentials"
	@echo "  make plan        # Show what would be created (dry-run)"
	@echo "  make bootstrap   # Create all AWS resources"
	@echo "  make destroy     # Remove all AWS resources"

build: ## Build the Docker image
	@echo "$(BLUE)Building Docker image...$(RESET)"
	docker build -t $(DOCKER_IMAGE) .

check: build ## Validate AWS credentials and configuration
	@echo "$(BLUE)Validating AWS credentials and configuration...$(RESET)"
	$(call run-bootstrap,--dry-run)

plan: check ## Show what resources will be created (dry-run)
	@echo "$(BLUE)Planning infrastructure changes (dry-run)...$(RESET)"
	$(call run-bootstrap,--dry-run)

bootstrap: build ## Create all AWS bootstrap infrastructure
	@echo "$(YELLOW)Creating AWS bootstrap infrastructure...$(RESET)"
	$(call check-env)
	$(call run-bootstrap)

destroy: build ## Destroy all AWS bootstrap infrastructure
	@echo "$(RED) This will destroy all bootstrap infrastructure!$(RESET)"
	$(call check-env)
	$(call run-bootstrap,--destroy)

test: build ## Test AWS connectivity and permissions
	@echo "$(BLUE)Testing AWS connectivity...$(RESET)"
	$(call check-env)
	docker run --rm \
		-v $(PWD):/workspace \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_REGION \
		-e GITHUB_ORG \
		$(DOCKER_IMAGE) \
		bash -c 'echo "Testing AWS connectivity..." && aws sts get-caller-identity && echo "AWS connection successful!"'

clean: ## Clean up Docker resources and local files
	@echo "$(BLUE)Cleaning up...$(RESET)"
	-docker rmi $(DOCKER_IMAGE) 2>/dev/null || true
	-docker system prune -f

# Helper functions
define check-env
	@if [ -z "$$AWS_ACCESS_KEY_ID" ]; then \
		echo "$(RED) Error: AWS_ACCESS_KEY_ID not set$(RESET)"; \
		echo "$(YELLOW)💡 Tip: Copy .env.example to .env and fill in your credentials$(RESET)"; \
		exit 1; \
	fi
	@if [ -z "$$AWS_SECRET_ACCESS_KEY" ]; then \
		echo "$(RED) Error: AWS_SECRET_ACCESS_KEY not set$(RESET)"; \
		echo "$(YELLOW)💡 Tip: Copy .env.example to .env and fill in your credentials$(RESET)"; \
		exit 1; \
	fi
	@if [ -z "$(AWS_REGION)" ]; then \
		echo "$(RED) Error: AWS_REGION not set$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN) Environment variables validated$(RESET)"
endef

define run-bootstrap
	docker run --rm -it \
		-v $(PWD):/workspace \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_REGION \
		-e GITHUB_ORG="$(GITHUB_ORG)" \
		$(DOCKER_IMAGE) \
		./bootstrap.sh $(1)
endef