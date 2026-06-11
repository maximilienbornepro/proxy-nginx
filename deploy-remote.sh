#!/bin/bash

# Proxy Nginx - Remote Deployment Script
# Usage: ./deploy-remote.sh [command]
#
# This script runs deployment commands on the remote server via SSH.
# Configure your server in .deploy.env

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load config
CONFIG_FILE=".deploy.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${YELLOW}[WARN]${NC} No .deploy.env found. Creating template..."
    cat > "$CONFIG_FILE" << 'EOF'
# Remote server configuration
REMOTE_HOST="studio.vitess.tech"
REMOTE_USER="root"
REMOTE_PATH="/opt/apps/proxy"
SSH_KEY=""  # Optional: path to SSH key, e.g., ~/.ssh/id_rsa
EOF
    echo -e "${GREEN}[INFO]${NC} Created .deploy.env - please configure it and retry."
    exit 1
fi

# Validate config
if [ -z "$REMOTE_HOST" ] || [ "$REMOTE_HOST" = "your-server.com" ]; then
    echo -e "${RED}[ERROR]${NC} Please configure REMOTE_HOST in .deploy.env"
    exit 1
fi

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_cmd() { echo -e "${CYAN}[CMD]${NC} $1"; }

# Build SSH command
ssh_cmd() {
    local cmd="ssh"
    if [ -n "$SSH_KEY" ]; then
        cmd="$cmd -i $SSH_KEY"
    fi
    cmd="$cmd ${REMOTE_USER}@${REMOTE_HOST}"
    echo "$cmd"
}

# Execute command on remote server
remote_exec() {
    local cmd="$1"
    log_cmd "$cmd"
    $(ssh_cmd) "cd $REMOTE_PATH && $cmd"
}

# Full deployment (git pull + certbot + restart all)
deploy_all() {
    log_info "Starting full deployment..."

    remote_exec "git pull origin main"

    log_info "Updating SSL certificate..."
    remote_exec "sudo certbot certonly --webroot \
        -w ${REMOTE_PATH}/certbot/www \
        -d studio.vitess.tech \
        -d tools.vitess.tech \
        -d rndv.vitess.tech \
        -d monitoring.vitess.tech \
        -d maximilienborne.fr \
        -d www.maximilienborne.fr \
        -d tools.maximilienborne.fr \
        -d oflf.vitess.tech \
        --non-interactive --agree-tos --expand || true"

    remote_exec 'CERT_NAME=$(ls /etc/letsencrypt/live/ | grep -v README | head -1) && \
        sudo cp -L "/etc/letsencrypt/live/$CERT_NAME/fullchain.pem" nginx/ssl/fullchain.pem && \
        sudo cp -L "/etc/letsencrypt/live/$CERT_NAME/privkey.pem" nginx/ssl/privkey.pem'

    log_info "Restarting services..."
    remote_exec "docker compose up -d --force-recreate"

    log_info "Testing nginx config..."
    remote_exec "docker compose exec -T nginx nginx -t"

    log_info "Reloading nginx..."
    remote_exec "docker compose exec -T nginx nginx -s reload"

    log_info "Full deployment complete!"
    remote_exec "docker compose ps"
}

# Quick deploy (git pull + reload nginx, no recreate)
deploy_quick() {
    log_info "Quick deployment..."
    remote_exec "git pull origin main"
    remote_exec "docker compose up -d"
    remote_exec "docker compose exec -T nginx nginx -t"
    remote_exec "docker compose exec -T nginx nginx -s reload"
    log_info "Quick deployment complete!"
    remote_exec "docker compose ps"
}

# Renew SSL certificate
renew_cert() {
    log_info "Renewing SSL certificate..."
    remote_exec "sudo certbot certonly --webroot \
        -w ${REMOTE_PATH}/certbot/www \
        -d studio.vitess.tech \
        -d tools.vitess.tech \
        -d rndv.vitess.tech \
        -d monitoring.vitess.tech \
        -d maximilienborne.fr \
        -d www.maximilienborne.fr \
        -d tools.maximilienborne.fr \
        --non-interactive --agree-tos --expand"

    remote_exec 'CERT_NAME=$(ls /etc/letsencrypt/live/ | grep -v README | head -1) && \
        sudo cp -L "/etc/letsencrypt/live/$CERT_NAME/fullchain.pem" nginx/ssl/fullchain.pem && \
        sudo cp -L "/etc/letsencrypt/live/$CERT_NAME/privkey.pem" nginx/ssl/privkey.pem'

    remote_exec "docker compose exec -T nginx nginx -s reload"
    log_info "Certificate renewed and nginx reloaded!"
}

# Show logs
show_logs() {
    local service="$1"
    if [ -z "$service" ]; then
        remote_exec "docker compose logs -f --tail=100"
    else
        remote_exec "docker compose logs -f --tail=100 $service"
    fi
}

# Show status
show_status() {
    remote_exec "docker compose ps"
}

# Restart service(s)
restart_service() {
    local services="$1"
    if [ -z "$services" ]; then
        log_info "Restarting all services..."
        remote_exec "docker compose restart"
    else
        log_info "Restarting: $services"
        remote_exec "docker compose restart $services"
    fi
    remote_exec "docker compose ps"
}

# SSH into server
ssh_connect() {
    log_info "Connecting to $REMOTE_HOST..."
    $(ssh_cmd) -t "cd $REMOTE_PATH && bash"
}

# Execute arbitrary command
exec_cmd() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        log_error "Usage: ./deploy-remote.sh exec '<command>'"
        exit 1
    fi
    remote_exec "$cmd"
}

# Print help
print_help() {
    echo "Proxy Nginx - Remote Deployment"
    echo ""
    echo -e "${CYAN}Usage:${NC} ./deploy-remote.sh [command] [args]"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo "  deploy          Full deployment (git pull + certbot + restart all)"
    echo "  quick           Quick deploy (git pull + reload nginx)"
    echo "  cert            Renew SSL certificate"
    echo "  restart [name]  Restart service(s) (all if no name given)"
    echo "  logs [name]     Show logs (all or specific service)"
    echo "  status          Show services status"
    echo "  ssh             SSH into the server"
    echo "  exec '<cmd>'    Execute arbitrary command on server"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  ./deploy-remote.sh deploy              # Full deployment"
    echo "  ./deploy-remote.sh quick               # Quick reload"
    echo "  ./deploy-remote.sh cert                # Renew SSL cert"
    echo "  ./deploy-remote.sh logs nginx          # Show nginx logs"
    echo "  ./deploy-remote.sh logs grafana        # Show grafana logs"
    echo "  ./deploy-remote.sh restart nginx       # Restart nginx"
    echo "  ./deploy-remote.sh status              # Show all services"
    echo "  ./deploy-remote.sh ssh                 # Connect to server"
    echo ""
    echo -e "${CYAN}Services:${NC}"
    echo "  nginx, loki, promtail, prometheus, nginx-exporter, grafana"
}

# Main
case "${1:-help}" in
    deploy)
        deploy_all
        ;;
    quick)
        deploy_quick
        ;;
    cert)
        renew_cert
        ;;
    restart)
        shift
        restart_service "$*"
        ;;
    logs)
        show_logs "$2"
        ;;
    status)
        show_status
        ;;
    ssh)
        ssh_connect
        ;;
    exec)
        shift
        exec_cmd "$*"
        ;;
    *)
        print_help
        ;;
esac
