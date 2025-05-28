#!/bin/bash

# VSCode Tunnel Deployment and Management Script

# Colourful output functions
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }

# Function to list available VS Code tunnel services
list_tunnel_services() {
    local services=($(sudo systemctl list-units "vscode-tunnel*.service" --no-legend | awk '{print $1}' | sed 's/\.service$//'))

    if [ ${#services[@]} -eq 0 ]; then
        info "No VS Code tunnel services found."
        return 1
    fi

    echo -e "\nAvailable VS Code tunnel services:"
    echo "-------------------------------------------------------------------------"
    echo -e "  ID\tSERVICE NAME\t\tSTATUS\t\tCLI-DATA DIR"
    echo "-------------------------------------------------------------------------"

    for i in "${!services[@]}"; do
        local service=${services[$i]}
        local status=$(sudo systemctl is-active "$service")

        # Try to find the CLI data dir from the service file
        local cli_data_dir="(default)"
        local service_file="/etc/systemd/system/$service.service"
        if [ -f "$service_file" ]; then
            local custom_dir=$(grep -o "\-\-cli-data-dir [^ ]*" "$service_file" | awk '{print $2}')
            if [ -n "$custom_dir" ]; then
                cli_data_dir="$custom_dir"
            fi
        fi

        # Format status with colour
        if [ "$status" == "active" ]; then
            status="\e[32mrunning\e[0m"
        else
            status="\e[31mstopped\e[0m"
        fi

        echo -e "  $i\t$service\t$status\t$cli_data_dir"
    done

    echo "-------------------------------------------------------------------------"
    return 0
}

# Function to pause a service
pause_service() {
    if ! list_tunnel_services; then
        return
    fi

    local services=($(sudo systemctl list-units "vscode-tunnel*.service" --no-legend | awk '{print $1}' | sed 's/\.service$//'))

    read -p "Enter the ID of the service to pause: " SERVICE_ID

    if ! [[ "$SERVICE_ID" =~ ^[0-9]+$ ]] || [ "$SERVICE_ID" -ge ${#services[@]} ]; then
        error "Invalid service ID."
        return
    fi

    local selected_service=${services[$SERVICE_ID]}

    info "Stopping service '$selected_service'..."
    sudo systemctl stop "$selected_service"
    success "Service '$selected_service' has been stopped."
    info "To restart it later, run: sudo systemctl start $selected_service"
}

# Function to remove a service
remove_service() {
    if ! list_tunnel_services; then
        return
    fi

    local services=($(sudo systemctl list-units "vscode-tunnel*.service" --no-legend | awk '{print $1}' | sed 's/\.service$//'))

    read -p "Enter the ID of the service to remove: " SERVICE_ID

    if ! [[ "$SERVICE_ID" =~ ^[0-9]+$ ]] || [ "$SERVICE_ID" -ge ${#services[@]} ]; then
        error "Invalid service ID."
        return
    fi

    local selected_service=${services[$SERVICE_ID]}
    local service_file="/etc/systemd/system/$selected_service.service"

    # Find CLI data directory
    local cli_data_dir=""
    if [ -f "$service_file" ]; then
        cli_data_dir=$(grep -o "\-\-cli-data-dir [^ ]*" "$service_file" | awk '{print $2}')
    fi

    # Ask if the user wants to keep data
    local remove_data=false
    if [ -n "$cli_data_dir" ]; then
        read -p "Do you want to remove service data ($cli_data_dir)? (y/N): " REMOVE_DATA_CONFIRM
        if [[ "$REMOVE_DATA_CONFIRM" == "y" || "$REMOVE_DATA_CONFIRM" == "Y" ]]; then
            remove_data=true
        fi
    fi

    # Stop and disable service
    info "Stopping service '$selected_service'..."
    sudo systemctl stop "$selected_service"
    sudo systemctl disable "$selected_service"

    # Remove service file
    info "Removing service file..."
    sudo rm -f "$service_file"
    sudo systemctl daemon-reload

    # Remove data if requested
    if $remove_data && [ -n "$cli_data_dir" ] && [ -d "$cli_data_dir" ]; then
        info "Removing service data directory..."
        rm -rf "$cli_data_dir"
        success "Service data removed."
    fi

    success "Service '$selected_service' has been completely removed."
}

# Function to install and configure a new VS Code tunnel service
install_service() {
    # Check if 'code' command exists
    if ! command -v code &>/dev/null; then
        info "VS Code CLI not found. Installing now..."
        sudo apt-get update
        sudo apt-get install -y wget gpg apt-transport-https
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
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
            return 1
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
    ENABLE_AT_BOOT=${ENABLE_AT_BOOT:-Y} # Default to Yes if empty

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
            REGISTRATION_CODE=$(echo "$TUNNEL_LOGS" | grep -o "code [0-9A-Z]\{4\}-[0-9A-Z]\{4\}" | sed 's/code //' | tail -n 1)

            if [ -n "$REGISTRATION_CODE" ]; then
                # Found registration code
                success "Service '${SERVICE_NAME}' is running successfully!"
                echo -e "\e[32m========================================================\e[0m"
                echo -e "\e[32m Registration code: $REGISTRATION_CODE \e[0m"
                echo -e "\e[32m Please use this code to authenticate your machine in VS Code \e[0m"
                echo -e "\e[32m on https://github.com/login/device \e[0m"
                echo -e "\e[32m========================================================\e[0m"
                break
            fi

            # Try again in 1 second if we haven't reached max tries
            TRIES=$((TRIES + 1))
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
    cat <<EOG

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
}

# Get current username
USERNAME=$(whoami)

# Display main menu
echo -e "\n================ VS Code Tunnel Manager ================\n"
echo "Please select an operation:"
echo "  1. Install/Configure a new VS Code tunnel service"
echo "  2. Pause an existing tunnel service"
echo "  3. Remove an existing tunnel service"
echo -e "\n======================================================="

read -p "Enter your choice (1-3): " MAIN_CHOICE

case $MAIN_CHOICE in
1 | "")
    info "Proceeding with tunnel service installation..."
    install_service
    ;;
2)
    pause_service
    ;;
3)
    remove_service
    ;;
*)
    error "Invalid choice. Exiting."
    exit 1
    ;;
esac
