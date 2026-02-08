#!/bin/bash
# droneid-go installer
# Auto-installs on WarDragon x86_64 kits, manual mode for other systems

set -e

INSTALL_DIR="/home/dragon/WarDragon/droneid-go"
SERVICE_NAME="zmq-decoder"
OLD_SERVICE="wifi-receiver"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root (sudo ./install.sh)"
fi

# Detect architecture - only x86_64 supported for now
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        BINARY_NAME="droneid-linux-x86_64"
        ;;
    aarch64|arm64|armv7l)
        error "ARM architecture not yet supported. x86_64 only for now."
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        ;;
esac

info "Detected architecture: $ARCH"

# Check for required files - look in bin/ first, then root
if [ -f "$SCRIPT_DIR/bin/$BINARY_NAME" ]; then
    BINARY_PATH="$SCRIPT_DIR/bin/$BINARY_NAME"
elif [ -f "$SCRIPT_DIR/$BINARY_NAME" ]; then
    BINARY_PATH="$SCRIPT_DIR/$BINARY_NAME"
elif [ -f "$SCRIPT_DIR/droneid" ]; then
    # Fallback to generic name (for development)
    BINARY_PATH="$SCRIPT_DIR/droneid"
else
    error "Binary not found for $ARCH. Expected: bin/$BINARY_NAME"
fi

info "Using binary: $BINARY_PATH"

# Detect if this is a WarDragon kit
# Requirements: x86_64, /home/dragon/WarDragon exists, and DragonSync present
IS_WARDRAGON_KIT=false
if [ "$ARCH" = "x86_64" ] && [ -d "/home/dragon/WarDragon" ]; then
    # Check for DragonSync (directory or service)
    if [ -d "/home/dragon/WarDragon/DragonSync" ] || \
       systemctl list-unit-files | grep -q "dragonsync" 2>/dev/null; then
        IS_WARDRAGON_KIT=true
    fi
fi

if [ "$IS_WARDRAGON_KIT" = true ]; then
    info "WarDragon kit detected - performing full auto-install"
else
    warn "WarDragon x86_64 kit not detected"
    warn "Auto-install is only supported on WarDragon kits"
    echo ""
    echo "For manual installation:"
    echo "  1. Copy bin/$BINARY_NAME to your preferred location"
    echo "  2. Edit zmq-decoder.service to match your system paths"
    echo "  3. Install service: sudo cp zmq-decoder.service /etc/systemd/system/"
    echo "  4. Reload systemd: sudo systemctl daemon-reload"
    echo "  5. Enable service: sudo systemctl enable zmq-decoder"
    echo "  6. Start service: sudo systemctl start zmq-decoder"
    echo ""
    echo "Or run manually:"
    echo "  sudo ./bin/$BINARY_NAME -i <wifi_interface> -z -v"
    exit 0
fi

# --- WarDragon kit auto-install below ---

if [ ! -f "$SCRIPT_DIR/zmq-decoder.service" ]; then
    error "Service file 'zmq-decoder.service' not found in $SCRIPT_DIR"
fi

info "Installing droneid-go..."

# Create install directory if needed
info "Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Copy binary (always copy to ensure latest version)
info "Installing binary to $INSTALL_DIR/droneid"
cp "$BINARY_PATH" "$INSTALL_DIR/droneid"
chmod +x "$INSTALL_DIR/droneid"

# Copy other files if not already in install dir
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    info "Copying support files to $INSTALL_DIR"
    cp "$SCRIPT_DIR/zmq-decoder.service" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/" 2>/dev/null || true

    # Copy sniffle if present
    if [ -d "$SCRIPT_DIR/sniffle" ]; then
        info "Copying sniffle directory..."
        cp -r "$SCRIPT_DIR/sniffle" "$INSTALL_DIR/"
    fi
fi

# Stop old wifi-receiver service if running
if systemctl is-active --quiet "$OLD_SERVICE" 2>/dev/null; then
    info "Stopping $OLD_SERVICE service..."
    systemctl stop "$OLD_SERVICE"
fi

if systemctl is-enabled --quiet "$OLD_SERVICE" 2>/dev/null; then
    info "Disabling $OLD_SERVICE service..."
    systemctl disable "$OLD_SERVICE"
fi

# Stop existing zmq-decoder if running
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    info "Stopping existing $SERVICE_NAME service..."
    systemctl stop "$SERVICE_NAME"
fi

# Install systemd service
info "Installing systemd service..."
cp "$INSTALL_DIR/zmq-decoder.service" /etc/systemd/system/

# Reload systemd
info "Reloading systemd..."
systemctl daemon-reload

# Enable and start service
info "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

info "Starting $SERVICE_NAME service..."
systemctl start "$SERVICE_NAME"

# Check status
sleep 1
if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "Service started successfully!"
    echo ""
    echo "Status:"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -15
else
    warn "Service may not have started correctly. Check with:"
    echo "  sudo journalctl -u $SERVICE_NAME -f"
fi

echo ""
info "Installation complete!"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME    # Check status"
echo "  sudo journalctl -u $SERVICE_NAME -f    # View logs"
echo "  sudo systemctl restart $SERVICE_NAME   # Restart service"
echo "  sudo systemctl stop $SERVICE_NAME      # Stop service"
