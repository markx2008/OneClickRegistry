#!/bin/sh

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

start_containers() {
    echo "Starting Docker containers..."
    mkdir -p ./registry/data ./registry/auth
    docker-compose up -d
    echo "Containers started."
}

stop_containers() {
    echo "Stopping Docker containers..."
    docker-compose down
    echo "Containers stopped."
}

# --- Dependency Check ---
echo "Checking for required tools: docker, docker-compose, tailscale, jq..."

if ! command_exists docker || ! command_exists docker-compose || ! command_exists tailscale || ! command_exists jq; then
    echo "Error: One or more required tools are not installed or not in your PATH."
    echo "Please install Docker, Docker Compose, Tailscale, and jq before running this script."
    exit 1
fi

echo "All required tools are found."

# --- Tailscale Domain Detection ---
echo "Detecting this machine's Tailscale domain..."
# Get the Tailscale DNS name for this machine and remove the trailing dot.
raw_domain=$(tailscale status --json | jq -r '.Self.DNSName')
REGISTRY_DOMAIN=${raw_domain%.}

if [ -z "$REGISTRY_DOMAIN" ]; then
    echo "Error: Could not determine Tailscale domain. Is Tailscale running and are you logged in?"
    exit 1
fi
echo "Successfully found domain: ${REGISTRY_DOMAIN}"
export REGISTRY_DOMAIN

# --- .env File Setup ---
if [ "$COMMAND" = "reset" ]; then
    # 已經在 case 區塊中處理了重置操作
    :
elif [ ! -f .env ]; then
    echo "--- Environment Setup ---"
    echo "The .env file was not found. Let's create it."

    echo -n "Enter a title for the Registry UI (REGISTRY_UI_TITLE): "
    read registry_ui_title

    # 確保HTTPS端口是Tailscale Funnel支持的端口
    while true; do
        echo -n "Enter HTTPS port for Registry (443, 8443, or 10000; default: 443): "
        read https_port
        
        # 如果為空，使用默認值
        if [ -z "$https_port" ]; then
            https_port=443
            break
        fi
        
        # 檢查是否為允許的端口
        if [ "$https_port" = "443" ] || [ "$https_port" = "8443" ] || [ "$https_port" = "10000" ]; then
            break
        else
            echo "Error: Tailscale Funnel only supports ports 443, 8443, or 10000. Please choose one of these ports."
        fi
    done
    
    # 確保HTTP端口是有效的數字
    while true; do
        echo -n "Enter HTTP port for Registry (default: 8080): "
        read http_port
        
        # 如果為空，使用默認值
        if [ -z "$http_port" ]; then
            http_port=8080
            break
        fi
        
        # 檢查是否為數字
        if echo "$http_port" | grep -q "^[0-9]\+$"; then
            # 檢查端口範圍
            if [ "$http_port" -ge 1 ] && [ "$http_port" -le 65535 ]; then
                break
            else
                echo "Error: Port must be between 1 and 65535. Please try again."
            fi
        else
            echo "Error: Please enter a valid number for the port."
        fi
    done
    
    # 設置各個端口
    HTTPS_PORT=$https_port
    TRAEFIK_HTTPS_PORT=$https_port
    DASHBOARD_PORT=$((HTTPS_PORT + 1))  # 儀表板端口設為HTTPS端口+1
    FUNNEL_PORT=$HTTPS_PORT
    HTTP_PORT=$http_port

    echo "--- Registry Credentials Setup ---"
    echo -n "Enter the full htpasswd line (e.g., user:\\$apr1\\$...): "
    read htpasswd_line

    echo "Creating .env file..."
    cat > .env << EOL
# Registry Settings
REGISTRY_DOMAIN=${REGISTRY_DOMAIN}
REGISTRY_UI_TITLE=${registry_ui_title}
HTTPS_PORT=${HTTPS_PORT}
TRAEFIK_HTTPS_PORT=${TRAEFIK_HTTPS_PORT}
DASHBOARD_PORT=${DASHBOARD_PORT}
FUNNEL_PORT=${FUNNEL_PORT}
HTTP_PORT=${HTTP_PORT}
EOL

    echo ".env file created successfully."

    echo "Creating htpasswd file..."
    mkdir -p ./registry/auth
    if echo "$htpasswd_line" > ./registry/auth/htpasswd; then
        echo "htpasswd file created successfully."
    else
        echo "Error: Failed to create htpasswd file."
        exit 1
    fi
else
    echo ".env file already exists. Loading variables."
    # 使用grep提取變量值，如果不存在則使用默認值
    HTTPS_PORT=$(grep -E "^HTTPS_PORT=" .env | cut -d= -f2)
    TRAEFIK_HTTPS_PORT=$(grep -E "^TRAEFIK_HTTPS_PORT=" .env | cut -d= -f2)
    DASHBOARD_PORT=$(grep -E "^DASHBOARD_PORT=" .env | cut -d= -f2)
    FUNNEL_PORT=$(grep -E "^FUNNEL_PORT=" .env | cut -d= -f2)
    HTTP_PORT=$(grep -E "^HTTP_PORT=" .env | cut -d= -f2)
    
    # 設置默認值（如果變量為空）
    HTTPS_PORT=${HTTPS_PORT:-443}
    TRAEFIK_HTTPS_PORT=${TRAEFIK_HTTPS_PORT:-443}
    DASHBOARD_PORT=${DASHBOARD_PORT:-8082}
    FUNNEL_PORT=${FUNNEL_PORT:-$HTTPS_PORT}
    HTTP_PORT=${HTTP_PORT:-8080}
    
    # 確保FUNNEL_PORT有值
    if [ -z "$FUNNEL_PORT" ]; then
        FUNNEL_PORT=$HTTPS_PORT
    fi
    
    # 將變量導出到環境中
    export HTTPS_PORT
    export TRAEFIK_HTTPS_PORT
    export DASHBOARD_PORT
    export FUNNEL_PORT
    export HTTP_PORT
    
    # 確保FUNNEL_PORT是有效的Tailscale Funnel端口
    if [ "$FUNNEL_PORT" != "443" ] && [ "$FUNNEL_PORT" != "8443" ] && [ "$FUNNEL_PORT" != "10000" ]; then
        echo "Warning: Stored FUNNEL_PORT ($FUNNEL_PORT) is not supported by Tailscale Funnel."
        echo "Tailscale Funnel only supports ports 443, 8443, or 10000."
        echo "Setting to default port 443."
        FUNNEL_PORT=443
        # 更新.env文件中的FUNNEL_PORT
        sed -i "s/^FUNNEL_PORT=.*/FUNNEL_PORT=443/" .env
    fi
fi

# --- 檢查端口是否已被占用 ---
check_port() {
    local port=$1
    local result=1
    
    # 使用lsof檢查端口（如果可用）
    if command_exists lsof; then
        lsof -i ":$port" >/dev/null 2>&1
        result=$?
        if [ $result -eq 0 ]; then
            return 0  # 端口被占用
        fi
    fi
    
    # 使用ss檢查端口（如果可用）
    if command_exists ss; then
        ss -tuln | grep -q ":$port " >/dev/null 2>&1
        result=$?
        if [ $result -eq 0 ]; then
            return 0  # 端口被占用
        fi
    fi
    
    # 使用netstat檢查端口（如果可用）
    if command_exists netstat; then
        # 使用靜默模式檢查端口
        netstat -tuln 2>/dev/null | grep -q ":$port " >/dev/null 2>&1
        result=$?
        if [ $result -eq 0 ]; then
            return 0  # 端口被占用
        fi
    fi
    
    # 所有方法都沒有檢測到端口被占用
    return 1
}

if check_port "$HTTPS_PORT"; then
    echo "警告: HTTPS 端口 $HTTPS_PORT 已被占用。請選擇其他端口或停止使用該端口的服務。"
    exit 1
fi

if check_port "$DASHBOARD_PORT"; then
    echo "警告: 儀表板端口 $DASHBOARD_PORT 已被占用。請選擇其他端口或停止使用該端口的服務。"
    exit 1
fi

if check_port "$HTTP_PORT"; then
    echo "警告: HTTP 端口 $HTTP_PORT 已被占用。請選擇其他端口或停止使用該端口的服務。"
    exit 1
fi

# --- Tailscale Funnel Setup ---
echo "Enabling Tailscale Funnel with TLS-terminated TCP forwarding on port ${FUNNEL_PORT}..."

# 檢查是否已有funnel運行
funnel_status=$(tailscale funnel status 2>/dev/null)
if [ -n "$funnel_status" ]; then
    echo "Resetting existing Tailscale Funnel..."
    tailscale funnel reset
fi

# 使用TLS-terminated TCP forwarding
if tailscale funnel --tls-terminated-tcp ${FUNNEL_PORT} tcp://localhost:${HTTPS_PORT}; then
    echo "Tailscale Funnel with TLS-terminated TCP forwarding enabled successfully."
else
    echo "Error: Failed to enable Tailscale Funnel with TCP forwarding."
    echo "Please check your Tailscale ACLs to ensure 'funnel' is allowed for this user."
    exit 1
fi

# --- Traefik TLS Config ---
echo "Generating Traefik TLS config..."
mkdir -p ./traefik/dynamic
rm -f ./traefik/dynamic/*.yml

cat > ./traefik/dynamic/tls.yml << EOL
tls:
  certificates:
    - certFile: "/certs/funnel.crt"
      keyFile: "/certs/funnel.key"
EOL
echo "Traefik TLS config created."

# --- Public Certificate Generation via Tailscale ---
CERT_FILE="./registry/certs/funnel.crt"
KEY_FILE="./registry/certs/funnel.key"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "--- Public TLS Certificate Setup ---"
    echo "Public certificate for Funnel not found. Generating new one with Tailscale..."
    echo "This certificate will be used for public traffic via ${REGISTRY_DOMAIN}."

    mkdir -p ./registry/certs

    # 確保域名不以點結尾，這可能會導致證書生成失敗
    CLEAN_DOMAIN="${REGISTRY_DOMAIN%.}"
    
    echo "Generating certificate for ${CLEAN_DOMAIN}..."
    if tailscale cert --cert-file "$CERT_FILE" --key-file "$KEY_FILE" "${CLEAN_DOMAIN}"; then
        echo "Public certificate generated successfully."
    else
        echo "Error: Failed to generate certificate with Tailscale."
        echo "Please check your Tailscale status and ensure the domain is correct and Funnel is enabled."
        exit 1
    fi
else
    echo "Public certificate already exists. Skipping generation."
fi

# --- Docker Compose Operations ---

# Default to 'start' if no command is provided
COMMAND=${1:-start}

case "$COMMAND" in
    start)
        start_containers
        echo "======================================"
        echo "Registry successfully started!"
        echo "Access URL: https://${REGISTRY_DOMAIN}:${FUNNEL_PORT}"
        echo "Docker login command: docker login ${REGISTRY_DOMAIN}:${FUNNEL_PORT}"
        echo "Traefik dashboard: http://localhost:${DASHBOARD_PORT}"
        echo "======================================"
        ;;
    stop)
        stop_containers
        ;;
    restart)
        stop_containers
        start_containers
        echo "======================================"
        echo "Registry successfully restarted!"
        echo "Access URL: https://${REGISTRY_DOMAIN}:${FUNNEL_PORT}"
        echo "Docker login command: docker login ${REGISTRY_DOMAIN}:${FUNNEL_PORT}"
        echo "Traefik dashboard: http://localhost:${DASHBOARD_PORT}"
        echo "======================================"
        ;;
    reset)
        echo "Stopping containers before resetting..."
        stop_containers
        echo "Removing configuration files (.env and htpasswd)..."
        rm -f .env
        rm -f ./registry/auth/htpasswd
        echo "Reset complete. Please run 'sh start.sh' to configure again."
        exit 0
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|reset}"
        exit 1
esac

exit 0