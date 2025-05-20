# VS Code Tunnel Manager

A comprehensive deployment and management tool for Visual Studio Code Remote Tunnel services on Linux systems.

## Overview

This script simplifies the process of installing, configuring, and managing VS Code Remote Tunnel services on Linux servers or devices. It automates the installation of the VS Code CLI, configures systemd services for tunnels, and provides a user-friendly interface for managing multiple tunnel services.

## Features

- **Easy installation** of VS Code CLI and tunnel services
- **Multi-user support** for managing multiple tunnel instances on the same machine
- **Custom data directory** configuration for each tunnel
- **Service management** (start, stop, enable/disable at boot)
- **Automatic detection** of tunnel registration codes
- **Cleanup functionality** to safely remove tunnels when no longer needed

## Quick Start

### Download the script

```bash
wget https://raw.githubusercontent.com/HNRobert/vscode-tunnel-deployer/main/deploy.bash -O deploy.bash
chmod +x deploy.bash
```

### Run the script

```bash
sudo ./deploy.bash
```

## Usage Guide

The script provides an interactive menu with the following options:

### 1. Install/Configure a new VS Code tunnel service

- Installs the VS Code CLI if not already present
- Creates a systemd service for the tunnel
- Optionally configures a custom name and data directory
- Automatically detects and displays the registration code
- Provides service control instructions

### 2. Pause an existing tunnel service

- Lists all installed tunnel services
- Allows you to select and stop a specific tunnel
- Preserves configuration for later restart

### 3. Remove an existing tunnel service

- Lists all installed tunnel services
- Allows you to select and remove a specific tunnel
- Option to delete or preserve tunnel data

## ⚙️ Service Management

After installation, you can manage your tunnel service with:

```bash
# Start the service
sudo systemctl start vscode-tunnel[-name]

# Stop the service
sudo systemctl stop vscode-tunnel[-name]

# Restart the service
sudo systemctl restart vscode-tunnel[-name]

# Check status
sudo systemctl status vscode-tunnel[-name]

# View logs
sudo journalctl -u vscode-tunnel[-name]

# Enable/disable at boot
sudo systemctl enable vscode-tunnel[-name]
sudo systemctl disable vscode-tunnel[-name]
```

## Notes

- The script requires sudo permissions to install the VS Code CLI and create systemd services
- Each tunnel service runs under the user account that created it
- Custom-named tunnels store their data in `~/.vscode/user-tunnel/<name>`
