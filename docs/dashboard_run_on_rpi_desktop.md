# Run the Dashboard on Raspberry Pi OS (Desktop)

These steps assume you see the Raspberry Pi OS desktop on your HyperPixel screen. This guide shows how to run the Tkinter dashboard manually and how to auto‑start it at login. It avoids heavy browsers and keeps memory use low.

## 1) One‑time setup

Open a Terminal on the Pi (Menu → Accessories → Terminal) and run:

```bash
sudo apt update
sudo apt install -y python3-venv python3-tk fonts-dejavu git
```

Clone the repo (if not already):

```bash
cd /opt
sudo git clone https://github.com/Robbe654321/LaMarzoccoBBW.git
sudo chown -R $USER:$USER LaMarzoccoBBW
cd LaMarzoccoBBW
```

Create a virtual environment and install minimal dependencies (recommended for 512MB RAM):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements-dashboard-min.txt
```

Copy the example configuration and edit it:

```bash
cp config/dashboard.example.toml config/dashboard.toml
nano config/dashboard.toml
```

Suggested changes:
- `refresh_rate_ms = 300`
- `[arduino].host = "192.168.0.177"` (aanpassen indien nodig)
- Laat `la_marzocco.enable_cloud = false` (scheelt RAM); later kun je overschakelen naar `requirements-dashboard.txt` en cloud inschakelen.

## 2) Handmatig starten (Desktop is actief)

Open een Terminal in de map en start:

```bash
cd /opt/LaMarzoccoBBW
source .venv/bin/activate
python dashboard.py
```

Als je per ongeluk vanaf een console zonder desktop start en je krijgt de fout “no $DISPLAY”, start dan vanuit een Terminalvenster op het bureaublad.

## 3) Auto‑start bij inloggen (LXDE autostart)

Maak een klein startscript dat de venv activeert en de app start:

```bash
cat > /opt/LaMarzoccoBBW/run-dashboard.sh <<'EOF'
#!/bin/sh
cd /opt/LaMarzoccoBBW
. .venv/bin/activate
exec python dashboard.py
EOF
sudo chmod +x /opt/LaMarzoccoBBW/run-dashboard.sh
```

Maak een .desktop bestand zodat LXDE het bij login start:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/lama-dashboard.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=La Marzocco Dashboard
Exec=/opt/LaMarzoccoBBW/run-dashboard.sh
X-GNOME-Autostart-enabled=true
EOF
```

Log uit en weer in (of herstart) om te testen.

## 4) Alternatief: systemd user‑service

Dit start de app na inloggen in je grafische sessie.

```bash
systemctl --user enable --now default.target 2>/dev/null || true
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/lama-dashboard.service <<'EOF'
[Unit]
Description=La Marzocco Dashboard (Tkinter)
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
WorkingDirectory=/opt/LaMarzoccoBBW
ExecStart=/opt/LaMarzoccoBBW/.venv/bin/python /opt/LaMarzoccoBBW/dashboard.py
Restart=on-failure

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now lama-dashboard.service
```

Als je een DISPLAY‑fout krijgt, is de service te vroeg gestart. In dat geval gebruik de LXDE‑autostartmethode of stel een ExecStartPre in die wacht totdat `$DISPLAY` is gezet.

## 5) Prestatie‑ en geheugen‑tips (Pi Zero 2 W)

- Gebruik `requirements-dashboard-min.txt` (geen cloud) voor laag RAM‑gebruik.
- Zet `refresh_rate_ms` hoger (bijv. 300–500 ms) voor lagere CPU.
- Houd `ui.fullscreen = true` zodat de window manager minimale overhead heeft.
- In `raspi-config` → Advanced → Memory Split: 64MB GPU geheugen is genoeg.
- Zram kan helpen: `sudo apt install -y zram-tools && sudo systemctl enable --now zram-config`.

## 6) Cloud (optioneel)

Wil je klok/boiler/targets uit de cloud toevoegen:
- Installeer extra deps: `pip install -r requirements-dashboard.txt`
- Volg `docs/dashboard_setup.md` → “Enable La Marzocco Cloud data” om installatiekeys te genereren en de TOML‑velden te vullen.

Problemen of vragen? Deel de exacte foutmelding en wat je al geprobeerd hebt.

