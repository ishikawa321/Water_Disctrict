"""Check published Windows processes. Usage: python smoke-release.py RELEASE_FOLDER.

Optional ConnectionStrings__WaterDistrict enables a configured readiness check.
This tool creates no accounts/records, and stops only processes it starts.
"""
import ctypes
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request


def request(port, path):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=2) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def window_title(pid):
    titles = []
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

    @callback_type
    def visit(handle, _):
        owner = ctypes.c_ulong()
        ctypes.windll.user32.GetWindowThreadProcessId(handle, ctypes.byref(owner))
        if owner.value == pid:
            text = ctypes.create_unicode_buffer(512)
            ctypes.windll.user32.GetWindowTextW(handle, text, len(text))
            if text.value:
                titles.append(text.value)
        return True

    ctypes.windll.user32.EnumWindows(visit, 0)
    return titles


def stop(process):
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=10)


def main():
    release = Path(sys.argv[1]).resolve()
    if sys.platform != "win32":
        raise RuntimeError("This smoke check runs the published Windows x64 executables.")
    with socket.socket() as address:
        address.bind(("127.0.0.1", 0))
        port = address.getsockname()[1]
    hidden = subprocess.STARTUPINFO()
    hidden.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    hidden.wShowWindow = 0
    results = {}
    api_dir = release / "Api"
    with (release / "api-smoke.log").open("w", encoding="utf-8") as log:
        api = subprocess.Popen([str(api_dir / "WaterDistrict.Api.exe"), "--urls", f"http://127.0.0.1:{port}"],
                               cwd=api_dir, stdout=log, stderr=log, startupinfo=hidden)
        try:
            deadline = time.monotonic() + 15
            while True:
                if api.poll() is not None:
                    raise RuntimeError("Published API exited; inspect api-smoke.log.")
                try:
                    status, _ = request(port, "/health")
                    if status == 200:
                        break
                except (OSError, urllib.error.URLError):
                    pass
                if time.monotonic() > deadline:
                    raise RuntimeError("Published API did not become available.")
                time.sleep(.25)
            results["health"] = status
            ready, detail = request(port, "/health/ready")
            results["ready"] = {"http": ready, "response": json.loads(detail)}
            expected = 200 if os.environ.get("ConnectionStrings__WaterDistrict") else 503
            assert ready == expected, detail
            for path in ["/api/session", "/api/workflow/concerns", "/api/workflow/tickets", "/api/office/accounts", "/api/office/bills", "/api/office/payments", "/api/office/announcements", "/api/office/summary"]:
                status, _ = request(port, path)
                assert status == 401, (path, status)
                results[path] = status
        finally:
            stop(api)
    desktop_dir = release / "Desktop"
    desktop = subprocess.Popen([str(desktop_dir / "WaterDistrict.Desktop.exe")],
                               cwd=desktop_dir, startupinfo=hidden)
    try:
        deadline = time.monotonic() + 15
        while True:
            assert desktop.poll() is None, "Published desktop exited unexpectedly."
            titles = window_title(desktop.pid)
            if "Water District Administration" in titles:
                results["desktop_window"] = "Water District Administration"
                break
            assert time.monotonic() < deadline, f"Expected desktop window not found: {titles}"
            time.sleep(.25)
    finally:
        stop(desktop)
    (release / "smoke-results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
