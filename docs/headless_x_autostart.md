# Headless auto-start (SSH only)

Use this when you cannot access a local terminal on the Pi desktop. It starts a minimal X server on boot and runs the Tkinter dashboard full-screen.

## 1) Install minimal X stack (over SSH)

```bash
sudo apt update
sudo apt install -y --no-install-recommends \
  xserver-xorg xinit matchbox-window-manager x11-xserver-utils
```

## 2) Clone repo and prepare Python env

```bash
cd /opt
sudo git clone https://github.com/Robbe654321/LaMarzoccoBBW.git
sudo chown -R pi:pi LaMarzoccoBBW
cd LaMarzoccoBBW
chmod +x run-dashboard.sh
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements-dashboard-min.txt
cp -n config/dashboard.example.toml config/dashboard.toml
```

Edit `config/dashboard.toml` if needed (Arduino IP, refresh rate):

```bash
nano config/dashboard.toml
```

## 3) Install X init script and systemd service

```bash
# Install ~/.xinitrc for user pi
sudo install -m 0755 x11/xinitrc /home/pi/.xinitrc
sudo chown pi:pi /home/pi/.xinitrc

# Install system service
sudo install -m 0644 systemd/lama-dashboard.service /etc/systemd/system/lama-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable --now lama-dashboard.service
```

The service will start an X server on display :0 and launch the dashboard on every boot.

## 4) Troubleshooting

- Black screen: ensure HyperPixel drivers are installed and the panel is enabled.
- Service status and logs:
  ```bash
  sudo systemctl status lama-dashboard.service
  journalctl -u lama-dashboard -f
  ```
- If you later enable cloud features, install full deps:
  ```bash
  source .venv/bin/activate
  pip install -r requirements-dashboard.txt
  sudo systemctl restart lama-dashboard.service
  ```

## Quick alternative (if a desktop user is logged in)

If the desktop is already running and user `pi` is logged in, you can launch into that session via SSH:

```bash
sudo -u pi DISPLAY=:0 XAUTHORITY=/home/pi/.Xauthority /opt/LaMarzoccoBBW/run-dashboard.sh >/dev/null 2>&1 &
```

This avoids setting up a headless X server, but requires an active graphical login.

