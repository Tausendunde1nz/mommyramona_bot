from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel
from typing import Optional, Deque, Dict, Any
from datetime import datetime, timezone
from collections import deque
import os
import httpx

app = FastAPI(title="mychatbuddy API")

# ========= Konfiguration aus ENV =========
def env(name: str, default: Optional[str] = None) -> Optional[str]:
    v = os.getenv(name, default)
    if v is not None:
        v = v.strip()
    return v

OPENROUTER_API_KEY = env("OPENROUTER_API_KEY")
LLM_MODEL          = env("LLM_MODEL", "openai/gpt-4o-mini")
LLM_TEMPERATURE    = float(env("LLM_TEMPERATURE", "0.7"))

# Persona (frei anpassen, inkl. FSK18 – beachte ggf. Anbieter/Plattform-Policies)
PROMPT_PERSONA = env("PROMPT_PERSONA", 
    "Du bist ein freundlicher, flirty Chat-Assistent. "
    "Antworte natürlich und in der Sprache des Nutzers. "
    "Halte dich an die Wünsche des Nutzers. "
)

# Verlaufseinstellungen
MAX_TURNS = int(env("MAX_TURNS", "6"))  # Anzahl abwechselnder User/Assistant-Beiträge

TELEGRAM_BOT_TOKEN      = env("TELEGRAM_BOT_TOKEN")
TELEGRAM_WEBHOOK_SECRET = env("TELEGRAM_WEBHOOK_SECRET")

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

# ========= Modelle =========
class ChatIn(BaseModel):
    message: str
    chat_id: Optional[str] = None  # optional: eigener Chat-ID-Bezug für /chat

class ChatOut(BaseModel):
    reply: str
    ts: str

# ========= Helpers =========
def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

# Einfaches In-Memory-Gedächtnis {chat_id: deque[dict(role, content)]}
HISTORY: Dict[str, Deque[Dict[str, Any]]] = {}

def history_for(chat_id: str) -> Deque[Dict[str, str]]:
    if chat_id not in HISTORY:
        HISTORY[chat_id] = deque(maxlen=MAX_TURNS * 2)  # user+assistant Paare
    return HISTORY[chat_id]

def build_messages(chat_id: Optional[str], user_text: str):
    msgs = [{"role": "system", "content": PROMPT_PERSONA}]
    if chat_id:
        msgs.extend(list(history_for(chat_id)))
    msgs.append({"role": "user", "content": user_text})
    return msgs

async def call_llm(user_text: str, chat_id: Optional[str]) -> str:
    if not OPENROUTER_API_KEY:
        # Fallback ohne Key
        return f"Du sagtest: {user_text}"

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "HTTP-Referer": "https://mychatbuddy.dev",
        "X-Title": "mychatbuddy",
    }
    payload = {
        "model": LLM_MODEL,
        "temperature": LLM_TEMPERATURE,
        "messages": build_messages(chat_id, user_text),
    }

    timeout = httpx.Timeout(30.0, connect=10.0, read=20.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        r = await client.post(OPENROUTER_URL, headers=headers, json=payload)
        r.raise_for_status()
        data = r.json()
        reply = data["choices"][0]["message"]["content"].strip()

    # Verlauf aktualisieren, wenn Chat-Kontext vorhanden
    if chat_id:
        h = history_for(chat_id)
        h.append({"role": "user", "content": user_text})
        h.append({"role": "assistant", "content": reply})

    return reply

async def send_telegram_message(chat_id: int, text: str) -> None:
    if not TELEGRAM_BOT_TOKEN:
        return
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {"chat_id": chat_id, "text": text}
    async with httpx.AsyncClient(timeout=20.0) as client:
        await client.post(url, json=payload)

# ========= Endpoints =========
@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "ts": now_iso()}

@app.post("/chat", response_model=ChatOut)
async def chat(body: ChatIn) -> ChatOut:
    reply_text = await call_llm(body.message, body.chat_id or "web")
    return ChatOut(reply=reply_text, ts=now_iso())

@app.post("/telegram/webhook")
async def telegram_webhook(
    request: Request,
    x_telegram_bot_api_secret_token: Optional[str] = Header(default=None),
):
    # Secret prüfen
    expected = TELEGRAM_WEBHOOK_SECRET or ""
    if not expected or x_telegram_bot_api_secret_token != expected:
        raise HTTPException(status_code=403, detail="bad secret")

    payload = await request.json()
    msg = payload.get("message") or {}
    chat  = msg.get("chat") or {}
    chat_id = chat.get("id")
    text = msg.get("text") or ""

    if not (chat_id and text):
        return {"ok": True}

    # chat_id als Kontextschlüssel benutzen
    ctx_id = f"tg:{chat_id}"

    try:
        reply = await call_llm(text, ctx_id)
    except Exception:
        reply = "Sorry, kurz überlastet – probier es gleich nochmal."

    try:
        await send_telegram_message(chat_id, reply)
    except Exception:
        pass

    return {"ok": True}
