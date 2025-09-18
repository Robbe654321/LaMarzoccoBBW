# Raspberry Pi Dashboard Setup

This guide walks through installing and running the touchscreen dashboard on a
Raspberry Pi Zero 2 W with a HyperPixel 4.0 Square (720×720) display.

## 1. Prepare Raspberry Pi OS & HyperPixel

1. Flash the latest Raspberry Pi OS Lite (32-bit) image to a microSD card.
2. Boot the Pi, connect to Wi-Fi, and update the base system:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```

3. Install the HyperPixel drivers (follow Pimoroni's script or manual guide):

   ```bash
   curl https://get.pimoroni.com/hyperpixel4 | bash
   sudo reboot
   ```

   > Tip: choose the **square** display option when prompted.

4. After reboot, set the display rotation if required:

   ```bash
   sudo hyperpixel-rotate right   # or left, normal, inverted
   ```

## 2. Install dependencies

```bash
sudo apt install -y git python3 python3-pip python3-venv python3-tk fonts-dejavu
```

Clone this repository and create a virtual environment:

```bash
cd /opt
sudo git clone https://github.com/Robbe654321/LaMarzoccoBBW.git
sudo chown -R robbewillemsens:robbewillemsens LaMarzoccoBBW
cd LaMarzoccoBBW
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
# On Pi Zero 2 W (512MB RAM), prefer the minimal set:
# pip install -r requirements-dashboard-min.txt
# Only install cloud deps if you enable cloud later:
# pip install -r requirements-dashboard.txt
```

## 3. Configure the dashboard

Copy the example config and edit the values (cloud disabled by default to save RAM):

```bash
cp config/dashboard.example.toml config/dashboard.toml
nano config/dashboard.toml
```

Key sections:

- `refresh_rate_ms`: UI update cadence (default 200 ms).
- `[arduino]`: IP for the Arduino paddle controller (`http://192.168.0.177`).
- `[shot]`: Default target weight in grams.
- `[ui]`: Colours and fullscreen preference (set `fullscreen = true` for HyperPixel).

### (Optional) Enable La Marzocco Cloud data (uses extra RAM)

1. Generate an installation key once (requires `pylamarzocco`):

   ```bash
   source .venv/bin/activate
   python - <<'PY'
   from pylamarzocco.util import generate_installation_key
   from uuid import uuid4

   key = generate_installation_key(str(uuid4()))
   as_dict = key.to_dict()

   print("installation_id:", as_dict["installation_id"])
   print("installation_secret_b64:", as_dict["secret"])
   print("installation_private_key_b64:", as_dict["private_key"])
   PY
   ```

2. Edit `config/dashboard.toml` and set:

   ```toml
   [la_marzocco]
   enable_cloud = true
   serial_number = "LMxxxxxx"
   username = "your@email.com"
   password = "app-or-cloud-password"
   installation_id = "<printed installation_id>"
   installation_secret_b64 = "<printed installation_secret_b64>"
   installation_private_key_b64 = "<printed installation_private_key_b64>"
   ```

3. The dashboard currently pulls machine mode, brew timer, target weight, and
   coffee boiler data. Real-time weight/flow remain simulated until the La
   Marzocco API exposes scale telemetry; keep the simulator running in tandem.

## Memory tips for Pi Zero 2 W (512MB)

- Use Raspberry Pi OS Lite (64-bit is fine) and avoid running a browser.
- Keep `enable_cloud = false` unless you really need cloud widgets.
- Use the minimal requirements file first: `pip install -r requirements-dashboard-min.txt`.
- Reduce UI refresh rate in `config/dashboard.toml` (e.g. `refresh_rate_ms = 300`).
- Set GPU memory to 64MB in `sudo raspi-config` (Advanced Options → Memory Split).
- Optional: enable zram to reduce swapping overhead:
  - `sudo apt install -y zram-tools && sudo systemctl enable --now zram-config`
- If you later enable cloud, stop the app, install full deps, then restart:
  - `pip install -r requirements-dashboard.txt`

## 4. Run the dashboard

```bash
source .venv/bin/activate
python dashboard.py
```

To exit a fullscreen session, press `Ctrl+Q` in the terminal or `Ctrl+C` in the
console window.

## 5. Auto-start on boot (optional)

Create a systemd service to launch the dashboard for user `robbewillemsens`:

```bash
sudo tee /etc/systemd/system/lama-dashboard.service > /dev/null <<'EOF'
[Unit]
Description=La Marzocco HyperPixel Dashboard
After=network-online.target
Wants=network-online.target

[Service]
User=robbewillemsens
WorkingDirectory=/opt/LaMarzoccoBBW
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/robbewillemsens/.Xauthority
ExecStart=/opt/LaMarzoccoBBW/.venv/bin/python /opt/LaMarzoccoBBW/dashboard.py
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now lama-dashboard.service
```

## 6. Next steps / integration ideas

- Replace simulated weight/flow with live data from a connected Acaia scale or
  the machine's brew-by-weight data once available via the websocket API.
- Expose MQTT or WebSocket endpoints so other systems (e.g. Home Assistant)
  can consume the metrics.
- Add soft buttons for La Marzocco actions (power, steam, profiles) once
  authentication is proven stable.
