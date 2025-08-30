#!/bin/bash

set -e

# CloudWeather Sentinel Deployment Script
# Supports AWS, Azure, and GCP deployments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CLOUD_PROVIDER="aws"
ENVIRONMENT="dev"
REGION=""
NAMESPACE="cloudweather-sentinel"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
CloudWeather Sentinel Deployment Script

Usage: $0 [OPTIONS]

Options:
    -c, --cloud PROVIDER    Cloud provider (aws|azure|gcp) [default: aws]
    -e, --env ENVIRONMENT   Environment (dev|staging|prod) [default: dev]
    -r, --region REGION     Cloud region
    -n, --namespace NAME    Kubernetes namespace [default: cloudweather-sentinel]
    -h, --help             Show this help message

Examples:
    $0 --cloud aws --env dev --region us-west-2
    $0 --cloud azure --env prod --region eastus
    $0 --cloud gcp --env staging --region us-central1-a

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local tools=("kubectl" "helm" "terraform" "docker")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done
    
    # Check cloud CLI tools
    case $CLOUD_PROVIDER in
        aws)
            if ! command -v aws &> /dev/null; then
                log_error "AWS CLI is required for AWS deployment"
                exit 1
            fi
            ;;
        azure)
            if ! command -v az &> /dev/null; then
                log_error "Azure CLI is required for Azure deployment"
                exit 1
            fi
            ;;
        gcp)
            if ! command -v gcloud &> /dev/null; then
                log_error "Google Cloud CLI is required for GCP deployment"
                exit 1
            fi
            ;;
    esac
    
    log_success "Prerequisites check passed"
}

setup_infrastructure() {
    log_info "Setting up infrastructure for $CLOUD_PROVIDER..."
    
    cd "$PROJECT_ROOT/infrastructure/$CLOUD_PROVIDER"
    
    # Initialize Terraform
    terraform init
    
    # Plan infrastructure
    terraform plan -var="environment=$ENVIRONMENT" -var="region=$REGION"
    
    # Apply infrastructure
    log_info "Applying infrastructure changes..."
    terraform apply -auto-approve -var="environment=$ENVIRONMENT" -var="region=$REGION"
    
    log_success "Infrastructure setup completed"
}

configure_kubernetes() {
    log_info "Configuring Kubernetes access..."
    
    case $CLOUD_PROVIDER in
        aws)
            aws eks update-kubeconfig --region "$REGION" --name "cloudweather-sentinel-cluster"
            ;;
        azure)
            az aks get-credentials --resource-group "cloudweather-sentinel-rg" --name "cloudweather-sentinel-cluster"
            ;;
        gcp)
            gcloud container clusters get-credentials "cloudweather-sentinel-cluster" --zone "$REGION"
            ;;
    esac
    
    # Verify connection
    kubectl cluster-info
    
    log_success "Kubernetes access configured"
}

deploy_applications() {
    log_info "Deploying applications..."
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy secrets (in real scenario, use proper secret management)
    kubectl create secret generic weather-secrets \
        --from-literal=redis-url="redis://redis:6379" \
        --from-literal=db-url="postgresql://user:pass@db:5432/weatherdb" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy applications
    kubectl apply -f "$PROJECT_ROOT/k8s/weather-api/" -n "$NAMESPACE"
    kubectl apply -f "$PROJECT_ROOT/k8s/ai-predictor/" -n "$NAMESPACE"
    
    # Wait for deployments
    kubectl rollout status deployment/weather-api -n "$NAMESPACE" --timeout=300s
    kubectl rollout status deployment/ai-predictor -n "$NAMESPACE" --timeout=300s
    
    log_success "Applications deployed successfully"
}

deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    # Add Prometheus Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus stack
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --values "$PROJECT_ROOT/monitoring/prometheus/values.yaml" \
        --wait
    
    log_success "Monitoring stack deployed"
}

run_health_checks() {
    log_info "Running health checks..."
    
    # Check pod status
    kubectl get pods -n "$NAMESPACE"
    
    # Check service endpoints
    local services=("weather-api" "ai-predictor")
    for service in "${services[@]}"; do
        log_info "Checking $service health..."
        kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- \
            curl -f "http://$service.$NAMESPACE.svc.cluster.local/health" || {
            log_error "$service health check failed"
            exit 1
        }
    done
    
    log_success "All health checks passed"
}

cleanup() {
    log_info "Cleaning up temporary resources..."
    kubectl delete pod curl-test --ignore-not-found=true
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cloud)
                CLOUD_PROVIDER="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate inputs
    if [[ ! "$CLOUD_PROVIDER" =~ ^(aws|azure|gcp)$ ]]; then
        log_error "Invalid cloud provider: $CLOUD_PROVIDER"
        exit 1
    fi
    
    if [[ -z "$REGION" ]]; then
        log_error "Region is required"
        exit 1
    fi
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    log_info "Starting CloudWeather Sentinel deployment"
    log_info "Cloud Provider: $CLOUD_PROVIDER"
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    log_info "Namespace: $NAMESPACE"
    
    # Execute deployment steps
    check_prerequisites
    setup_infrastructure
    configure_kubernetes
    deploy_applications
    deploy_monitoring
    run_health_checks
    
    log_success "🌤️ CloudWeather Sentinel deployment completed successfully!"
    log_info "Access your services:"
    log_info "  Weather API: kubectl port-forward svc/weather-api 8080:80 -n $NAMESPACE"
    log_info "  AI Predictor: kubectl port-forward svc/ai-predictor 8081:80 -n $NAMESPACE"
    log_info "  Grafana: kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"
}

# Run main function
main "$@"