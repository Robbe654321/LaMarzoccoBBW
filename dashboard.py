"""Touch-friendly dashboard for Raspberry Pi HyperPixel display.

This script renders a 720x720 Tkinter UI to monitor the La Marzocco machine,
poll the Arduino paddle controller, and (optionally) connect to the cloud API
through the `pylamarzocco` library. Live weight/flow/shot data is simulated
until real values are pulled from the machine/scale.

The script is designed for a Raspberry Pi Zero 2 W driving a HyperPixel 4.0
Square (720x720) touch screen and avoids heavyweight GUI frameworks or web
renderers.
"""

from __future__ import annotations

import asyncio
import json
import random
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11 fallback
    try:
        import tomli as tomllib  # type: ignore
    except ModuleNotFoundError:
        tomllib = None  # type: ignore

import tkinter as tk
from tkinter import ttk


APP_ROOT = Path(__file__).resolve().parent
CONFIG_PATH = APP_ROOT / "config" / "dashboard.toml"


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


@dataclass
class ArduinoStatus:
    """Mirror of the Arduino HTTP /status response."""

    mode: str = "UNKNOWN"
    paddle: int = 0
    relay_main: int = 0
    override: str = "off"
    flush_active: bool = False
    gesture_enabled: bool = True
    gesture_flush_ms: int = 0
    gesture_pulse_min_ms: int = 0
    gesture_pulse_max_ms: int = 0
    raw: dict[str, Any] = field(default_factory=dict)
    last_error: Optional[str] = None


@dataclass
class ShotMetrics:
    """Aggregated shot/scale metrics for the dashboard."""

    weight_g: float = 0.0
    flow_g_s: float = 0.0
    shot_time_ms: int = 0
    target_weight_g: float = 0.0
    pressure_bar: float = 0.0
    boiler_temp_c: float = 0.0
    group_temp_c: float = 0.0
    brew_state: str = "IDLE"  # e.g. IDLE / BREWING / RINSING
    scale_connected: bool = False
    notes: str = ""


@dataclass
class CombinedState:
    """Container with the latest data for the UI."""

    timestamp: float = field(default_factory=time.time)
    arduino: ArduinoStatus = field(default_factory=ArduinoStatus)
    shot: ShotMetrics = field(default_factory=ShotMetrics)


# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------


def _default_config() -> dict[str, Any]:
    return {
        "refresh_rate_ms": 200,
        "arduino": {
            "host": "192.168.0.177",
            "timeout": 0.6,
        },
        "shot": {
            "target_weight_g": 36.0,
            "simulate": True,
        },
        "la_marzocco": {
            "enable_cloud": False,
            "serial_number": "",
            "username": "",
            "password": "",
            "installation_id": "",
            "installation_secret_b64": "",
            "installation_private_key_b64": "",
        },
        "ui": {
            "fullscreen": False,
            "bg_color": "#101010",
            "fg_color": "#F5F5F5",
            "accent_color": "#3FA7D6",
        },
    }


def _deep_merge(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
    for key, value in overrides.items():
        if (
            isinstance(value, dict)
            and key in base
            and isinstance(base[key], dict)
        ):
            base[key] = _deep_merge(dict(base[key]), value)
        else:
            base[key] = value
    return base


def load_config() -> dict[str, Any]:
    config = _default_config()
    if CONFIG_PATH.exists() and tomllib:
        try:
            with CONFIG_PATH.open("rb") as fh:
                user_cfg = tomllib.load(fh)
            config = _deep_merge(config, user_cfg)
        except Exception as exc:  # pragma: no cover - config parsing error
            print(f"Failed to read {CONFIG_PATH}: {exc}")
    return config


# ---------------------------------------------------------------------------
# Arduino HTTP client
# ---------------------------------------------------------------------------


class ArduinoClient:
    def __init__(self, base_url: str, timeout: float = 0.6) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def fetch_status(self) -> ArduinoStatus:
        url = f"{self.base_url}/status"
        status = ArduinoStatus()
        try:
            with urllib.request.urlopen(url, timeout=self.timeout) as resp:
                payload = resp.read()
            data = json.loads(payload.decode("utf-8"))
            status.mode = str(data.get("mode", "UNKNOWN"))
            status.paddle = int(data.get("paddle", 0))
            status.relay_main = int(data.get("relay_main", 0))
            status.override = str(data.get("override", "off"))
            status.flush_active = bool(data.get("flush_active", False))
            status.gesture_enabled = bool(data.get("gesture_enabled", True))
            status.gesture_flush_ms = int(data.get("gesture_flush_ms", 0))
            status.gesture_pulse_min_ms = int(
                data.get("gesture_pulse_min_ms", 0)
            )
            status.gesture_pulse_max_ms = int(
                data.get("gesture_pulse_max_ms", 0)
            )
            status.raw = data
        except urllib.error.URLError as exc:
            status.last_error = f"HTTP error: {exc.reason}"
        except (ValueError, json.JSONDecodeError) as exc:
            status.last_error = f"Decode error: {exc}"
        except Exception as exc:  # pragma: no cover - unexpected
            status.last_error = f"Unexpected: {exc}"
        return status

    def send_override(self, value: str) -> None:
        url = f"{self.base_url}/override?set={value}"
        try:
            with urllib.request.urlopen(url, timeout=self.timeout):
                pass
        except Exception:
            pass  # Ignore errors; UI will reflect status fetch failures


# ---------------------------------------------------------------------------
# La Marzocco data sources (simulation + optional cloud connector)
# ---------------------------------------------------------------------------


class BaseLaMarzoccoSource:
    def get_snapshot(self) -> ShotMetrics:
        raise NotImplementedError

    def notify_arduino(self, status: ArduinoStatus) -> None:
        """Optional hook to react to paddle state."""


class SimulatedLaMarzoccoSource(BaseLaMarzoccoSource):
    """Simple physics-ish simulation for weight/flow/pressure."""

    def __init__(self, target_weight_g: float) -> None:
        self.target_weight_g = target_weight_g
        self._shot_active = False
        self._shot_start = 0.0
        self._weight = 0.0
        self._flow = 0.0
        self._pressure = 0.0
        self._boiler_temp = 94.0
        self._group_temp = 93.0
        self._last_update = time.monotonic()

    def notify_arduino(self, status: ArduinoStatus) -> None:
        if status.paddle == 1 and not self._shot_active:
            self._shot_active = True
            self._shot_start = time.monotonic()
            self._weight = 0.0
            self._flow = 0.0
        elif status.paddle == 0 and self._shot_active:
            self._shot_active = False
            self._flow = 0.0

    def _tick(self) -> None:
        now = time.monotonic()
        dt = max(0.001, now - self._last_update)
        self._last_update = now

        if self._shot_active:
            elapsed = now - self._shot_start
            # Basic ramp up / ramp down curve
            flow_peak = 2.6  # g/s
            ramp = min(1.0, elapsed / 4.0)
            decay = max(0.2, 1.0 - (self._weight / max(1.0, self.target_weight_g * 1.1)))
            self._flow = flow_peak * ramp * decay + random.uniform(-0.1, 0.1)
            self._flow = max(0.0, self._flow)
            self._weight += self._flow * dt
            self._pressure = 2.0 + 8.0 * ramp * decay + random.uniform(-0.3, 0.3)
        else:
            self._flow *= 0.9
            self._weight *= 0.999
            if self._weight < 0.05:
                self._weight = 0.0
            self._pressure *= 0.8

        # Boiler temperatures drift slowly
        self._boiler_temp += random.uniform(-0.02, 0.02)
        self._group_temp += random.uniform(-0.015, 0.015)

    def get_snapshot(self) -> ShotMetrics:
        self._tick()
        if self._shot_active:
            shot_time_ms = int((time.monotonic() - self._shot_start) * 1000)
            state = "BREWING"
        else:
            shot_time_ms = 0
            state = "IDLE"
        return ShotMetrics(
            weight_g=max(0.0, round(self._weight, 1)),
            flow_g_s=max(0.0, round(self._flow, 2)),
            shot_time_ms=shot_time_ms,
            target_weight_g=self.target_weight_g,
            pressure_bar=max(0.0, round(self._pressure, 2)),
            boiler_temp_c=round(self._boiler_temp, 1),
            group_temp_c=round(self._group_temp, 1),
            brew_state=state,
            scale_connected=True,
            notes="Simulated",
        )


class CloudLaMarzoccoSource(BaseLaMarzoccoSource):
    """Minimal cloud poller using pylamarzocco.

    The connector runs its own asyncio loop in a background thread. If anything
    fails (missing credentials, network issues), it falls back to simulation.
    """

    def __init__(
        self,
        username: str,
        password: str,
        serial_number: str,
        installation_id: str,
        installation_secret_b64: str,
        installation_private_key_b64: str,
        fallback: BaseLaMarzoccoSource,
    ) -> None:
        from pylamarzocco.clients import LaMarzoccoCloudClient
        from pylamarzocco.util import InstallationKey
        from base64 import b64decode
        from cryptography.hazmat.primitives import serialization

        self._fallback = fallback
        self._latest = ShotMetrics(notes="Waiting for cloud...")
        self._lock = threading.Lock()
        self._ready = threading.Event()
        self._stop = threading.Event()

        # Prepare installation key object
        try:
            secret_bytes = b64decode(installation_secret_b64)
            private_key_bytes = b64decode(installation_private_key_b64)
            private_key = serialization.load_der_private_key(
                private_key_bytes, password=None
            )
        except Exception as exc:  # pragma: no cover - misconfiguration
            raise ValueError("Invalid installation key material") from exc
        self._installation_key = InstallationKey(
            installation_id=installation_id,
            secret=secret_bytes,
            private_key=private_key,
        )

        self._username = username
        self._password = password
        self._serial = serial_number
        self._client_cls = LaMarzoccoCloudClient

        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()

    # ------------------------ Async loop management ---------------------
    def _run_loop(self) -> None:
        asyncio.set_event_loop(self._loop)
        self._loop.run_until_complete(self._loop_main())

    async def _loop_main(self) -> None:
        try:
            from pylamarzocco import LaMarzoccoMachine

            client = self._client_cls(
                username=self._username,
                password=self._password,
                installation_key=self._installation_key,
            )

            await client.async_register_client()
            await client.async_get_access_token()

            machine = LaMarzoccoMachine(
                serial_number=self._serial,
                cloud_client=client,
            )

            self._ready.set()

            while not self._stop.is_set():
                try:
                    await machine.get_dashboard()
                    snapshot = self._parse_dashboard(machine)
                    with self._lock:
                        self._latest = snapshot
                except Exception as exc:  # pragma: no cover - network errors
                    with self._lock:
                        self._latest = ShotMetrics(notes=f"Cloud error: {exc}")
                await asyncio.sleep(1.0)

        except Exception as exc:  # pragma: no cover - cloud setup failure
            self._ready.set()
            with self._lock:
                self._latest = ShotMetrics(notes=f"Cloud disabled: {exc}")

    def stop(self) -> None:
        self._stop.set()
        if self._loop.is_running():
            self._loop.call_soon_threadsafe(self._loop.stop)

    # ------------------------ Dashboard parsing ------------------------
    def _parse_dashboard(self, machine: Any) -> ShotMetrics:
        dash = getattr(machine, "dashboard", None)
        if dash is None:
            return ShotMetrics(notes="No dashboard data yet")

        data = dash.to_dict() if hasattr(dash, "to_dict") else dash

        machine_status: dict[str, Any] = {}
        brew_by_weight: dict[str, Any] = {}
        coffee_boiler: dict[str, Any] = {}

        widgets = data.get("widgets", []) if isinstance(data, dict) else []
        for widget in widgets:
            widget_type = widget.get("widget_type") or widget.get("code")
            output = widget.get("output", {})
            if widget_type in ("CM_MACHINE_STATUS", "MachineStatus"):
                machine_status = output
            elif widget_type in ("CM_BREW_BY_WEIGHT_DOSES", "BrewByWeightDoses"):
                brew_by_weight = output
            elif widget_type in ("CM_COFFEE_BOILER", "CoffeeBoiler"):
                coffee_boiler = output

        status = machine_status.get("status", "UNKNOWN")
        brewing_start = machine_status.get("brewingStartTime")
        if isinstance(brewing_start, (int, float)):
            shot_time_ms = int(max(0.0, time.time() * 1000 - brewing_start))
        else:
            shot_time_ms = 0

        target_weight = 0.0
        if brew_by_weight:
            doses = brew_by_weight.get("doses") or {}
            first_dose = doses.get("dose_1") if isinstance(doses, dict) else None
            if isinstance(first_dose, dict):
                target_weight = float(first_dose.get("weight", target_weight))

        boiler_temp = coffee_boiler.get("target", coffee_boiler.get("temperature", 0.0))

        # Real-time weight/flow are not exposed via cloud; keep previous values.
        with self._lock:
            previous = self._latest

        return ShotMetrics(
            weight_g=previous.weight_g,
            flow_g_s=previous.flow_g_s,
            shot_time_ms=shot_time_ms,
            target_weight_g=target_weight or previous.target_weight_g,
            pressure_bar=previous.pressure_bar,
            boiler_temp_c=float(boiler_temp) if boiler_temp else previous.boiler_temp_c,
            group_temp_c=previous.group_temp_c,
            brew_state=status,
            scale_connected=previous.scale_connected,
            notes="Cloud dashboard",
        )

    # ------------------------ Public API ------------------------------
    def get_snapshot(self) -> ShotMetrics:
        if not self._ready.is_set():
            return ShotMetrics(notes="Connecting to cloud...")
        with self._lock:
            if self._latest.notes.startswith("Cloud disabled"):
                return self._fallback.get_snapshot()
            return self._latest

    def notify_arduino(self, status: ArduinoStatus) -> None:
        self._fallback.notify_arduino(status)


# ---------------------------------------------------------------------------
# Data coordinator thread
# ---------------------------------------------------------------------------


class DataCoordinator:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        arduino_cfg = config.get("arduino", {})
        base_url = f"http://{arduino_cfg.get('host', '192.168.0.177')}"
        timeout = float(arduino_cfg.get("timeout", 0.6))

        self.arduino_client = ArduinoClient(base_url, timeout)

        shot_cfg = config.get("shot", {})
        target_weight = float(shot_cfg.get("target_weight_g", 36.0))
        self.sim_source = SimulatedLaMarzoccoSource(target_weight)

        lm_cfg = config.get("la_marzocco", {})
        if lm_cfg.get("enable_cloud"):
            required = [
                lm_cfg.get("username"),
                lm_cfg.get("password"),
                lm_cfg.get("serial_number"),
                lm_cfg.get("installation_id"),
                lm_cfg.get("installation_secret_b64"),
                lm_cfg.get("installation_private_key_b64"),
            ]
            if all(required):
                try:
                    self.lm_source: BaseLaMarzoccoSource = CloudLaMarzoccoSource(
                        username=lm_cfg["username"],
                        password=lm_cfg["password"],
                        serial_number=lm_cfg["serial_number"],
                        installation_id=lm_cfg["installation_id"],
                        installation_secret_b64=lm_cfg["installation_secret_b64"],
                        installation_private_key_b64=lm_cfg[
                            "installation_private_key_b64"
                        ],
                        fallback=self.sim_source,
                    )
                except Exception as exc:  # pragma: no cover - import errors
                    print(f"Cloud source init failed ({exc}), using simulator")
                    self.lm_source = self.sim_source
            else:
                print("Cloud source missing credentials, using simulator")
                self.lm_source = self.sim_source
        else:
            self.lm_source = self.sim_source

        self._state = CombinedState()
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def _loop(self) -> None:
        poll_interval = max(0.1, self.config.get("refresh_rate_ms", 200) / 1000)
        while not self._stop.is_set():
            self._update_once()
            time.sleep(poll_interval)

    def _update_once(self) -> None:
        arduino = self.arduino_client.fetch_status()
        self.lm_source.notify_arduino(arduino)
        shot = self.lm_source.get_snapshot()

        with self._lock:
            self._state = CombinedState(
                timestamp=time.time(),
                arduino=arduino,
                shot=shot,
            )

    def latest(self) -> CombinedState:
        with self._lock:
            return CombinedState(
                timestamp=self._state.timestamp,
                arduino=self._state.arduino,
                shot=self._state.shot,
            )

    def stop(self) -> None:
        self._stop.set()


# ---------------------------------------------------------------------------
# Tkinter UI
# ---------------------------------------------------------------------------


class DashboardApp:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.coordinator = DataCoordinator(config)

        ui_cfg = config.get("ui", {})
        bg = ui_cfg.get("bg_color", "#101010")
        fg = ui_cfg.get("fg_color", "#F5F5F5")
        accent = ui_cfg.get("accent_color", "#3FA7D6")

        root = tk.Tk()
        root.title("La Marzocco BW Dashboard")
        root.configure(bg=bg)
        root.geometry("720x720")
        if ui_cfg.get("fullscreen"):
            root.attributes("-fullscreen", True)

        default_font = ("Helvetica", 16)
        root.option_add("*Font", default_font)

        self.root = root
        self.bg = bg
        self.fg = fg
        self.accent = accent

        self._build_layout()

        refresh_ms = int(config.get("refresh_rate_ms", 200))
        self._schedule_update(refresh_ms)

    # --------------------------- UI layout ------------------------------
    def _build_layout(self) -> None:
        root = self.root
        fg = self.fg
        accent = self.accent

        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)

        main = ttk.Frame(root, padding=12)
        main.grid(sticky="nsew")
        for col in range(2):
            main.columnconfigure(col, weight=1)
        for row in range(4):
            main.rowconfigure(row, weight=1)

        style = ttk.Style(root)
        style.theme_use("clam")
        style.configure("TFrame", background=self.bg)
        style.configure("TLabel", background=self.bg, foreground=fg)
        style.configure("Accent.TLabel", background=self.bg, foreground=accent)

        self.timer_label = ttk.Label(
            main, text="00.0 s", font=("Helvetica", 48, "bold"), style="Accent.TLabel"
        )
        self.timer_label.grid(row=0, column=0, columnspan=2, sticky="n", pady=(0, 12))

        self.weight_label = ttk.Label(
            main, text="0.0 g", font=("Helvetica", 56, "bold")
        )
        self.weight_label.grid(row=1, column=0, sticky="nsew")

        self.flow_label = ttk.Label(
            main, text="Flow 0.0 g/s", font=("Helvetica", 24)
        )
        self.flow_label.grid(row=2, column=0, sticky="nw")

        self.target_label = ttk.Label(
            main, text="Target 0 g", font=("Helvetica", 24)
        )
        self.target_label.grid(row=2, column=1, sticky="ne")

        self.pressure_label = ttk.Label(
            main, text="Pressure 0.0 bar", font=("Helvetica", 24)
        )
        self.pressure_label.grid(row=3, column=0, sticky="sw")

        self.temp_label = ttk.Label(
            main, text="93.0°C / 94.0°C", font=("Helvetica", 24)
        )
        self.temp_label.grid(row=3, column=1, sticky="se")

        # Right-side status panel
        side = ttk.Frame(main)
        side.grid(row=1, column=1, sticky="nsew")
        for i in range(6):
            side.rowconfigure(i, weight=1)
        side.columnconfigure(0, weight=1)

        self.mode_label = ttk.Label(side, text="Mode: ?", font=("Helvetica", 20))
        self.mode_label.grid(row=0, column=0, sticky="w")

        self.paddle_label = ttk.Label(side, text="Paddle: ?", font=("Helvetica", 20))
        self.paddle_label.grid(row=1, column=0, sticky="w")

        self.override_label = ttk.Label(side, text="Override: off", font=("Helvetica", 20))
        self.override_label.grid(row=2, column=0, sticky="w")

        self.flush_label = ttk.Label(side, text="Flush: off", font=("Helvetica", 20))
        self.flush_label.grid(row=3, column=0, sticky="w")

        self.status_label = ttk.Label(
            side, text="", font=("Helvetica", 14), style="Accent.TLabel"
        )
        self.status_label.grid(row=4, column=0, sticky="w")

        btn_frame = ttk.Frame(side)
        btn_frame.grid(row=5, column=0, sticky="sew", pady=(12, 0))
        btn_frame.columnconfigure((0, 1, 2), weight=1)

        self.btn_override_on = ttk.Button(
            btn_frame,
            text="Override 1",
            command=lambda: self.coordinator.arduino_client.send_override("1"),
        )
        self.btn_override_on.grid(row=0, column=0, padx=4, sticky="ew")

        self.btn_override_zero = ttk.Button(
            btn_frame,
            text="Override 0",
            command=lambda: self.coordinator.arduino_client.send_override("0"),
        )
        self.btn_override_zero.grid(row=0, column=1, padx=4, sticky="ew")

        self.btn_override_off = ttk.Button(
            btn_frame,
            text="Override off",
            command=lambda: self.coordinator.arduino_client.send_override("off"),
        )
        self.btn_override_off.grid(row=0, column=2, padx=4, sticky="ew")

    # --------------------------- UI updates ----------------------------
    def _schedule_update(self, interval_ms: int) -> None:
        self.root.after(interval_ms, lambda: self._refresh(interval_ms))

    def _refresh(self, interval_ms: int) -> None:
        state = self.coordinator.latest()
        shot = state.shot
        arduino = state.arduino

        timer_s = shot.shot_time_ms / 1000
        self.timer_label.configure(text=f"{timer_s:05.1f} s")
        self.weight_label.configure(text=f"{shot.weight_g:>5.1f} g")
        self.flow_label.configure(text=f"Flow {shot.flow_g_s:>4.2f} g/s")
        self.target_label.configure(text=f"Target {shot.target_weight_g:>4.1f} g")
        self.pressure_label.configure(text=f"Pressure {shot.pressure_bar:>4.1f} bar")
        self.temp_label.configure(
            text=f"Group {shot.group_temp_c:>4.1f}°C  Coffee {shot.boiler_temp_c:>4.1f}°C"
        )

        self.mode_label.configure(text=f"Mode: {arduino.mode}")
        paddle_txt = "Closed" if arduino.paddle else "Open"
        self.paddle_label.configure(text=f"Paddle: {paddle_txt}")
        self.override_label.configure(text=f"Override: {arduino.override}")
        flush_state = "ON" if arduino.flush_active else "off"
        self.flush_label.configure(
            text=f"Flush: {flush_state} ({arduino.gesture_flush_ms} ms)"
        )

        status_parts = []
        if arduino.last_error:
            status_parts.append(arduino.last_error)
        if shot.notes:
            status_parts.append(shot.notes)
        self.status_label.configure(text=" | ".join(status_parts))

        self._schedule_update(interval_ms)

    def run(self) -> None:
        try:
            self.root.mainloop()
        finally:
            self.coordinator.stop()


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def main() -> None:
    config = load_config()
    app = DashboardApp(config)
    app.run()


if __name__ == "__main__":
    main()
