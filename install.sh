#!/bin/bash
# droneid-go installer
# Auto-installs on WarDragon kits (x86_64 or arm64), manual mode for other systems
# Usage: sudo ./install.sh [--legacy]

set -e

# ── Change this if your username is not 'dragon' ──────────────────────────────
WARDRAGON_USER="dragon"
# ──────────────────────────────────────────────────────────────────────────────

WARDRAGON_HOME="/home/$WARDRAGON_USER"
INSTALL_DIR="$WARDRAGON_HOME/WarDragon/droneid-go"
SERVICE_NAME="zmq-decoder"
OLD_SERVICE="wifi-receiver"
OLD_BLE_SERVICE="sniff-receiver"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_MODE=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --legacy)
            LEGACY_MODE=true
            ;;
        --help|-h)
            echo "Usage: sudo ./install.sh [--legacy]"
            echo ""
            echo "Options:"
            echo "  --legacy    Use legacy mode with external sniffle BLE pipeline"
            echo "              (keeps sniff-receiver service running)"
            echo ""
            echo "Default install uses native BLE support (-ble auto) and"
            echo "stops/disables the sniff-receiver service."
            exit 0
            ;;
    esac
done

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

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        BINARY_NAME="droneid-linux-x86_64"
        ;;
    aarch64|arm64)
        BINARY_NAME="droneid-linux-arm64"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        ;;
esac

info "Detected architecture: $ARCH"

if [ "$LEGACY_MODE" = true ]; then
    info "Legacy mode: using external sniffle BLE pipeline"
    SERVICE_FILE="zmq-decoder-legacy.service"
else
    info "Default mode: using native BLE support"
    SERVICE_FILE="zmq-decoder.service"
fi

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

# Detect if this is a WarDragon kit (x86_64 or arm64)
IS_WARDRAGON_KIT=false
if [ -d "$WARDRAGON_HOME/WarDragon" ]; then
    # Check for DragonSync (directory or service)
    if [ -d "$WARDRAGON_HOME/WarDragon/DragonSync" ] || \
       systemctl list-unit-files | grep -q "dragonsync" 2>/dev/null; then
        IS_WARDRAGON_KIT=true
    fi
fi

if [ "$IS_WARDRAGON_KIT" = true ]; then
    info "WarDragon kit detected - performing full auto-install"
else
    warn "WarDragon kit not detected"
    warn "Auto-install is only supported on WarDragon kits"
    echo ""
    echo "For manual installation:"
    echo "  1. Copy bin/$BINARY_NAME to your preferred location"
    echo "  2. Edit $SERVICE_FILE to match your system paths"
    echo "  3. Install service: sudo cp $SERVICE_FILE /etc/systemd/system/zmq-decoder.service"
    echo "  4. Reload systemd: sudo systemctl daemon-reload"
    echo "  5. Enable service: sudo systemctl enable zmq-decoder"
    echo "  6. Start service: sudo systemctl start zmq-decoder"
    echo ""
    echo "Or run manually:"
    echo "  sudo ./bin/$BINARY_NAME -i <wifi_interface> -z -v"
    exit 0
fi

# --- WarDragon kit auto-install below ---

if [ ! -f "$SCRIPT_DIR/$SERVICE_FILE" ]; then
    error "Service file '$SERVICE_FILE' not found in $SCRIPT_DIR"
fi

# Install required system dependencies
info "Checking system dependencies..."
MISSING_PKGS=""
for pkg in iproute2 iw libpcap0.8 libzmq5; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done
if [ -n "$MISSING_PKGS" ]; then
    info "Installing missing packages:$MISSING_PKGS"
    apt-get install -y -q $MISSING_PKGS || warn "Some packages failed to install - WiFi capture may not work"
else
    info "All dependencies present"
fi

info "Installing droneid-go..."

# Note whether the capture service is already running, but do NOT stop it to
# swap the binary. Replacing the file with mv (below) is atomic — the running
# process keeps the old binary until it next restarts — so there's no need to
# stop it. Stopping/restarting on a live kit flips the WiFi adapter out of and
# back into monitor mode on a warm device, and some USB WiFi drivers can fault
# when the radio is reconfigured that way. A clean reboot re-initializes the
# adapter safely, so if it's already running we stage the new version and ask
# for a reboot instead of restarting in place.
WAS_ACTIVE=false
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    WAS_ACTIVE=true
fi

# Stop old wifi-receiver service if running (replaced in both modes)
if systemctl is-active --quiet "$OLD_SERVICE" 2>/dev/null; then
    info "Stopping $OLD_SERVICE service..."
    systemctl stop "$OLD_SERVICE"
fi

if systemctl is-enabled --quiet "$OLD_SERVICE" 2>/dev/null; then
    info "Disabling $OLD_SERVICE service..."
    systemctl disable "$OLD_SERVICE"
fi

# Handle sniff-receiver based on mode
if [ "$LEGACY_MODE" = true ]; then
    # Legacy mode: ensure sniff-receiver is running for BLE pipeline
    if systemctl list-unit-files | grep -q "$OLD_BLE_SERVICE" 2>/dev/null; then
        if ! systemctl is-active --quiet "$OLD_BLE_SERVICE" 2>/dev/null; then
            info "Starting $OLD_BLE_SERVICE service (required for legacy BLE pipeline)..."
            systemctl start "$OLD_BLE_SERVICE" || warn "Failed to start $OLD_BLE_SERVICE"
        else
            info "$OLD_BLE_SERVICE is already running (legacy BLE pipeline)"
        fi
    else
        warn "$OLD_BLE_SERVICE service not found - BLE capture may not work"
        warn "Ensure $WARDRAGON_HOME/WarDragon/DroneID/sniffle/python_cli/sniff_receiver.py is running on port 4222"
    fi
else
    # Default mode: stop/disable sniff-receiver (replaced by native -ble auto)
    if systemctl is-active --quiet "$OLD_BLE_SERVICE" 2>/dev/null; then
        info "Stopping $OLD_BLE_SERVICE service (replaced by native BLE support)..."
        systemctl stop "$OLD_BLE_SERVICE"
    fi

    if systemctl is-enabled --quiet "$OLD_BLE_SERVICE" 2>/dev/null; then
        info "Disabling $OLD_BLE_SERVICE service..."
        systemctl disable "$OLD_BLE_SERVICE"
    fi
fi

# Create install directory if needed
info "Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Install binary via temp file + rename to avoid 'Text file busy' errors
info "Installing binary to $INSTALL_DIR/droneid"
cp "$BINARY_PATH" "$INSTALL_DIR/droneid.new"
chmod +x "$INSTALL_DIR/droneid.new"
mv "$INSTALL_DIR/droneid.new" "$INSTALL_DIR/droneid"

# Copy and patch support files, substituting the actual home path
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    info "Copying support files to $INSTALL_DIR"
    # Patch service file: replace /home/dragon with actual home path
    sed "s|/home/dragon|$WARDRAGON_HOME|g" "$SCRIPT_DIR/$SERVICE_FILE" \
        > "$INSTALL_DIR/zmq-decoder.service"
    cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/" 2>/dev/null || true
else
    # Running from install dir — patch in place if needed
    if [ "$WARDRAGON_HOME" != "/home/dragon" ]; then
        sed -i "s|/home/dragon|$WARDRAGON_HOME|g" "$INSTALL_DIR/zmq-decoder.service"
    fi
fi

# Install udev rule for stable TI XDS110 Sniffle dongle naming.
# Creates /dev/sniffle-ti0 for TI dongles (VID:PID 0451:bef3, interface 00).
# Reloading the rules is always safe. Only re-trigger TTY uevents when the
# service isn't running — a live droneid-go holds the serial dongles open, and
# droneid-go falls back to probing if the symlink is absent anyway.
if [ -f "$SCRIPT_DIR/70-sniffle.rules" ]; then
    info "Installing udev rule for TI Sniffle dongle (/dev/sniffle-ti0)..."
    cp "$SCRIPT_DIR/70-sniffle.rules" /etc/udev/rules.d/70-sniffle.rules
    udevadm control --reload-rules 2>/dev/null || true
    if [ "$WAS_ACTIVE" != true ]; then
        udevadm trigger --subsystem-match=tty 2>/dev/null || true
    fi
fi

# Install systemd service (always installs as zmq-decoder.service)
info "Installing systemd service..."
cp "$INSTALL_DIR/zmq-decoder.service" /etc/systemd/system/

# Reload systemd
info "Reloading systemd..."
systemctl daemon-reload

# Enable the service so it starts on boot (it always has).
info "Enabling $SERVICE_NAME service..."
systemctl enable "$SERVICE_NAME"

if [ "$WAS_ACTIVE" = true ]; then
    # Apply the update in place, with NO radio reconfigure and no reboot. The
    # crash risk is the capture adapter being flipped monitor->managed->monitor
    # on a warm device. A graceful stop lets the OLD binary flip it back to
    # managed on the way out, so we SIGKILL it instead: the card is simply left
    # in monitor. The new binary then sees it is already in monitor and skips the
    # down/set-type/up reconfigure entirely (idempotent setup).
    info "Applying update in place (no radio reconfigure)..."
    systemctl kill -s KILL "$SERVICE_NAME" 2>/dev/null || true
    sleep 2
    # Start covers the case where the unit's Restart= policy did not already
    # relaunch it; it is a no-op if the new binary is already back up.
    systemctl start "$SERVICE_NAME" 2>/dev/null || true
else
    info "Starting $SERVICE_NAME service..."
    systemctl start "$SERVICE_NAME"
fi

# Check status
sleep 1
if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "Service is running on the new version."
    echo ""
    echo "Status:"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -15
else
    warn "Service did not come back up. Check with:"
    echo "  sudo journalctl -u $SERVICE_NAME -n 50"
fi

echo ""
info "Installation complete!"
if [ "$LEGACY_MODE" = true ]; then
    info "Running in LEGACY mode (external sniffle BLE pipeline on port 4222)"
else
    info "Running in DEFAULT mode (native BLE via -ble auto)"
fi
echo ""
echo "Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME    # Check status"
echo "  sudo journalctl -u $SERVICE_NAME -f    # View logs"
echo "  sudo systemctl restart $SERVICE_NAME   # Restart service"
echo "  sudo systemctl stop $SERVICE_NAME      # Stop service"
