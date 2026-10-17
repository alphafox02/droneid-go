#!/bin/bash
# droneid-check — quick system health check for droneid-go
# Run as root for full diagnostics

echo "=== droneid-go System Check ==="

# 1. Service status
echo -e "\n--- Service ---"
if systemctl is-active --quiet zmq-decoder 2>/dev/null; then
    echo "  zmq-decoder: RUNNING"
    uptime=$(systemctl show zmq-decoder --property=ActiveEnterTimestamp --value 2>/dev/null)
    [ -n "$uptime" ] && echo "  Started: $uptime"
else
    echo "  zmq-decoder: NOT RUNNING"
fi

# 2. USB devices
echo -e "\n--- Devices ---"
found_ble=false
found_wifi=false
found_esp=false

# BLE dongles
for dev in /dev/sniffle* /dev/ttyACM* /dev/ttyUSB*; do
    [ -e "$dev" ] || continue
    label=""
    # Check if it's a known symlink
    case "$dev" in
        /dev/sniffle*) label="(sniffle symlink)" ;;
        /dev/esp*)     label="(ESP32)"; continue ;;
    esac
    echo "  $dev $label"
    found_ble=true
done

# WiFi interfaces
for iface in /sys/class/net/wl*; do
    [ -d "$iface/wireless" ] || continue
    name=$(basename "$iface")
    usb="onboard"
    readlink -f "$iface/device" 2>/dev/null | grep -q usb && usb="USB"
    driver=$(basename "$(readlink -f "$iface/device/driver")" 2>/dev/null)
    echo "  $name ($usb, driver: ${driver:-unknown})"
    found_wifi=true
done

# ESP32
for dev in /dev/esp*; do
    [ -e "$dev" ] || continue
    target=$(readlink -f "$dev" 2>/dev/null)
    echo "  $dev -> $target (ESP32)"
    found_esp=true
done

$found_ble  || echo "  No BLE dongles found"
$found_wifi || echo "  No WiFi interfaces found"
$found_esp  || echo "  No ESP32 devices found"

# 3. ZMQ output (quick 2-second listen)
echo -e "\n--- ZMQ Port 4224 ---"
if command -v python3 &>/dev/null && python3 -c "import zmq" 2>/dev/null; then
    timeout 3 python3 -c "
import zmq, json, sys
ctx = zmq.Context()
s = ctx.socket(zmq.SUB)
s.connect('tcp://127.0.0.1:4224')
s.subscribe(b'')
s.setsockopt(zmq.RCVTIMEO, 2000)
try:
    msg = json.loads(s.recv())
    print('  Receiving data: YES')
    for item in (msg if isinstance(msg, list) else [msg]):
        if isinstance(item, dict) and 'Basic ID' in item:
            b = item['Basic ID']
            t = b.get('transport', '?')
            f = b.get('frequency_mhz', '?')
            rid = b.get('id', '?')
            print(f'  Last frame: {t} @ {f} MHz (ID: {rid})')
            break
except zmq.Again:
    print('  Receiving data: NO (no frames in 2s)')
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null
else
    # Fallback: just check if port is listening
    if ss -tlnp 2>/dev/null | grep -q ':4224'; then
        echo "  Port 4224: LISTENING (install python3-zmq for full check)"
    else
        echo "  Port 4224: NOT LISTENING"
    fi
fi

# 4. Ask droneid for health (SIGUSR1)
echo -e "\n--- Health Status ---"
PID=$(pidof droneid)
if [ -n "$PID" ]; then
    kill -USR1 "$PID" 2>/dev/null
    sleep 0.5
    # Try journalctl first, fall back to syslog
    if journalctl -u zmq-decoder --no-pager -n 30 2>/dev/null | grep -A 20 "Health Status"; then
        :
    else
        echo "  SIGUSR1 sent to PID $PID — check logs manually"
    fi
else
    echo "  droneid not running (PID not found)"
fi

echo ""
