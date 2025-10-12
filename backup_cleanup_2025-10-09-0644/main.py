import os

def _load_env(p):

    try:

        with open(p,"r",encoding="utf-8",errors="ignore") as fh:

            for raw in fh:

                line=raw.strip()

                if not line or line.startswith("#") or "=" not in line: continue

                k,v=line.split("=",1)

                os.environ[k]=v

    except Exception as _e:

        pass

_load_env("/opt/system_status_bot/.env")

import os, json, requests
from flask import Flask, request, abort

app = Flask(__name__)

BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
SECRET    = os.environ.get("SECRET", "")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"

@app.get("/health")
def health():
    return "OK", 200

def check_secret():
    incoming = request.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
    if not SECRET or incoming != SECRET:
        abort(403)

@app.post("/webhook")
def webhook():
    check_secret()
    update = request.get_json(silent=True) or {}
    msg = (update.get("message") or update.get("edited_message") or {}) 
    chat = msg.get("chat") or {}
    chat_id = chat.get("id")
    text = (msg.get("text") or "").strip()

    # sehr einfache Antwort-Logik zum Funktionstest
    reply = "pong" if text.lower() == "ping" else "✅ Test erfolgreich! MommyRamona kann wieder mit dir sprechen."

    if chat_id:
        try:
            requests.post(
                f"{TELEGRAM_API}/sendMessage",
                json={"chat_id": chat_id, "text": reply},
                timeout=8
            )
        except Exception:
            # Fehler beim Antworten sollen den Webhook nicht killen
            pass

    # Telegram erwartet schnelles 200
    return "", 200

if __name__ == "__main__":
    # Flask-Dev-Server starten (im Container auf 0.0.0.0:8080)
    app.run(host="0.0.0.0", port=8080)
