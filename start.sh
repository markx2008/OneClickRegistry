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
read -p "Enter your Registry Username: " REGISTRY_USER
read -p "Enter your Registry Password: " REGISTRY_PASSWORD
echo ""

# 3. 產生 .env 環境變數檔案
log_info "Creating .env file for Docker Compose..."
{
    echo "REGISTRY_DOMAIN=${REGISTRY_DOMAIN}"
    echo "REGISTRY_UI_DOMAIN=${REGISTRY_UI_DOMAIN}"
    # === 【修改點】使用新的端口，避免與你現有的 8080 端口衝突 ===
    echo "TRAEFIK_WEB_PORT=8880"
    echo "TRAEFIK_API_PORT=8881"
    # ==========================================================
    echo "TRAEFIK_DASHBOARD_DOMAIN=traefik.${REGISTRY_DOMAIN}"
    echo "REGISTRY_UI_TITLE=My New OCR Registry"
    echo "REGISTRY_UI_INTERNAL_PORT=80"
} > ./.env
log_info ".env file created successfully."

# 4. 建立必要的目錄和設定檔
log_info "Creating required directories and config files..."
mkdir -p ./registry/data
mkdir -p ./registry/auth
mkdir -p ./traefik/config

# 建立 Traefik 中間件設定檔
cat <<EOF > ./traefik/config/middlewares.yml
http:
  middlewares:
    registry-auth:
      basicAuth:
        usersFile: /auth/htpasswd
EOF
log_info "Traefik middleware config created."

# 5. 產生 htpasswd 檔案 (使用內建 openssl)
log_info "Generating htpasswd file for user: $REGISTRY_USER..."
SALT=$(openssl rand -base64 6)
PASSWORD_HASH=$(openssl passwd -1 -salt "$SALT" "$REGISTRY_PASSWORD")
if [ $? -eq 0 ] && [ -n "$PASSWORD_HASH" ]; then
    echo "$REGISTRY_USER:$PASSWORD_HASH" > ./registry/auth/htpasswd
    log_info "htpasswd file created successfully."
else
    log_error "Failed to create htpasswd file using openssl."
    exit 1
fi

# 6. 啟動服務
log_info "Starting all services with Docker Compose..."
sudo docker-compose up -d

# 7. 顯示結果
if [ $? -eq 0 ]; then
    log_info "All services started successfully!"
    echo "-----------------------------------------------------"
    log_info "Next Steps:"
    # === 【修改點】更新提示訊息中的端口號 ===
    echo "1. Your new services are running on ports 8880 (web) and 8881 (api)."
    echo "2. Set up your reverse proxy:"
    echo "   - Point ${GREEN}${REGISTRY_DOMAIN}${NC} to http://<your-nas-ip>:8880"
    echo "   - Point ${GREEN}${REGISTRY_UI_DOMAIN}${NC} to http://<your-nas-ip>:8880"
    echo "   - Point ${GREEN}traefik.${REGISTRY_DOMAIN}${NC} to http://<your-nas-ip>:8881 for dashboard"
    # =======================================
    echo "3. Access your UI at: ${GREEN}https://${REGISTRY_UI_DOMAIN}${NC}"
    echo "4. To login, run: ${YELLOW}docker login ${REGISTRY_DOMAIN}${NC}"
    echo "-----------------------------------------------------"
else
    log_error "There was an error starting the services. Please check logs with 'sudo docker-compose logs'."
fi