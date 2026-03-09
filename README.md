# droneid-go

A high-performance Open Drone ID (ASTM F3411) receiver and decoder for [WarDragon](https://github.com/alphafox02/WarDragon) kits.

## Overview

droneid-go is a unified detection receiver that replaces multiple Python-based services with a single Go binary:

- **ASTM F3411-19 and F3411-22a** - Full Remote ID specification compliance
- **WiFi Remote ID** - Direct monitor mode capture on 2.4/5 GHz (replaces `wifi-receiver`)
- **Native BLE Remote ID** - Built-in Sniffle dongle support for Bluetooth 5 Long Range (replaces `sniff-receiver`)
- **DJI DroneID** - ZMQ input from AntSDR-based DJI receiver
- **UART/ESP32 passthrough** - Direct serial connection to ESP32 devices
- **Pcap file analysis** - Offline processing of captured traffic
- **ZMQ pub/sub** - Single unified output for DragonSync on port 4224

> **v0.3.0** - Native BLE support (`-ble auto`) eliminates the need for the external Python sniffle process.

## What It Replaces

| Old Service | Old Port | droneid-go Equivalent |
|-------------|----------|----------------------|
| `wifi-receiver` (Python) | 4223 | Built-in WiFi capture (`-g`) |
| `sniff-receiver` (Python sniffle) | 4222 | Native BLE (`-ble auto`) |
| `zmq-decoder.py` (aggregator) | 4224 | Unified ZMQ output (`-z`) |

DragonSync now subscribes to a single port (4224) instead of multiple Python services.

## License

droneid-go is not open source at this time. See LICENSE file for details.

### Sniffle Firmware

Native BLE support requires a Sniffle-compatible dongle (nRF52840 or Sonoff CC2652P) pre-flashed with Sniffle firmware. droneid-go communicates with the dongle directly over serial — no Python sniffle process required.

Sniffle is licensed under GPL-3.0. See the [Sniffle repository](https://github.com/bkerler/sniffle) for firmware source and flashing instructions. Thanks to [@bkerler](https://github.com/bkerler) for the ZMQ-enabled fork.

## Prerequisites

- Linux x86_64 (Ubuntu 22.04+) or ARM64 (Ubuntu 24.04, e.g. Raspberry Pi)
- WiFi adapter capable of monitor mode (for WiFi capture)
- Sniffle-compatible BLE dongle (for BLE capture) - nRF52840 or Sonoff CC2652P

> **Note:** The `droneid-linux-arm64` binary is built against libzmq 4.3.5 (Ubuntu 24.04). It requires `libzmq5 >= 4.3.5` at runtime.

### System Dependencies

```bash
# Ubuntu/Debian
sudo apt install libpcap0.8 libzmq5

# Fedora
sudo dnf install libpcap zeromq
```

## Installation

### WarDragon Kits

```bash
cd /home/dragon/WarDragon
git clone https://github.com/alphafox02/droneid-go.git
cd droneid-go
sudo ./install.sh
```

The installer will:
- Detect if this is a WarDragon kit (x86_64 with DragonSync)
- Copy files to `/home/dragon/WarDragon/droneid-go/`
- Stop and disable legacy `wifi-receiver` and `sniff-receiver` services
- Install and enable the `zmq-decoder` systemd service
- Start the service

### Non-WarDragon Systems

On non-WarDragon systems, the installer will display manual setup instructions.

## Usage

**WarDragon kits:** The `zmq-decoder` service runs automatically via systemd. The examples below are for manual operation or standalone use.

### Typical WarDragon deployment (all inputs)

```bash
sudo ./droneid -g -ble auto -uart /dev/esp0 -dji 127.0.0.1:4221 -z -zmqsetting 0.0.0.0:4224
```

This enables:
- WiFi capture with 5 GHz hopping (`-g`)
- Native BLE via auto-detected Sniffle dongle (`-ble auto`)
- ESP32 UART passthrough (`-uart /dev/esp0`)
- DJI DroneID from AntSDR (`-dji 127.0.0.1:4221`)
- ZMQ output on port 4224 for DragonSync (`-z -zmqsetting`)

Missing hardware is handled gracefully - the binary retries connections and continues with whatever is available.

### WiFi only

```bash
# 2.4 GHz only
sudo ./droneid -i wlan1 -z -v

# With 5 GHz support (for Skydio, etc.)
sudo ./droneid -i wlan1 -g -z -v

# Custom channel hopping
sudo ./droneid -i wlan1 -hop -hop-channels "6,149" -hop-cycle "3,1" -z -v
```

### BLE only (native)

```bash
# Auto-detect Sniffle dongle
sudo ./droneid -ble auto -z -v

# Specify device path
sudo ./droneid -ble /dev/sniffle0 -z -v
```

### BLE via legacy sniffle pipeline (v0.2.0)

```bash
# Terminal 1: Start sniffle
cd sniffle/python_cli
python3 sniff_receiver.py -l -e -z

# Terminal 2: Subscribe to sniffle ZMQ output
./droneid -zmqclients 127.0.0.1:4222 -z -v
```

### DJI only

```bash
./droneid -dji 127.0.0.1:4221 -z -v
```

### Process a pcap file

```bash
./droneid -pcap capture.pcap -v
```

## Command-line Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i`, `-wifi` | WiFi interface for capture | (auto-detect) |
| `-channel` | Initial WiFi channel | 6 |
| `-g` | Use 5 GHz channel 149, enables hopping | false |
| `-hop` | Enable channel hopping | false |
| `-hop-channels` | Channels to hop between | 6,149 |
| `-hop-cycle` | Dwell time per channel (seconds) | 3,1 |
| `-no-hop` | Disable hopping when -g is set | false |
| `-ble` | BLE Sniffle dongle (`auto` or device path) | (none) |
| `-z` | Enable ZMQ publisher | false |
| `-v` | Verbose output | false |
| `-zmqsetting` | ZMQ publisher bind address | 127.0.0.1:4224 |
| `-zmqclients` | ZMQ subscriber endpoints (legacy) | (none) |
| `-uart` | UART device for ESP32 passthrough | (none) |
| `-uart-baud` | UART baud rate | 115200 |
| `-dji` | DJI receiver ZMQ endpoint | (none) |
| `-pcap` | Process pcap file (offline mode) | (none) |
| `-version` | Show version | |

## ZMQ Port Reference

| Port | Service | Description |
|------|---------|-------------|
| 4221 | dji_receiver.py | DJI DroneID from AntSDR E200 |
| 4224 | droneid-go | Unified output (WiFi + BLE + UART + DJI) |
| 4225 | WarDragon Monitor | GPS and system status |
| 4222 | ~~sniff-receiver~~ | Deprecated - replaced by `-ble auto` |
| 4223 | ~~wifi-receiver~~ | Deprecated - replaced by built-in WiFi |

## Output

droneid-go publishes decoded Remote ID messages via ZMQ in JSON format, compatible with [DragonSync](https://github.com/alphafox02/DragonSync) and other consumers.

## References

- [WarDragon Documentation](https://github.com/alphafox02/WarDragon)
- ASTM F3411-19: Standard Specification for Remote ID and Tracking
- ASTM F3411-22a: Updated Remote ID specification
