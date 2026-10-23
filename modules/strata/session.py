"""Strata VT session and unprivileged desktop start/status/stop CLI."""
import argparse
import json
import os
import select
import signal
import subprocess
import sys
import termios
import time
import tty
import urllib.request

import evdev

STOP = False


def request_stop(_signum, _frame):
    global STOP
    STOP = True


def systemctl(*args):
    return subprocess.run([CONFIG["systemctl"], "--no-pager", *args],
                          capture_output=True, text=True, check=False)


def state(unit):
    result = systemctl("show", unit, "--property=ActiveState,SubState,Result")
    return dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)


def stop(unit):
    # Do not return to the greeter until the stop job (including docker stop) ends.
    while True:
        systemctl("stop", unit)
        if state(unit).get("ActiveState") in ("inactive", "failed"):
            return
        time.sleep(1)


def safe(text):
    return "".join(c for c in str(text) if c.isprintable() or c == "\n")


def draw(lines):
    print("\033[2J\033[H" + "\n".join(safe(line) for line in lines), flush=True)


class Inputs:
    def __init__(self):
        self.devices = {}
        self.refresh_at = 0

    def read(self, timeout=0.2):
        if time.monotonic() >= self.refresh_at:
            self.refresh_at = time.monotonic() + 5
            for path in evdev.list_devices():
                if path in self.devices:
                    continue
                try:
                    device = evdev.InputDevice(path)
                    if evdev.ecodes.KEY_POWER in device.capabilities().get(evdev.ecodes.EV_KEY, []):
                        self.devices[path] = device
                    else:
                        device.close()
                except OSError:
                    pass
        devices = list(self.devices.values())
        ready, _, _ = select.select([sys.stdin, *devices], [], [], timeout)
        keys = []
        for source in ready:
            if source is sys.stdin:
                data = os.read(sys.stdin.fileno(), 64)
                if not data:
                    request_stop(None, None)
                elif data and not data.strip(b"\x1b"):
                    keys.extend("escape" for _ in data)
                else:
                    keys.extend(chr(c) for c in data if 32 <= c <= 126 or c in (10, 13))
            else:
                try:
                    for event in source.read():
                        if event.type == evdev.ecodes.EV_KEY and event.code == evdev.ecodes.KEY_POWER and event.value == 1:
                            keys.append("power")
                except OSError:
                    self.devices.pop(source.path, None)
                    source.close()
        return keys

    def close(self):
        for device in self.devices.values():
            device.close()


def log_tail(path):
    try:
        with open(path, "rb") as stream:
            stream.seek(0, os.SEEK_END)
            stream.seek(max(0, stream.tell() - 12000))
            return stream.read().decode("utf-8", "replace").splitlines()[-12:]
    except OSError:
        return ["Waiting for console output..."]


def ready():
    try:
        # Health is deliberately unauthenticated; require loaded, not just HTTP 200.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(CONFIG["healthUrl"], timeout=0.7) as response:
            health = json.load(response)
        return health.get("service") == "strata" and health.get("loaded") is True
    except (OSError, ValueError):
        return False


def session():
    if not sys.stdin.isatty():
        raise SystemExit("Strata session requires a VT")
    for sig in (signal.SIGINT, signal.SIGTSTP, signal.SIGQUIT):
        signal.signal(sig, signal.SIG_IGN)
    for sig in (signal.SIGHUP, signal.SIGTERM):
        signal.signal(sig, request_stop)
    old = termios.tcgetattr(sys.stdin)
    inputs = Inputs()
    unit = None
    confirm = 0
    confirm_kind = None

    def confirmed(keys):
        nonlocal confirm, confirm_kind
        now = time.monotonic()
        for key in keys:
            if key in ("escape", "power"):
                if key == confirm_kind and now < confirm:
                    return True
                confirm_kind, confirm = key, now + 5
        return False

    try:
        tty.setraw(sys.stdin.fileno())  # disables ISIG, including Ctrl-C/Ctrl-Z/Ctrl-\\
        # Keep LF output legible while retaining raw input and ISIG disabled.
        attrs = termios.tcgetattr(sys.stdin)
        attrs[1] |= termios.OPOST | termios.ONLCR
        termios.tcsetattr(sys.stdin, termios.TCSANOW, attrs)
        print("\033[?25l", end="", flush=True)
        deadline = time.monotonic() + 10
        chosen = 0
        digits = ""
        while not STOP and time.monotonic() < deadline:
            lines = ["Strata (API only)", "Select model number + Enter (default: 1)", ""]
            lines += [f"{i + 1}. {model['model']}" for i, model in enumerate(CONFIG["models"])]
            lines += [f"Starting default in {max(0, int(deadline - time.monotonic()) + 1)}s   Selection: {digits}"]
            if time.monotonic() < confirm:
                lines.append("Press the same exit key again within 5s to leave.")
            draw(lines)
            keys = inputs.read()
            if confirmed(keys):
                return
            for key in keys:
                if key.isdecimal():
                    digits = (digits + key)[-6:]
                elif key in ("\n", "\r"):
                    if not digits or 1 <= int(digits) <= len(CONFIG["models"]):
                        chosen = int(digits) - 1 if digits else 0
                        deadline = 0
                    else:
                        digits = ""
        if STOP:
            return
        model = CONFIG["models"][chosen]
        unit = model["unit"]
        started = systemctl("start", "--no-block", unit)
        if started.returncode:
            draw(["Could not start Strata", started.stderr])
            time.sleep(10)
            return
        grace = time.monotonic() + 3
        blanked = False
        next_health = 0
        loaded = False
        last_screen = None
        while not STOP:
            status = state(unit)
            active = status.get("ActiveState", "unknown")
            if active in ("inactive", "failed") and time.monotonic() > grace:
                draw([f"Strata {active}", f"Result: {status.get('Result', 'unknown')}", *log_tail(model["log"]), "Returning to greeter..."])
                time.sleep(10 if active == "failed" else 2)
                return
            if time.monotonic() >= next_health:
                loaded = ready()
                next_health = time.monotonic() + 2
            if loaded and not blanked:
                subprocess.run([CONFIG["setterm"], "--term", "linux", "--blank", "1", "--powerdown", "2"], check=False, stderr=subprocess.DEVNULL)
                blanked = True
            lines = [f"Strata: {model['model']}", CONFIG["endpoint"],
                     f"{active}/{status.get('SubState', '?')} - {'Serving' if loaded else 'Preparing / loading'}",
                     "Esc twice or power button twice within 5s to stop."]
            if time.monotonic() < confirm:
                lines.append("Confirm exit: press the same key again within 5s.")
            # Once serving, avoid continuous VT writes which prevent console blanking.
            signature = (active, status.get("SubState"), loaded, time.monotonic() < confirm)
            if not loaded or signature != last_screen:
                draw(lines + ([""] + log_tail(model["log"]) if not loaded else []))
                last_screen = signature
            if confirmed(inputs.read()):
                break
    finally:
        if unit is not None:
            draw(["Stopping Strata... waiting for GPU memory to be released."])
            stop(unit)
        inputs.close()
        subprocess.run([CONFIG["setterm"], "--term", "linux", "--blank", "0", "--powerdown", "0"], check=False, stderr=subprocess.DEVNULL)
        termios.tcsetattr(sys.stdin, termios.TCSANOW, old)
        print("\033[?25h\033[0m", end="", flush=True)


def wait_for_start(model, offset):
    grace = time.monotonic() + 3
    next_health = 0
    try:
        while True:
            try:
                with open(model["log"], "rb") as stream:
                    if os.fstat(stream.fileno()).st_size < offset:
                        offset = 0
                    stream.seek(offset)
                    print(safe(stream.read().decode("utf-8", "replace")), end="", flush=True)
                    offset = stream.tell()
            except OSError:
                offset = 0
            status = state(model["unit"])
            active = status.get("ActiveState", "unknown")
            if active in ("inactive", "failed") and time.monotonic() >= grace:
                print(f"Strata {active}; Result: {status.get('Result', 'unknown')}", file=sys.stderr)
                raise SystemExit(1)
            if time.monotonic() >= next_health:
                if active == "active" and ready():
                    print(safe(f"Serving {model['model']} at {CONFIG['endpoint']}"))
                    return
                next_health = time.monotonic() + 2
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nDetached; Strata keeps starting. Check progress with `strata-headless status`, stop with `strata-headless stop`.")
        raise SystemExit(130) from None


def main():
    parser = argparse.ArgumentParser(description="On-demand Strata API: VT session or desktop start/status/stop")
    parser.add_argument("command", choices=["session", "start", "status", "stop"])
    parser.add_argument("model", nargs="?")
    parser.add_argument("--no-wait", action="store_true")
    args = parser.parse_args()
    if args.command != "start" and (args.model is not None or args.no_wait):
        parser.error("model and --no-wait are only valid with start")
    if args.command == "start":
        model = CONFIG["models"][0] if args.model is None else next(
            (model for i, model in enumerate(CONFIG["models"], 1)
             if args.model.casefold() == model["model"].casefold() or args.model == str(i)), None)
        if model is None:
            available = ", ".join(f"{i}. {model['model']}" for i, model in enumerate(CONFIG["models"], 1))
            parser.error(f"Unknown model {args.model!r}. Available models: {available}")
        for other in CONFIG["models"]:
            if other != model and state(other["unit"]).get("ActiveState") == "active":
                print(safe(f"Stopping {other['model']} and switching to {model['model']}"), flush=True)
        offset = 0
        if state(model["unit"]).get("ActiveState") == "active":
            try:
                offset = os.path.getsize(model["log"])
            except OSError:
                pass
        started = systemctl("start", "--no-block", model["unit"])
        if started.returncode:
            print(safe(started.stderr), file=sys.stderr)
            print("start is allowed only from the configured user's local active session (the desktop or the Strata greeter session); stop also works over SSH.", file=sys.stderr)
            raise SystemExit(1)
        if not args.no_wait:
            wait_for_start(model, offset)
    elif args.command == "session":
        session()
    else:
        found = False
        for model in CONFIG["models"]:
            current = state(model["unit"]).get("ActiveState")
            if current not in ("inactive", "failed"):
                found = True
                if args.command == "stop":
                    stop(model["unit"])
                else:
                    print(f"{model['unit']} model={model['model']} state={current} ready={'yes' if ready() else 'no'}")
        if args.command == "status":
            if not found:
                print("No active model.")
            print("Endpoint: " + CONFIG["endpoint"])


if __name__ == "__main__":
    with open(sys.argv.pop(1), encoding="utf-8") as stream:
        CONFIG = json.load(stream)
    main()
