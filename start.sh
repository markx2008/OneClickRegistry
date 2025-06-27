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
if ! command -v openssl &>/dev/null; then
    log_error "openssl is not installed. Please install it to generate self-signed certificates."
    exit 1
fi

# 2. 互動式設定
log_info "Starting interactive setup..."

# 2.1 Tailscale Funnel 設定
log_info "Tailscale Funnel will be used for external access."

TS_HOSTNAME="registry" # 使用 registry 作為主機名稱
log_info "Using fixed Tailscale node name: '${TS_HOSTNAME}' for domain construction."

log_info "Please find your tailnet name from the Tailscale admin panel DNS page: https://login.tailscale.com/admin/dns"
read -p "Enter your Tailnet name (e.g., tail99999a.ts.net): " TS_TAILNET
if [ -z "$TS_TAILNET" ]; then
    log_error "Tailnet name is required to construct the full domain for Tailscale Funnel."
    exit 1
fi

echo -e "${YELLOW}Please provide a Tailscale OAuth Client Secret.${NC}"
echo "You can get one from: https://login.tailscale.com/admin/settings/oauth"
echo "Generate an OAuth client with 'Auth Keys: Write' scope and tag:container."
read -p "Tailscale OAuth Client Secret (TS_AUTHKEY): " TS_AUTHKEY
if [ -z "$TS_AUTHKEY" ]; then
    log_error "Tailscale OAuth Client Secret is required to use the Funnel."
    exit 1
fi
echo ""
echo -e "${YELLOW}Do you want this to be an ephemeral node? (y/n)${NC}"
read -p "Ephemeral node: " TS_EPHEMERAL
if [[ "$TS_EPHEMERAL" == "y" || "$TS_EPHEMERAL" == "Y" ]]; then
    TS_AUTHKEY="${TS_AUTHKEY}?ephemeral=true"
    log_info "Configuring as ephemeral node."
else
    TS_AUTHKEY="${TS_AUTHKEY}?ephemeral=false"
    log_info "Configuring as persistent node."
fi

REGISTRY_DOMAIN="registry.${TS_TAILNET}"
log_info "Your domain will be automatically configured as:"
echo -e "  - Registry & UI: ${YELLOW}${REGISTRY_DOMAIN}${NC}"
echo -e "    - UI access: ${YELLOW}${REGISTRY_DOMAIN}:80${NC}"
echo -e "    - Registry access: ${YELLOW}${REGISTRY_DOMAIN}:5000${NC}"

# 2.3 互動式輸入 Registry 認證資訊
log_info "Authentication Setup"
echo -e "${YELLOW}Please enter your htpasswd entry (format: username:hash)${NC}"
echo "Example: registry:$apr1$le1k9qfm$TjAF6rksD1nRw0QhJkW7o."
echo "This will be used for Registry authentication and UI access."
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
    echo "REGISTRY_UI_DOMAIN=${REGISTRY_DOMAIN}"
    echo "REGISTRY_UI_TITLE=My Direct Registry"
    echo "TS_AUTHKEY=${TS_AUTHKEY}"
    echo "TS_HOSTNAME=${TS_HOSTNAME}"
    echo "TS_EXTRA_ARGS=--advertise-tags=tag:container"
    echo "REGISTRY_HTTP_HEADERS_Access-Control-Allow-Credentials=['true']"
    echo "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt"
    echo "REGISTRY_HTTP_TLS_KEY=/certs/registry.key"
    echo "REGISTRY_HTTP_ADDR=0.0.0.0:5003"
} > ./.env
log_info ".env file created successfully."

# 4. 建立必要的目錄和設定檔
log_info "Creating required directories and config files..."
mkdir -p ./registry/data
mkdir -p ./registry/auth
mkdir -p ./registry/certs

# Tailscale Funnel 設定
mkdir -p ./tailscale/config
cat <<EOF > ./tailscale/config/funnel.json
{
  "TCP": {
    "80": {
      "HTTPS": true
    },
    "5003": {
      "HTTPS": true
    }
  },
  "Web": {
    "${REGISTRY_DOMAIN}:80": {
      "Handlers": {
        "/": {
          "Proxy": "http://localhost:80"
        }
      }
    },
    "${REGISTRY_DOMAIN}:5003": {
      "Handlers": {
        "/": {
          "Proxy": "https://localhost:5003",
          "InsecureSkipVerify": true
        }
      }
    }
  },
  "AllowFunnel": {
    "${REGISTRY_DOMAIN}:80": true,
    "${REGISTRY_DOMAIN}:5003": true
  }
}
EOF
log_info "Tailscale Funnel config created."

# 產生內部通訊用的自簽憑證
if [ ! -f ./registry/certs/registry.key ] || [ ! -f ./registry/certs/registry.crt ]; then
    log_info "Generating self-signed certificate for internal communication..."
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout ./registry/certs/registry.key -out ./registry/certs/registry.crt \
        -days 3650 \
        -subj "/CN=registry.internal"
    log_info "Self-signed certificate generated."
else
    log_info "Self-signed certificate already exists."
fi

# 5. 儲存使用者輸入的 htpasswd 到檔案
echo "$HTPASSWD_ENTRY" > ./registry/auth/htpasswd
log_info "Registry htpasswd file created successfully."

# 6. 啟動服務
log_info "Starting all services with Docker Compose..."
docker-compose up -d --force-recreate --remove-orphans

# 7. 顯示結果
if [ $? -eq 0 ]; then
    log_info "All services started successfully!"
    echo "-----------------------------------------------------"
    log_info "Next Steps:"
    echo "1. Your services are exposed via Tailscale Funnel."
    echo "   Check the Tailscale admin panel to see your node '${TS_HOSTNAME}'."
    echo "2. Access your services at:"
    echo "   - Registry & UI: ${REGISTRY_DOMAIN}"
    echo "   - UI Interface: ${REGISTRY_DOMAIN}:80"
    echo "   - Docker Registry: ${REGISTRY_DOMAIN}:5003"
    echo "3. To login to the registry, run: docker login ${REGISTRY_DOMAIN}:5003"
    echo ""
    echo -e "${RED}Authentication Credentials: Username=${REGISTRY_USER} (Please note it down)${NC}"
    echo "The same credentials will be used for Registry login and UI access."
    echo "-----------------------------------------------------"
else
    log_error "There was an error starting the services. Please check logs with 'docker-compose logs'."
fi