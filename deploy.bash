#!/bin/bash

# VSCode Tunnel One-Click Deployment Script

# Colourful output functions
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; }

# Get current username
USERNAME=$(whoami)

# Check if 'code' command exists
if ! command -v code &> /dev/null; then
  info "VS Code CLI not found. Installing now..."
  sudo apt-get update
  sudo apt-get install -y wget gpg apt-transport-https
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
  sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
  rm -f packages.microsoft.gpg
  sudo apt update
  sudo apt install -y code
else
  info "VS Code CLI is already installed."
fi

# Get full path of 'code'
CODE_PATH=$(command -v code)

# Prompt user to input a custom name B
read -p "Enter a custom name (used in service name, leave blank to use default): " B
if [[ -z "$B" ]]; then
  SERVICE_NAME="vscode-tunnel"
  USE_CUSTOM_CLI_DIR=false
else
  SERVICE_NAME="vscode-tunnel-${B}"
  USE_CUSTOM_CLI_DIR=true
fi

# Check if service already exists
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
if [[ -f "$SERVICE_FILE" ]]; then
  warn "Service '${SERVICE_NAME}' already exists."
  read -p "Do you want to overwrite it? (y/N): " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    info "Deployment cancelled."
    exit 0
  fi
  sudo systemctl stop "${SERVICE_NAME}"
fi

# Build service command
TUNNEL_CMD="\"${CODE_PATH}\" tunnel --accept-server-license-terms"
if $USE_CUSTOM_CLI_DIR; then
  CLI_DIR="$HOME/.vscode/user-tunnel/${B}"
  mkdir -p "$CLI_DIR"
  TUNNEL_CMD="${TUNNEL_CMD} --cli-data-dir ${CLI_DIR}"
fi

# Write the systemd service file
info "Writing systemd service file to '${SERVICE_FILE}'..."
sudo bash -c "cat > '${SERVICE_FILE}'" <<EOF
[Unit]
Description=VS Code Remote Tunnel Service
After=network.target

[Service]
Type=simple
User=${USERNAME}
ExecStart=${TUNNEL_CMD}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Ask if user wants to enable the service at boot
read -p "Do you want to enable the service to start automatically at boot? (Y/n): " ENABLE_AT_BOOT
ENABLE_AT_BOOT=${ENABLE_AT_BOOT:-Y}  # Default to Yes if empty

# Reload and start the service
info "Reloading systemd daemon..."
sudo systemctl daemon-reload

if [[ "$ENABLE_AT_BOOT" == "Y" || "$ENABLE_AT_BOOT" == "y" ]]; then
  info "Enabling service '${SERVICE_NAME}' to start at boot..."
  sudo systemctl enable "${SERVICE_NAME}"
else
  info "Service will not start automatically at boot."
fi

sudo systemctl start "${SERVICE_NAME}"
info "Service '${SERVICE_NAME}' has been started. Checking status..."

# Start checking service status quickly
sleep 1

# Check service status and handle accordingly
SERVICE_STATUS=$(sudo systemctl status "${SERVICE_NAME}" 2>&1)
SERVICE_EXIT_CODE=$?

if [ $SERVICE_EXIT_CODE -ne 0 ]; then
    # Service failed to start properly
    error "Service failed to start properly. Error details:"
    echo -e "\e[31m$SERVICE_STATUS\e[0m"
    error "Please fix the issues above or report them at https://github.com/your-username/vscode-tunnel-deployer/issues"
else
    # Service started, now check if it's running properly
    # Look for the registration code pattern with retries
    MAX_TRIES=5
    TRIES=0
    REGISTRATION_CODE=""
    
    while [ $TRIES -lt $MAX_TRIES ]; do
        TUNNEL_LOGS=$(sudo journalctl -u "${SERVICE_NAME}" -n 50 --no-pager 2>&1)
        REGISTRATION_CODE=$(echo "$TUNNEL_LOGS" | grep -o '[A-Z]\{4\}-[A-Z]\{4\}-[A-Z]\{4\}')
        
        if [ -n "$REGISTRATION_CODE" ]; then
            # Found registration code
            info "Service '${SERVICE_NAME}' is running successfully!"
            echo -e "\e[32m========================================================\e[0m"
            echo -e "\e[32m Registration code found: $REGISTRATION_CODE \e[0m"
            echo -e "\e[32m Please use this code to authenticate your machine in VS Code \e[0m"
            echo -e "\e[32m========================================================\e[0m"
            break
        fi
        
        # Try again in 1 second if we haven't reached max tries
        TRIES=$((TRIES+1))
        if [ $TRIES -lt $MAX_TRIES ]; then
            sleep 1
        fi
    done
    
    # Only show this message if we never found a registration code after all tries
    if [ -z "$REGISTRATION_CODE" ]; then
        info "Service '${SERVICE_NAME}' is running, but no registration code detected."
        info "You can check for vscode tunnel service log with: sudo journalctl -u ${SERVICE_NAME} -f"
    fi
fi

# Print service control guide
cat << EOG

---------------------------------------------------
Service Control Guide for '${SERVICE_NAME}':
---------------------------------------------------
• Start the service:
  sudo systemctl start ${SERVICE_NAME}

• Stop the service:
  sudo systemctl stop ${SERVICE_NAME}

• Restart the service:
  sudo systemctl restart ${SERVICE_NAME}

• Check service status:
  sudo systemctl status ${SERVICE_NAME}

• View service logs:
  sudo journalctl -u ${SERVICE_NAME}

• Enable service at boot:
  sudo systemctl enable ${SERVICE_NAME}

• Disable service at boot:
  sudo systemctl disable ${SERVICE_NAME}
---------------------------------------------------
EOG