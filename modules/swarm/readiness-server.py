#!/usr/bin/env python3
"""Expose only overlay readiness, never files or Swarm credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


class ReadinessHandler(BaseHTTPRequestHandler):
    timeout = 5

    def do_GET(self):
        ready = self.path == "/traefik-network-ready" and self.server.marker.is_file()
        body = b"ready\n" if ready else b""
        self.send_response(200 if ready else 404)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer((sys.argv[1], int(sys.argv[2])), ReadinessHandler)
    server.marker = Path(sys.argv[3])
    server.serve_forever()
