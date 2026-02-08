# droneid-go

A high-performance Open Drone ID (ASTM F3411) receiver and decoder.

## Overview

droneid-go captures and decodes Remote ID broadcasts from drones, providing:

- **ASTM F3411-19 and F3411-22a support** - Full Remote ID specification compliance
- **Direct WiFi capture** - Supports WiFi adapters capable of monitor mode
- **BLE support** - Via sniffle (included)
- **DJI receiver support** - Via ZMQ input from SDR-based DJI receiver
- **UART/ESP32 passthrough** - Direct serial connection to ESP32 devices
- **Pcap file analysis** - Offline processing of captured traffic
- **ZMQ pub/sub** - Compatible with DragonSync infrastructure

## License

droneid-go is not open source at this time. See LICENSE file for details.

### Sniffle

The included `sniffle/` subdirectory is licensed under GPL-3.0 - see `sniffle/LICENSE` for details.
Thanks to [@bkerler](https://github.com/bkerler) for the ZMQ-enabled Sniffle fork.

## Prerequisites

- Linux (x86_64)
- WiFi adapter capable of monitor mode (for WiFi capture)
- nRF52840 dongle with Sniffle firmware (for BLE capture)

### System Dependencies

```bash
# Ubuntu/Debian
sudo apt install libpcap0.8 libzmq5

# Fedora
sudo dnf install libpcap zeromq
```

## Installation

For WarDragon systems, use the install script:

```bash
sudo ./install.sh
```

This will:
- Copy files to `/home/dragon/WarDragon/droneid-go/`
- Stop and disable the old `wifi-receiver` service (if running)
- Install and enable the `zmq-decoder` systemd service
- Start the service

## Usage

**Note for WarDragon kits:** On a properly configured kit, the `zmq-decoder`, `dji-receiver`, and `sniff-receiver` services are managed by systemd and start automatically. The examples below are for manual operation or standalone use.

### WiFi capture

**Note:** If upgrading from a Python-based WarDragon setup manually, stop the wifi-receiver service first:
```bash
sudo systemctl stop wifi-receiver
sudo systemctl disable wifi-receiver  # optional, to prevent it starting on boot
```

```bash
# Basic - captures on channel 6 (2.4GHz)
sudo ./droneid -i wlan1 -z -v

# With 5GHz support and channel hopping
sudo ./droneid -i wlan1 -g -z -v

# Custom channel hopping (3s on ch6, 1s on ch149)
sudo ./droneid -i wlan1 -hop -hop-channels "6,149" -hop-cycle "3,1" -z -v
```

### ZMQ-only mode (no WiFi capture)

```bash
# Subscribe to sniffle BLE only
./droneid -zmqclients 127.0.0.1:4222 -z -v

# Subscribe to DJI receiver only
./droneid -dji 127.0.0.1:4221 -z -v

# Subscribe to both sniffle and DJI
./droneid -zmqclients 127.0.0.1:4222 -dji 127.0.0.1:4221 -z -v
```

### BLE capture with sniffle

Sniffle requires an nRF52840 dongle flashed with Sniffle firmware.
See `sniffle/README.md` for firmware flashing instructions.

```bash
# Terminal 1: Start sniffle for BLE Remote ID
# The -l flag enables Long Range (Coded PHY), -e enables extended advertising, -z enables ZMQ output
cd sniffle/python_cli
python3 sniff_receiver.py -l -e -z

# Terminal 2: Run droneid-go to receive and decode BLE frames
./droneid -zmqclients 127.0.0.1:4222 -z -v
```

Sniffle publishes on `tcp://127.0.0.1:4222` by default.

### Process a pcap file

```bash
./droneid -pcap capture.pcap -v
```

### Full example with all inputs

```bash
sudo ./droneid \
  -i wlan1 \
  -g \
  -z \
  -zmqsetting "127.0.0.1:4224" \
  -zmqclients "127.0.0.1:4222" \
  -uart /dev/ttyACM0 \
  -dji "127.0.0.1:4221" \
  -v
```

## Command-line Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i`, `-wifi` | WiFi interface for capture | (none) |
| `-channel` | Initial WiFi channel | 6 |
| `-g` | Use 5GHz channel 149, enables hopping | false |
| `-hop` | Enable channel hopping | false |
| `-hop-channels` | Channels to hop between | 6,149 |
| `-hop-cycle` | Dwell time per channel (seconds) | 3,1 |
| `-no-hop` | Disable hopping when -g is set | false |
| `-z` | Enable ZMQ publisher | false |
| `-v` | Verbose output | false |
| `-zmqsetting` | ZMQ publisher bind address | 127.0.0.1:4224 |
| `-zmqclients` | ZMQ subscriber endpoints | 127.0.0.1:4222 |
| `-uart` | UART device for ESP32 passthrough | (none) |
| `-uart-baud` | UART baud rate | 115200 |
| `-dji` | DJI receiver ZMQ endpoint | (none) |
| `-pcap` | Process pcap file (offline mode) | (none) |
| `-version` | Show version | |

## Output

droneid-go publishes decoded Remote ID messages via ZMQ in JSON format, compatible with DragonSync and other consumers.

## References

- ASTM F3411-19: Standard Specification for Remote ID and Tracking
- ASTM F3411-22a: Updated Remote ID specification
