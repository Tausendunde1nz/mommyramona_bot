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

import os
import time
import json
import sqlite3
from flask import Flask, request, jsonify
import requests
from langdetect import detect, LangDetectException

# ------------ Konfiguration aus .env ------------
TOKEN = os.getenv("BOT_TOKEN")
SECRET = os.getenv("SECRET")
MODEL = os.getenv("MODEL", "openai/gpt-4o-mini")
SYS_PROMPT = os.getenv(
    "CHARACTER_SYSTEM_PROMPT",
    (
        "Flirte, necke, sei locker und gerne ein wenig dominant, aber respektvoll. "
        "Keine expliziten sexuellen Handlungen oder detaillierten Körperbeschreibungen. "
        "Kein Content mit Minderjährigen/Familien-Rollen, kein Zwang, keine Gewalt, nichts Illegales. "
        "Antworte immer in der Sprache des Users. "
        "Sei kurz, lebendig, mit gelegentlichen Emojis; greife bekannte Nutzerfakten auf, wenn sie passen."
    )
)
MAX_HIST = int(os.getenv("MAX_HISTORY_MESSAGES", "14"))
DB_PATH = "/app/botdata.sqlite"

app = Flask(__name__)

# ------------ SQLite Helpers ------------
def db():
    conn = sqlite3.connect(DB_PATH)
    # Nutzer
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users(
            user_id TEXT PRIMARY KEY,
            username TEXT,
            is_adult INTEGER DEFAULT 0,
            lang TEXT,
            created_at INTEGER
        )
    """)
    # Kurzzeit-Verlauf (für Chatkontext)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS messages(
            user_id TEXT,
            role TEXT,
            content TEXT,
            ts INTEGER
        )
    """)
    # Langzeit-Fakten (dauerhaftes Gedächtnis pro User)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS user_facts(
            user_id TEXT,
            k TEXT,
            v TEXT,
            updated_at INTEGER,
            PRIMARY KEY(user_id, k)
        )
    """)
    return conn

def get_user(conn, user_id):
    cur = conn.execute(
        "SELECT user_id, username, is_adult, lang FROM users WHERE user_id=?",
        (user_id,)
    )
    r = cur.fetchone()
    if r:
        return {"user_id": r[0], "username": r[1], "is_adult": r[2], "lang": r[3]}
    return None

def upsert_user(conn, user_id, username=None, is_adult=None, lang=None):
    u = get_user(conn, user_id)
    if not u:
        conn.execute(
            "INSERT INTO users(user_id, username, is_adult, lang, created_at) VALUES (?,?,?,?,?)",
            (user_id, username or "", is_adult or 0, lang or "", int(time.time()))
        )
    else:
        if username is None: username = u["username"]
        if is_adult is None: is_adult = u["is_adult"]
        if lang is None: lang = u["lang"]
        conn.execute(
            "UPDATE users SET username=?, is_adult=?, lang=? WHERE user_id=?",
            (username, is_adult, lang, user_id)
        )
    conn.commit()

def add_msg(conn, user_id, role, content):
    conn.execute(
        "INSERT INTO messages(user_id, role, content, ts) VALUES (?,?,?,?)",
        (user_id, role, content, int(time.time()))
    )
    # nur die letzten MAX_HIST*2 Einträge halten
    conn.execute(
        """
        DELETE FROM messages
         WHERE user_id=? AND rowid NOT IN (
           SELECT rowid FROM messages WHERE user_id=?
            ORDER BY ts DESC LIMIT ?
         )
        """,
        (user_id, user_id, MAX_HIST * 2)
    )
    conn.commit()

def get_history(conn, user_id):
    cur = conn.execute(
        "SELECT role, content FROM messages WHERE user_id=? ORDER BY ts ASC",
        (user_id,)
    )
    rows = cur.fetchall()
    return [{"role": r, "content": c} for (r, c) in rows][-MAX_HIST:]

# ---- Langzeit-Fakten (KV) ----
def set_fact(conn, user_id, key, value):
    conn.execute("""
        INSERT INTO user_facts(user_id, k, v, updated_at)
        VALUES (?,?,?,?)
        ON CONFLICT(user_id, k) DO UPDATE SET v=excluded.v, updated_at=excluded.updated_at
    """, (user_id, key, value, int(time.time())))
    conn.commit()

def del_fact(conn, user_id, key):
    conn.execute("DELETE FROM user_facts WHERE user_id=? AND k=?", (user_id, key))
    conn.commit()

def clear_facts(conn, user_id):
    conn.execute("DELETE FROM user_facts WHERE user_id=?", (user_id,))
    conn.commit()

def list_facts(conn, user_id):
    cur = conn.execute("SELECT k, v FROM user_facts WHERE user_id=? ORDER BY k ASC", (user_id,))
    return cur.fetchall()

def facts_as_bullets(conn, user_id):
    rows = list_facts(conn, user_id)
    if not rows:
        return "• (keine gespeicherten Fakten)"
    return "\n".join([f"• {k}: {v}" for (k, v) in rows])

# ---- frei-form Erinnerungen parsen ----
def parse_remember_payload(payload: str):
    """
    Akzeptiert:
      - 'key: value'  oder  'key=value'
      - beliebigen Text -> wird als 'note_<timestamp>' gespeichert
    Gibt (key, value) zurück.
    """
    text = payload.strip()
    if ":" in text:
        k, v = text.split(":", 1)
        k, v = k.strip().lower(), v.strip()
        if k and v:
            return k, v
    if "=" in text:
        k, v = text.split("=", 1)
        k, v = k.strip().lower(), v.strip()
        if k and v:
            return k, v
    # Fallback: freie Notiz
    key = f"note_{int(time.time())}"
    return key, text

# ------------ Sprache & Regeln ------------
def detect_lang(text, fallback="de"):
    try:
        code = detect(text)
        return code or fallback
    except LangDetectException:
        return fallback

def system_prompt_with_rules(lang_code="de", facts_text=""):
    rules = (
        "Sicherheitsregeln:\n"
        "- Keine expliziten sexuellen Handlungen oder detaillierten Körperbeschreibungen.\n"
        "- Keine Minderjährigen/Teen-/Familien-Rollen, kein Inzest.\n"
        "- Kein Zwang, keine Gewalt, nichts Illegales.\n"
        "- Flirte soft/suggestiv (PG-13), humorvoll, respektvoll, kurz & lebendig.\n"
        "- Bei verbotenen Anfragen: freundlich ablehnen und harmlos umlenken.\n"
        "\n"
        "Wenn es bekannte Fakten über den Nutzer gibt, berücksichtige sie behutsam:\n"
        f"{facts_text}\n"
    )
    if lang_code.startswith("de"):
        prolog = SYS_PROMPT
    else:
        prolog = "You respond in the user's language. " + SYS_PROMPT
    return f"{prolog}\n\n{rules}"

FORBIDDEN_KEYWORDS = [
    "minderjähr", "teen", "schule", "stiefvater", "stiefmutter", "inzest",
    "non-consensual", "gewalt", "vergewalt", "rape"
]

def violates_simple_guardrails(text):
    t = text.lower()
    return any(k in t for k in FORBIDDEN_KEYWORDS)

# ------------ OpenRouter Call ------------
def call_openrouter(messages):
    url = "https://openrouter.ai/api/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {os.getenv('OPENROUTER_API_KEY','')}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://api.mychatbuddy.dev",
    }
    payload = {
        "model": MODEL,
        "messages": messages,
        "temperature": 0.8,
        "max_tokens": 400
    }
    r = requests.post(url, headers=headers, data=json.dumps(payload), timeout=40)
    r.raise_for_status()
    data = r.json()
    return data["choices"][0]["message"]["content"].strip()

# ------------ Telegram Helper ------------
def tg_send(chat_id, text):
    requests.post(
        f"https://api.telegram.org/bot{TOKEN}/sendMessage",
        json={"chat_id": chat_id, "text": text}
    )

# ------------ Healthcheck ------------
@app.route("/health", methods=["GET"])
def health():
    return "ok", 200

# ------------ Webhook ------------
@app.route("/tg/webhook", methods=["POST"])
def webhook():
    # Secret prüfen
    if request.headers.get("X-Telegram-Bot-Api-Secret-Token") != SECRET:
        return "Bad Secret", 403

    data = request.json or {}
    if "message" not in data:
        return "ok", 200

    msg = data["message"]
    chat_id = msg["chat"]["id"]
    user_id = str(msg["from"]["id"])
    username = msg["from"].get("username", "")
    text = msg.get("text", "") or ""
    t = text.strip().lower()

    conn = db()
    if not get_user(conn, user_id):
        upsert_user(conn, user_id, username=username, is_adult=0, lang="")

    # ---- Admin-/Memory-Kommandos ----
    if t == "/reset":
        conn.execute("DELETE FROM messages WHERE user_id=?", (user_id,))
        conn.commit()
        tg_send(chat_id, "Dein Verlauf ist zurückgesetzt.")
        return "ok", 200

    if t == "/help":
        tg_send(chat_id, "Befehle:\n"
                         "/reset – Verlauf löschen\n"
                         "/lang xx – Sprache setzen (z. B. /lang en)\n"
                         "/about – Info & Regeln\n"
                         "/remember ... – Fakt speichern (z. B. /remember name: Daniel oder /remember Ich mag Pizza)\n"
                         "/facts – alle gespeicherten Fakten anzeigen\n"
                         "/forget key – Fakt löschen (z. B. /forget name)\n"
                         "/forget all – alle Fakten löschen")
        return "ok", 200

    if t == "/about":
                         "Keine expliziten Details, keine Minderjährigen-/Familien-Rollen, kein Zwang.\n"
                         "Ich antworte in deiner Sprache und merke mir deine Vorlieben 😊")
        return "ok", 200

    if t.startswith("/lang "):
        lang_code = t.split(" ", 1)[1].strip().lower()
        upsert_user(conn, user_id, lang=lang_code)
        tg_send(chat_id, f"Okay – ich antworte jetzt bevorzugt in: {lang_code}")
        return "ok", 200

    if t.startswith("/remember"):
        payload = text[len("/remember"):].strip()
        if not payload:
            tg_send(chat_id, "Nutze: /remember key: value  oder  /remember dein freier Text")
            return "ok", 200
        key, value = parse_remember_payload(payload)
        set_fact(conn, user_id, key, value)
        tg_send(chat_id, f"Merke mir: {key} = {value}")
        return "ok", 200

    if t == "/facts":
        tg_send(chat_id, "Deine gespeicherten Fakten:\n" + facts_as_bullets(conn, user_id))
        return "ok", 200

    if t.startswith("/forget "):
        arg = t.split(" ", 1)[1].strip().lower()
        if arg == "all":
            clear_facts(conn, user_id)
            tg_send(chat_id, "Alles vergessen. 🔄")
        elif arg:
            del_fact(conn, user_id, arg)
            tg_send(chat_id, f"Vergessen: {arg}")
        else:
            tg_send(chat_id, "Format: /forget key  oder  /forget all")
        return "ok", 200
    # -----------------------------------

    user = get_user(conn, user_id)

    # 18+ Gate
    if user["is_adult"] == 0:
        if t in ("ja", "yes", "y", "ich bin 18", "bin 18", "/adult_yes"):
            upsert_user(conn, user_id, is_adult=1)
            tg_send(chat_id, "Danke für die Bestätigung 🖤 Lass uns locker & respektvoll schreiben.")
            return "ok", 200
        tg_send(chat_id, "Kurze Frage vorab: Bist du 18+? Antworte mit **ja** (oder /adult_yes).")
        return "ok", 200

    # einfache Guardrails
    if violates_simple_guardrails(text):
        tg_send(chat_id, "Das ist außerhalb meiner Grenzen. Lass uns bei harmloser, flirtiger Stimmung bleiben 😉")
        return "ok", 200

    # Sprache erkennen/merken
    lang_code = user["lang"] or detect_lang(text, fallback="de")
    if lang_code != user.get("lang"):
        upsert_user(conn, user_id, lang=lang_code)

    # Verlauf aktualisieren
    add_msg(conn, user_id, "user", text)
    history = get_history(conn, user_id)

    # Fakten für Prompt einbetten (Langzeit-Gedächtnis)
    facts_text = facts_as_bullets(conn, user_id)

    # Prompt bauen
    messages = [{"role": "system", "content": system_prompt_with_rules(lang_code, facts_text)}]
    messages.extend(history)

    # KI-Aufruf
    try:
        reply = call_openrouter(messages)
    except Exception:
        reply = "Kleiner Hänger bei mir 🤖 – versuch’s gleich nochmal."

    add_msg(conn, user_id, "assistant", reply)
    tg_send(chat_id, reply)
    return jsonify(ok=True), 200

# ------------ Local run ------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
