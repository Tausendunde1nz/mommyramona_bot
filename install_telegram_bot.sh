#!/usr/bin/env bash
set -euo pipefail

echo "=== Telegram Bot One-Shot Installer ==="

# --- Eingaben ---
read -rp "Domain (z.B. bot.deinedomain.tld): " DOMAIN
read -rp "Admin E-Mail für Let's Encrypt: " EMAIL
read -rp "Telegram BOT_TOKEN: " BOT_TOKEN
read -rp "Webhook Pfad (z.B. /tg-hook): " WEBHOOK_PATH
read -rp "Webhook SECRET_TOKEN (A-Z,a-z,0-9,_,-): " SECRET_TOKEN

echo "Provider wählen:
1) OpenRouter (empfohlen)
2) OpenAI
"
read -rp "Auswahl (1/2): " PROVIDER_CHOICE

if [[ "$PROVIDER_CHOICE" == "1" ]]; then
  PROVIDER="openrouter"
  read -rp "OpenRouter API Key (sk-or-...): " API_KEY
  MODEL_DEFAULT="openrouter/auto"
  read -rp "Model (Enter für ${MODEL_DEFAULT}): " MODEL
  MODEL="${MODEL:-$MODEL_DEFAULT}"
  API_ENDPOINT="https://openrouter.ai/api/v1/chat/completions"
elif [[ "$PROVIDER_CHOICE" == "2" ]]; then
  PROVIDER="openai"
  read -rp "OpenAI API Key (sk-...): " API_KEY
  MODEL_DEFAULT="gpt-4o-mini"
  read -rp "Model (Enter für ${MODEL_DEFAULT}): " MODEL
  MODEL="${MODEL:-$MODEL_DEFAULT}"
  API_ENDPOINT="https://api.openai.com/v1/chat/completions"
else
  echo "Ungültige Auswahl"; exit 1
fi

# --- System vorbereiten ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw jq

# Docker installieren (falls nicht vorhanden)
if ! command -v docker >/dev/null 2>&1; then
  echo "Installiere Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# certbot installieren
if ! command -v certbot >/dev/null 2>&1; then
  apt-get install -y certbot python3-certbot-nginx
fi

# Firewall (ufw)
ufw allow OpenSSH || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
yes | ufw enable || true

# --- Projekt anlegen ---
PROJECT_DIR="/opt/telegram_chatbot"
mkdir -p "${PROJECT_DIR}"
cd "${PROJECT_DIR}"

mkdir -p bot/app nginx

# .env schreiben
cat > .env <<EOF
DOMAIN=${DOMAIN}
HOST_PORT=443

BOT_TOKEN=${BOT_TOKEN}
WEBHOOK_PATH=${WEBHOOK_PATH}
WEBHOOK_SECRET_TOKEN=${SECRET_TOKEN}

PROVIDER=${PROVIDER}
API_KEY=${API_KEY}
API_ENDPOINT=${API_ENDPOINT}
MODEL=${MODEL}

LOG_LEVEL=info
EOF

# requirements
cat > bot/requirements.txt <<'EOF'
fastapi
uvicorn[standard]
httpx
pydantic
gunicorn
EOF

# Dockerfile
cat > bot/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
EOF

# FastAPI App
cat > bot/app/main.py <<'EOF'
import os, httpx, json
from fastapi import FastAPI, Request, Header, HTTPException
from pydantic import BaseModel

app = FastAPI()

BOT_TOKEN = os.getenv("BOT_TOKEN")
WEBHOOK_SECRET_TOKEN = os.getenv("WEBHOOK_SECRET_TOKEN")
PROVIDER = os.getenv("PROVIDER", "openrouter")
API_KEY = os.getenv("API_KEY")
API_ENDPOINT = os.getenv("API_ENDPOINT")
MODEL = os.getenv("MODEL", "openrouter/auto")

class Update(BaseModel):
    update_id: int

async def send_message(chat_id: int, text: str):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {"chat_id": chat_id, "text": text}
    async with httpx.AsyncClient(timeout=20.0) as client:
        r = await client.post(url, json=payload)
        r.raise_for_status()

async def call_llm(prompt: str) -> str:
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"}
    body = {
        "model": MODEL,
        "messages": [
            {"role":"system","content":"Du bist ein freundlicher, präziser Assistent. Antworte knapp und hilfreich."},
            {"role":"user","content": prompt}
        ]
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.post(API_ENDPOINT, headers=headers, json=body)
        r.raise_for_status()
        data = r.json()
        # OpenAI-kompatibles Schema (OpenRouter normalisiert ebenfalls)
        # choices[0].message.content
        try:
            return data["choices"][0]["message"]["content"]
        except Exception:
            return json.dumps(data)[:1000]

@app.get("/health")
async def health():
    return {"ok": True}

@app.post("/tg{path:path}")
async def tg_webhook(request: Request, x_telegram_bot_api_secret_token: str | None = Header(None)):
    # Secret prüfen
    if WEBHOOK_SECRET_TOKEN:
        if x_telegram_bot_api_secret_token != WEBHOOK_SECRET_TOKEN:
            raise HTTPException(status_code=403, detail="forbidden: bad secret token")
    body = await request.json()
    message = body.get("message") or body.get("edited_message")
    if not message:
        return {"ok": True, "reason": "no message"}
    chat_id = message.get("chat", {}).get("id")
    text = message.get("text", "") or ""
    if text.strip().startswith("/start"):
        await send_message(chat_id, "Hi! Ich bin bereit. Schreib mir einfach eine Nachricht.")
        return {"ok": True}

    prompt = f"Nutzer: {text}\nAntworte kurz und hilfreich in deutscher Sprache."
    try:
        reply = await call_llm(prompt)
    except Exception as e:
        await send_message(chat_id, f"LLM-Fehler: {e}")
        return {"ok": False}
    await send_message(chat_id, reply)
    return {"ok": True}
EOF

# nginx config
cat > nginx/nginx.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    client_max_body_size 10M;

    location / {
        proxy_pass http://bot:8000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Telegram Webhook – wichtig: Header weiterreichen
    location ${WEBHOOK_PATH} {
        proxy_pass http://bot:8000${WEBHOOK_PATH};
        proxy_set_header X-Telegram-Bot-Api-Secret-Token \$http_x_telegram_bot_api_secret_token;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF

# docker-compose
cat > docker-compose.yml <<'EOF'
version: "3.8"
services:
  bot:
    build: ./bot
    env_file: .env
    restart: unless-stopped
    networks: [web]
    depends_on: [nginx]
  nginx:
    image: nginx:stable
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    ports:
      - "80:80"
      - "443:443"
    restart: unless-stopped
    networks: [web]
networks:
  web:
    driver: bridge
EOF

# Zertifikat besorgen
mkdir -p /var/www/certbot
systemctl stop nginx || true
certbot certonly --webroot -w /var/www/certbot -d "${DOMAIN}" --email "${EMAIL}" --agree-tos --non-interactive
echo "TLS Zertifikate erstellt."

# Container bauen & starten
docker compose build
docker compose up -d

# Webhook setzen
WEBHOOK_URL="https://${DOMAIN}${WEBHOOK_PATH}"
echo "Setze Telegram Webhook auf ${WEBHOOK_URL} ..."
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook" \
  -d "url=${WEBHOOK_URL}" \
  -d "secret_token=${SECRET_TOKEN}" \
  -d "max_connections=40" \
  -d "drop_pending_updates=true" | jq

echo "=== Fertig! ===
Healthcheck:   curl -s https://${DOMAIN}/health
Logs:          docker compose logs -f bot
Webhook-Test:  curl -v -X POST '${WEBHOOK_URL}' \
  -H 'Content-Type: application/json' \
  -H 'X-Telegram-Bot-Api-Secret-Token: ${SECRET_TOKEN}' \
  -d '{\"update_id\":1,\"message\":{\"chat\":{\"id\":123456789},\"text\":\"Hallo\"}}'
"
