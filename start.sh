#!/bin/bash

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 函數
log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# 1. 檢查依賴
if ! command -v docker &>/dev/null || ! command -v docker-compose &>/dev/null; then
    log_error "Docker or Docker Compose is not installed."
    exit 1
fi

# 2. 互動式設定
log_info "Starting interactive setup..."
read -p "Enter your Registry Domain (e.g., registry.example.com): " REGISTRY_DOMAIN
read -p "Enter your Registry UI Domain (e.g., ui.example.com): " REGISTRY_UI_DOMAIN
echo ""

# 2.1 互動式輸入 Traefik Dashboard Domain
read -p "Enter your Traefik Dashboard Domain (default: traefik.${REGISTRY_DOMAIN}): " TRAEFIK_DASHBOARD_DOMAIN
TRAEFIK_DASHBOARD_DOMAIN=${TRAEFIK_DASHBOARD_DOMAIN:-traefik.${REGISTRY_DOMAIN}}

# 2.3 互動式輸入 Registry 認證資訊
log_info "Authentication Setup"
echo -e "${YELLOW}Please enter your htpasswd entry (format: username:hash)${NC}"
echo "Example: registry:$apr1$le1k9qfm$TjAF6rksD1nRw0QhJkW7o."
echo "This will be used for both Registry authentication and UI/Dashboard access."
read -p "htpasswd entry: " HTPASSWD_ENTRY

# 驗證 htpasswd 格式
if [ -z "$HTPASSWD_ENTRY" ]; then
    log_error "No htpasswd entry provided. Authentication will not work correctly."
    exit 1
fi

# 從 htpasswd 提取用戶名和哈希
REGISTRY_USER=$(echo "$HTPASSWD_ENTRY" | cut -d':' -f1)
REGISTRY_HASH=$(echo "$HTPASSWD_ENTRY" | cut -d':' -f2-)

if [ -z "$REGISTRY_USER" ] || [ -z "$REGISTRY_HASH" ]; then
    log_error "Invalid htpasswd format. Expected format: username:hash"
    exit 1
fi

log_info "Using credentials for user: $REGISTRY_USER"

# 3. 產生 .env 環境變數檔案
log_info "Creating .env file for Docker Compose..."
{
    echo "REGISTRY_DOMAIN=${REGISTRY_DOMAIN}"
    echo "REGISTRY_UI_DOMAIN=${REGISTRY_UI_DOMAIN}"
    # === 【修改點】使用新的端口，避免與你現有的 8080 端口衝突 ===
    echo "TRAEFIK_WEB_PORT=8880"
    echo "TRAEFIK_API_PORT=8881"
    # ==========================================================
    echo "TRAEFIK_DASHBOARD_DOMAIN=${TRAEFIK_DASHBOARD_DOMAIN}"
    echo "REGISTRY_UI_TITLE=My New OCR Registry"
    echo "REGISTRY_UI_INTERNAL_PORT=80"
} > ./.env
log_info ".env file created successfully."

# 4. 建立必要的目錄和設定檔
log_info "Creating required directories and config files..."
mkdir -p ./registry/data
mkdir -p ./registry/auth
mkdir -p ./traefik/config

# 5. 儲存使用者輸入的 htpasswd 到檔案
echo "$HTPASSWD_ENTRY" > ./registry/auth/htpasswd
log_info "Registry htpasswd file created successfully."

# 建立 Traefik 中間件設定檔，使用 usersFile 指向 htpasswd 檔案
cat <<EOF > ./traefik/config/middlewares.yml
# traefik/middlewares.yml
http:
  middlewares:
    registry-auth:
      basicAuth:
        usersFile: "/auth/htpasswd" # 指向掛載進來的認證檔案
        removeHeader: true
EOF
log_info "Traefik middleware config created."

# 6. 啟動服務
log_info "Starting all services with Docker Compose..."
sudo docker-compose up -d

# 7. 顯示結果
if [ $? -eq 0 ]; then
    log_info "All services started successfully!"
    echo "-----------------------------------------------------"
    log_info "Next Steps:"
    echo "1. Your new services are running on ports 8880 (web) and 8881 (api)."
    echo "2. Set up your reverse proxy:"
    echo "   - Point ${REGISTRY_DOMAIN} to http://<your-nas-ip>:8880"
    echo "   - Point ${REGISTRY_UI_DOMAIN} to http://<your-nas-ip>:8880"
    echo "   - Point traefik.${REGISTRY_DOMAIN} to http://<your-nas-ip>:8881 for dashboard"
    echo "3. Access your UI at: https://${REGISTRY_UI_DOMAIN}"
    echo "4. Access your Traefik Dashboard at: https://${TRAEFIK_DASHBOARD_DOMAIN}"
    echo "5. To login registry, run: docker login ${REGISTRY_DOMAIN}"
    echo ""
    echo -e "${RED}Authentication Credentials: Username=${REGISTRY_USER} (Please note it down)${NC}"
    echo "The same credentials will be used for Registry login, UI access, and Traefik Dashboard."
    echo "-----------------------------------------------------"
else
    log_error "There was an error starting the services. Please check logs with 'sudo docker-compose logs'."
fi