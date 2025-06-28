#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Dependency Check ---
echo "Checking for required tools: docker, docker-compose, tailscale..."

if ! command_exists docker || ! command_exists docker-compose || ! command_exists tailscale; then
    echo "Error: One or more required tools are not installed or not in your PATH."
    echo "Please install Docker, Docker Compose, and Tailscale before running this script."
    exit 1
fi

echo "All required tools are found."

# --- .env File Setup ---
if [ ! -f .env ]; then
    echo "--- Environment Setup ---"
    echo "The .env file was not found. Let's create it."
    
    read -p "Enter your Tailscale Auth Key (TS_AUTHKEY): " ts_authkey
    read -p "Enter the Tailscale domain suffix (e.g., your-name.ts.net): " ts_domain_suffix
    read -p "Enter the registry subdomain (e.g., registry): " registry_subdomain
    registry_domain="${registry_subdomain}.${ts_domain_suffix}"
    read -p "Enter a hostname for your Tailscale container (e.g., my-registry) (TS_HOSTNAME): " ts_hostname
    read -p "Enter a title for the Registry UI (REGISTRY_UI_TITLE): " registry_ui_title

    echo "Creating .env file..."
    cat > .env << EOL
# Tailscale Settings
TS_AUTHKEY=${ts_authkey}
TS_HOSTNAME=${ts_hostname}

# Registry Settings
REGISTRY_DOMAIN=${registry_domain}
REGISTRY_UI_TITLE=${registry_ui_title}
EOL

    echo ".env file created successfully."
else
    echo ".env file already exists. Loading variables."
fi

# Load environment variables (Docker Compose handles this automatically)

# --- Certificate Generation ---
CERT_FILE="./registry/certs/registry.crt"
KEY_FILE="./registry/certs/registry.key"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "--- Certificate Setup ---"
    echo "TLS certificates not found. Generating them with Tailscale..."

    # Create necessary directories if they don't exist
    mkdir -p ./registry/certs
    mkdir -p ./tailscale/config

    # Generate funnel.json for Tailscale Funnel
    cat <<EOF > ./tailscale/config/funnel.json
{
  "TCP": {
    "8082": {
      "HTTPS": true
    },
    "5003": {
      "HTTPS": true
    }
  },
  "Web": {
    "${REGISTRY_DOMAIN}:8082": {
      "Handlers": {
        "/": {
          "Proxy": "http://localhost:8082"
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
    "${REGISTRY_DOMAIN}:8082": true,
    "${REGISTRY_DOMAIN}:5003": true
  }
}
EOF
    echo "funnel.json created successfully."

    echo "Starting Tailscale container..."
    docker-compose up -d tailscale

    # Add a small delay to allow the container to start or fail
    sleep 5

    # Check if the Tailscale container is running
    if ! docker ps | grep -q ocr-tailscale; then
        echo "Error: Tailscale container (ocr-tailscale) is not running."
        echo "Checking Tailscale container logs for details:"
        docker-compose logs ocr-tailscale
        echo "Exiting script. Please check the logs above for the reason."
        exit 1
    fi

    echo "Waiting for Tailscale to connect..."
    until docker-compose exec ocr-tailscale tailscale status | grep -q "Logged in"; do
        echo "Tailscale not yet connected. Waiting..."
        sleep 5
    done
    echo "Tailscale connected."

    # Ensure the user has enabled HTTPS certificates in Tailscale admin console
    echo "IMPORTANT: Please ensure you have enabled HTTPS certificates in your Tailscale admin console."
    read -p "Press [Enter] to continue once you have enabled HTTPS certificates..."

    echo "Generating certificate for ${REGISTRY_DOMAIN} inside the Tailscale container..."
    docker-compose exec ocr-tailscale tailscale cert "${REGISTRY_DOMAIN}"

    echo "Copying certificates from Tailscale container to ./registry/certs/"
    docker cp ocr-tailscale:"/${REGISTRY_DOMAIN}.crt" "$CERT_FILE"
    docker cp ocr-tailscale:"/${REGISTRY_DOMAIN}.key" "$KEY_FILE"

    echo "Certificates generated and copied successfully."
else
    echo "Certificates already exist. Skipping generation."
fi

# --- Docker Compose Operations ---

start_containers() {
    echo "Starting Docker containers..."
    docker-compose up -d
    echo "Containers started."
    echo "--- Important Final Step ---"
    echo "To ensure your browser and Docker client trust the new certificate, please run the following command on your local machine (not in the container):"
    echo "tailscale cert --install"
}

stop_containers() {
    echo "Stopping Docker containers..."
    docker-compose down
    echo "Containers stopped."
}

case "$1" in
    start)
        start_containers
        ;;
    stop)
        stop_containers
        ;;
    restart)
        stop_containers
        start_containers
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
esac

exit 0
