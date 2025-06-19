#!/bin/bash

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函數：輸出日誌
log_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}
log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}
log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# 1. 檢查 Docker 和 Docker Compose 是否安裝
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    exit 1
fi
if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# 2. 互動式設定
log_info "Starting interactive setup..."
read -p "Enter your Registry Domain (e.g., registry.example.com): " REGISTRY_DOMAIN
read -p "Enter your Registry UI Domain (e.g., ui.example.com): " REGISTRY_UI_DOMAIN
read -p "Enter your Registry Username: " REGISTRY_USER
read -s -p "Enter your Registry Password: " REGISTRY_PASSWORD
echo ""

# 確認輸入
log_info "Using the following settings:"
echo "Registry Domain: $REGISTRY_DOMAIN"
echo "Registry UI Domain: $REGISTRY_UI_DOMAIN"
echo "Registry Username: $REGISTRY_USER"

# 3. 檢查 htpasswd 工具是否存在
if ! command -v htpasswd &> /dev/null; then
    log_warn "htpasswd command not found. Attempting to install it..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update && sudo apt-get install -y apache2-utils
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y httpd-tools
    elif [ -f /etc/alpine-release ]; then
        sudo apk add apache2-utils
    else
        log_error "Unsupported system. Please install htpasswd manually."
        exit 1
    fi

    if ! command -v htpasswd &> /dev/null; then
        log_error "Failed to install htpasswd. Please install it manually."
        exit 1
    fi
    log_info "htpasswd installed successfully."
fi

# 4. 建立必要的目錄
log_info "Creating required directories..."
mkdir -p ./registry/data
mkdir -p ./registry/auth
mkdir -p ./traefik

# 5. 產生 htpasswd 檔案
log_info "Generating htpasswd file for user: $REGISTRY_USER"
htpasswd -bc ./registry/auth/htpasswd "$REGISTRY_USER" "$REGISTRY_PASSWORD" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    log_error "Failed to create htpasswd file. Please check permissions or htpasswd command."
    exit 1
fi
log_info "htpasswd file created successfully."

# 6. 啟動服務
log_info "Starting all services with Docker Compose..."
docker-compose up -d

if [ $? -eq 0 ]; then
    log_info "All services started successfully!"
    echo "-----------------------------------------------------"
    log_info "Next Steps:"
    echo "1. Set up Cloudflare Tunnel to point your domains to http://localhost:${TRAEFIK_WEB_PORT}"
    echo "   - Target for ${GREEN}${REGISTRY_DOMAIN}${NC}: http://localhost:${TRAEFIK_WEB_PORT}"
    echo "   - Target for ${GREEN}${REGISTRY_UI_DOMAIN}${NC}: http://localhost:${TRAEFIK_WEB_PORT}"
    echo "2. Access your UI at: ${GREEN}https://${REGISTRY_UI_DOMAIN}${NC}"
    echo "3. To login to your registry from your local machine, run:"
    echo "   ${YELLOW}docker login ${REGISTRY_DOMAIN}${NC}"
    echo "   (Username: ${REGISTRY_USER}, Password: [the one you entered])"
    echo "4. Access Traefik Dashboard at: ${GREEN}http://<your-nas-ip>:${TRAEFIK_API_PORT}${NC}"
    echo "-----------------------------------------------------"
else
    log_error "There was an error starting the services. Please check the logs using 'docker-compose logs'."
fi