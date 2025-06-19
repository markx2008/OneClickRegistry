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

# 2. 檢查 .env 檔案是否存在
if [ ! -f .env ]; then
    log_warn ".env file not found. Copying from .env.example."
    cp .env.example .env
    log_error "Please edit the .env file with your custom settings, then run this script again."
    exit 1
fi

# 3. 載入環境變數
export $(grep -v '^#' .env | xargs)

# 4. 檢查域名是否已設定
if [[ "$REGISTRY_DOMAIN" == "registry.your-domain.com" || "$REGISTRY_UI_DOMAIN" == "ui.your-domain.com" ]]; then
    log_error "Default domain names are still in use in the .env file."
    log_error "Please update REGISTRY_DOMAIN and REGISTRY_UI_DOMAIN with your actual domains."
    exit 1
fi

# 5. 檢查 htpasswd 工具是否存在
if ! command -v htpasswd &> /dev/null; then
    log_error "htpasswd command not found. It's required to generate the password file."
    log_error "Please install it. On Debian/Ubuntu: 'sudo apt-get install apache2-utils'. On CentOS/RHEL: 'sudo yum install httpd-tools'."
    exit 1
fi

# 6. 建立必要的目錄
log_info "Creating required directories..."
mkdir -p ./registry/data
mkdir -p ./registry/auth
mkdir -p ./traefik

# 7. 產生 htpasswd 檔案
log_info "Generating htpasswd file for user: $REGISTRY_USER"
htpasswd -bc ./registry/auth/htpasswd "$REGISTRY_USER" "$REGISTRY_PASSWORD"
if [ $? -ne 0 ]; then
    log_error "Failed to create htpasswd file. Please check permissions or htpasswd command."
    exit 1
fi
log_info "htpasswd file created successfully."

# 8. 啟動服務
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
    echo "   (Username: ${REGISTRY_USER}, Password: [the one in your .env file])"
    echo "4. Access Traefik Dashboard at: ${GREEN}http://<your-nas-ip>:${TRAEFIK_API_PORT}${NC}"
    echo "-----------------------------------------------------"
else
    log_error "There was an error starting the services. Please check the logs using 'docker-compose logs'."
fi