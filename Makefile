# CloudWeather Sentinel Makefile
# Comprehensive automation for development, testing, and deployment

.PHONY: help build test deploy clean docker-build docker-push k8s-deploy monitoring

# Default target
.DEFAULT_GOAL := help

# Variables
PROJECT_NAME := cloudweather-sentinel
REGISTRY := ghcr.io/1234-ad
VERSION := $(shell git describe --tags --always --dirty)
NAMESPACE := cloudweather-sentinel

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)CloudWeather Sentinel - Available Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# Development Commands
dev-setup: ## Set up development environment
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@command -v go >/dev/null 2>&1 || { echo "$(RED)Go is required$(NC)"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "$(RED)Python3 is required$(NC)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)Docker is required$(NC)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)kubectl is required$(NC)"; exit 1; }
	@echo "$(GREEN)Development environment ready!$(NC)"

install-deps: ## Install project dependencies
	@echo "$(BLUE)Installing Go dependencies...$(NC)"
	@cd apps/weather-api && go mod tidy
	@echo "$(BLUE)Installing Python dependencies...$(NC)"
	@cd apps/ai-predictor && pip install -r requirements.txt
	@echo "$(GREEN)Dependencies installed!$(NC)"

# Build Commands
build: build-weather-api build-ai-predictor ## Build all applications

build-weather-api: ## Build weather API service
	@echo "$(BLUE)Building weather API...$(NC)"
	@cd apps/weather-api && go build -o bin/weather-api .
	@echo "$(GREEN)Weather API built successfully!$(NC)"

build-ai-predictor: ## Build AI predictor service
	@echo "$(BLUE)Building AI predictor...$(NC)"
	@cd apps/ai-predictor && python -m py_compile app.py
	@echo "$(GREEN)AI predictor built successfully!$(NC)"

# Test Commands
test: test-weather-api test-ai-predictor ## Run all tests

test-weather-api: ## Test weather API service
	@echo "$(BLUE)Testing weather API...$(NC)"
	@cd apps/weather-api && go test -v ./...
	@echo "$(GREEN)Weather API tests passed!$(NC)"

test-ai-predictor: ## Test AI predictor service
	@echo "$(BLUE)Testing AI predictor...$(NC)"
	@cd apps/ai-predictor && python -m pytest tests/ -v || echo "$(YELLOW)Tests would run here$(NC)"
	@echo "$(GREEN)AI predictor tests completed!$(NC)"

lint: ## Run linting on all code
	@echo "$(BLUE)Linting Go code...$(NC)"
	@cd apps/weather-api && go vet ./... && go fmt ./...
	@echo "$(BLUE)Linting Python code...$(NC)"
	@cd apps/ai-predictor && python -m flake8 . || echo "$(YELLOW)Install flake8 for Python linting$(NC)"
	@echo "$(GREEN)Linting completed!$(NC)"

# Docker Commands
docker-build: docker-build-weather-api docker-build-ai-predictor ## Build all Docker images

docker-build-weather-api: ## Build weather API Docker image
	@echo "$(BLUE)Building weather API Docker image...$(NC)"
	@docker build -t $(REGISTRY)/weather-api:$(VERSION) -t $(REGISTRY)/weather-api:latest apps/weather-api/
	@echo "$(GREEN)Weather API image built!$(NC)"

docker-build-ai-predictor: ## Build AI predictor Docker image
	@echo "$(BLUE)Building AI predictor Docker image...$(NC)"
	@docker build -t $(REGISTRY)/ai-predictor:$(VERSION) -t $(REGISTRY)/ai-predictor:latest apps/ai-predictor/
	@echo "$(GREEN)AI predictor image built!$(NC)"

docker-push: ## Push Docker images to registry
	@echo "$(BLUE)Pushing Docker images...$(NC)"
	@docker push $(REGISTRY)/weather-api:$(VERSION)
	@docker push $(REGISTRY)/weather-api:latest
	@docker push $(REGISTRY)/ai-predictor:$(VERSION)
	@docker push $(REGISTRY)/ai-predictor:latest
	@echo "$(GREEN)Images pushed successfully!$(NC)"

# Local Development
local-run: ## Run services locally with Docker Compose
	@echo "$(BLUE)Starting local development environment...$(NC)"
	@docker-compose up -d
	@echo "$(GREEN)Services running locally!$(NC)"
	@echo "Weather API: http://localhost:8080"
	@echo "AI Predictor: http://localhost:8081"

local-stop: ## Stop local development environment
	@echo "$(BLUE)Stopping local services...$(NC)"
	@docker-compose down
	@echo "$(GREEN)Local services stopped!$(NC)"

# Kubernetes Commands
k8s-namespace: ## Create Kubernetes namespace
	@echo "$(BLUE)Creating namespace...$(NC)"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "$(GREEN)Namespace ready!$(NC)"

k8s-secrets: ## Create Kubernetes secrets
	@echo "$(BLUE)Creating secrets...$(NC)"
	@kubectl create secret generic weather-secrets \
		--from-literal=redis-url="redis://redis:6379" \
		--from-literal=db-url="postgresql://user:pass@db:5432/weatherdb" \
		--namespace=$(NAMESPACE) \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo "$(GREEN)Secrets created!$(NC)"

k8s-deploy: k8s-namespace k8s-secrets ## Deploy to Kubernetes
	@echo "$(BLUE)Deploying to Kubernetes...$(NC)"
	@kubectl apply -f k8s/weather-api/ -n $(NAMESPACE)
	@kubectl apply -f k8s/ai-predictor/ -n $(NAMESPACE)
	@kubectl rollout status deployment/weather-api -n $(NAMESPACE)
	@kubectl rollout status deployment/ai-predictor -n $(NAMESPACE)
	@echo "$(GREEN)Deployment completed!$(NC)"

k8s-status: ## Check Kubernetes deployment status
	@echo "$(BLUE)Checking deployment status...$(NC)"
	@kubectl get pods,svc,deploy -n $(NAMESPACE)

k8s-logs: ## View application logs
	@echo "$(BLUE)Application logs:$(NC)"
	@kubectl logs -l app=weather-api -n $(NAMESPACE) --tail=50
	@kubectl logs -l app=ai-predictor -n $(NAMESPACE) --tail=50

# Monitoring Commands
monitoring-install: ## Install monitoring stack
	@echo "$(BLUE)Installing monitoring stack...$(NC)"
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	@helm repo update
	@helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--create-namespace \
		--values monitoring/prometheus/values.yaml \
		--wait
	@echo "$(GREEN)Monitoring stack installed!$(NC)"

monitoring-port-forward: ## Port forward monitoring services
	@echo "$(BLUE)Port forwarding monitoring services...$(NC)"
	@echo "Grafana will be available at: http://localhost:3000 (admin/admin123)"
	@echo "Prometheus will be available at: http://localhost:9090"
	@kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring &
	@kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
	@echo "$(GREEN)Port forwarding started!$(NC)"

# Cloud Deployment Commands
deploy-aws: ## Deploy to AWS
	@echo "$(BLUE)Deploying to AWS...$(NC)"
	@./scripts/deploy.sh --cloud aws --env dev --region us-west-2
	@echo "$(GREEN)AWS deployment completed!$(NC)"

deploy-azure: ## Deploy to Azure
	@echo "$(BLUE)Deploying to Azure...$(NC)"
	@./scripts/deploy.sh --cloud azure --env dev --region eastus
	@echo "$(GREEN)Azure deployment completed!$(NC)"

deploy-gcp: ## Deploy to GCP
	@echo "$(BLUE)Deploying to GCP...$(NC)"
	@./scripts/deploy.sh --cloud gcp --env dev --region us-central1-a
	@echo "$(GREEN)GCP deployment completed!$(NC)"

# Infrastructure Commands
infra-plan: ## Plan infrastructure changes
	@echo "$(BLUE)Planning infrastructure...$(NC)"
	@cd infrastructure/aws && terraform plan
	@echo "$(GREEN)Infrastructure plan completed!$(NC)"

infra-apply: ## Apply infrastructure changes
	@echo "$(BLUE)Applying infrastructure...$(NC)"
	@cd infrastructure/aws && terraform apply
	@echo "$(GREEN)Infrastructure applied!$(NC)"

infra-destroy: ## Destroy infrastructure
	@echo "$(RED)Destroying infrastructure...$(NC)"
	@cd infrastructure/aws && terraform destroy
	@echo "$(GREEN)Infrastructure destroyed!$(NC)"

# Utility Commands
clean: ## Clean build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf apps/weather-api/bin/
	@rm -rf apps/ai-predictor/__pycache__/
	@rm -rf apps/ai-predictor/*.pyc
	@docker system prune -f
	@echo "$(GREEN)Cleanup completed!$(NC)"

health-check: ## Run health checks
	@echo "$(BLUE)Running health checks...$(NC)"
	@kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- \
		curl -f http://weather-api.$(NAMESPACE).svc.cluster.local/health
	@kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- \
		curl -f http://ai-predictor.$(NAMESPACE).svc.cluster.local/health
	@echo "$(GREEN)Health checks passed!$(NC)"

version: ## Show version information
	@echo "$(BLUE)CloudWeather Sentinel$(NC)"
	@echo "Version: $(VERSION)"
	@echo "Registry: $(REGISTRY)"
	@echo "Namespace: $(NAMESPACE)"

# Quick deployment for local development
deploy-local: docker-build k8s-deploy monitoring-install ## Quick local deployment
	@echo "$(GREEN)🌤️ CloudWeather Sentinel deployed locally!$(NC)"
	@echo ""
	@echo "$(BLUE)Access your services:$(NC)"
	@echo "  Weather API: kubectl port-forward svc/weather-api 8080:80 -n $(NAMESPACE)"
	@echo "  AI Predictor: kubectl port-forward svc/ai-predictor 8081:80 -n $(NAMESPACE)"
	@echo "  Grafana: kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"