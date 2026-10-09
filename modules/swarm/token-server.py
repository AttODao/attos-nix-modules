#!/usr/bin/env python3
"""Opt-in private-link token transport. Plaintext HTTP is not authenticated encryption."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import sys


class TokenHandler(BaseHTTPRequestHandler):
    timeout = 5

    def do_GET(self):
        if self.client_address[0] not in self.server.allowed_addresses:
            self.send_error(403)
            return
        if self.path == "/worker-token":
            path = self.server.token
            try:
                body = path.read_bytes()
            except OSError:
                self.send_error(503)
                return
        else:
            name = self.path.removeprefix("/networks-ready/")
            if self.path != "/networks-ready" and not (
                self.path.startswith("/networks-ready/")
                and re.fullmatch(r"backend-[a-z0-9-]+", name) is not None
            ):
                self.send_error(404)
                return
            if not self.server.marker.joinpath("ready").is_file() or (
                self.path != "/networks-ready" and not self.server.marker.joinpath(name).is_file()
            ):
                self.send_error(503)
                return
            body = b""
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer((sys.argv[1], int(sys.argv[2])), TokenHandler)
    server.token = Path(sys.argv[3])
    server.marker = Path(sys.argv[4])
    server.allowed_addresses = sys.argv[5:]
    server.serve_forever()
