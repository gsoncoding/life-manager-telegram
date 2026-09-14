import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"life-manager-telegram is running\n")

    def log_message(self, *_args):
        pass


def run_bot():
    subprocess.run(["bash", "telegram-bot.sh"], check=False)


if __name__ == "__main__":
    threading.Thread(target=run_bot, daemon=True).start()
    HTTPServer(("0.0.0.0", int(os.environ.get("PORT", "10000"))), HealthHandler).serve_forever()
