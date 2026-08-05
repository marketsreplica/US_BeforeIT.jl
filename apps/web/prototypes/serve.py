#!/usr/bin/env python3
"""Static server + API proxy for BeforeIT visual prototypes.

Serves each prototype folder at http://127.0.0.1:8090/<folder>/ and proxies
every /api/* request to the running Julia backend at http://127.0.0.1:8080.
This keeps the prototypes on real plumbing (datasets, knobs, run creation,
status polling, summaries) without modifying the running server.

Usage:  python3 serve.py [port]
"""

import http.server
import json
import pathlib
import socketserver
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
BACKEND = "http://127.0.0.1:8080"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8090

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".woff2": "font/woff2",
}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, status, body, ctype="application/json; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _proxy(self):
        url = BACKEND + self.path
        length = int(self.headers.get("Content-Length") or 0)
        payload = self.rfile.read(length) if length else None
        req = urllib.request.Request(url, data=payload, method=self.command)
        if payload is not None:
            req.add_header("Content-Type", self.headers.get("Content-Type") or "application/json")
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
                ctype = resp.headers.get("Content-Type") or "application/json"
                self._send(resp.status, body, ctype)
        except urllib.error.HTTPError as e:
            self._send(e.code, e.read() or b"{}", e.headers.get("Content-Type") or "application/json")
        except Exception as e:  # backend down, timeout, ...
            msg = json.dumps({"error": "proxy_failure", "details": str(e)}).encode()
            self._send(502, msg)

    def _static(self):
        raw = self.path.split("?", 1)[0].split("#", 1)[0]
        if raw.endswith("/"):
            raw += "index.html"
        target = (ROOT / raw.lstrip("/")).resolve()
        if not str(target).startswith(str(ROOT)):
            self._send(403, b'{"error":"forbidden"}')
            return
        if target.is_dir():
            target = target / "index.html"
        if not target.is_file():
            self._send(404, b'{"error":"not found"}')
            return
        ctype = CONTENT_TYPES.get(target.suffix.lower(), "application/octet-stream")
        self._send(200, target.read_bytes(), ctype)

    def do_GET(self):
        if self.path.startswith("/api/"):
            self._proxy()
        else:
            self._static()

    def do_POST(self):
        if self.path.startswith("/api/"):
            self._proxy()
        else:
            self._send(405, b'{"error":"method not allowed"}')


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"Prototype server on http://127.0.0.1:{PORT}/  (proxying /api -> {BACKEND})")
    ThreadingServer(("127.0.0.1", PORT), Handler).serve_forever()
