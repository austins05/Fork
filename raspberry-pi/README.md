# Raspberry Pi Temperature Monitor

PeerTalk USB temperature monitoring daemon for Rotorsync iPad app.

## Files

- `peertalk_temp_sender.py` - Main daemon that reads SMTC thermocouples and sends data via PeerTalk
- `temp-monitor.service` - Systemd service for auto-start on boot

## Features

- Reads actual temperature from SMTC HAT boards (6 CHT + 6 EGT)
- Falls back to simulated data if hardware not available
- Sends data to iPad via PeerTalk (USB)
- Auto-starts on boot
- Auto-restarts on failure
- No "address already in use" errors

## Installation

1. Copy files to Pi:
```bash
scp peertalk_temp_sender.py pi@raspberrypi:~/
scp temp-monitor.service pi@raspberrypi:/tmp/
```

2. Install service:
```bash
ssh pi@raspberrypi
sudo mv /tmp/temp-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable temp-monitor
sudo systemctl start temp-monitor
```

3. Check status:
```bash
sudo systemctl status temp-monitor
sudo journalctl -u temp-monitor -f
```

## Hardware

- **SMtc HAT Boards**: 2x stacked (stack level 0 and 1)
- **Thermocouples**: K-type, 12 total (6 CHT + 6 EGT)
- **I2C Addresses**: 0x16 (EGT board), 0x17 (CHT board)
- **Channel Mapping**: Channels 1-4, 7-8 (probes 1-6)

## Temperature Thresholds

- **CHT**: 450°F danger, 420°F warning, 250-500°F scale
- **EGT**: 1650°F danger, 1550°F warning, 1200-1700°F scale

## Service Management

- Start: `sudo systemctl start temp-monitor`
- Stop: `sudo systemctl stop temp-monitor`
- Restart: `sudo systemctl restart temp-monitor`
- Status: `sudo systemctl status temp-monitor`
- Logs: `sudo journalctl -u temp-monitor -f`

## PeerTalk Protocol

- **Port**: 2345 (forwarded via iproxy)
- **Frame Type**: 100 (temperature data)
- **Format**: `version (1), type (100), tag (0), payloadSize`
- **Payload**: JSON with CHT and EGT arrays

```json
{
  "cht": [385, 390, 382, 388, 391, 387],
  "egt": [1385, 1420, 1390, 1410, 1405, 1398],
  "timestamp": 1699216123.45,
  "unit": "F"
}
```
