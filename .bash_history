            { "name": "text", "value": "❌ MommyRamona Healthcheck fehlgeschlagen (Status != 200)" }
          ]
        }
      },
      "name": "Send Telegram",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4,
      "position": [200, 300]
    }
  ],
  "connections": { "Cron": { "main": [[{ "node": "Check MommyRamona", "type": "main", "index": 0 }]] } },
  "active": false
}
EOF

# 2️⃣ Workflows importieren und aktivieren
sudo docker exec -i n8n n8n import:workflow --input=/home/node/.n8n/health_spicymila.json --activate=true
sudo docker exec -i n8n n8n import:workflow --input=/home/node/.n8n/health_mommyramona.json --activate=true
# 1️⃣ Dateien vom Host in das n8n-Datenverzeichnis kopieren
sudo docker cp /opt/Tausendunde1nz/n8n/workflows/health_spicymila.json n8n:/home/node/.n8n/
sudo docker cp /opt/Tausendunde1nz/n8n/workflows/health_mommyramona.json n8n:/home/node/.n8n/
# 2️⃣ Workflows importieren und aktivieren
sudo docker exec -i n8n n8n import:workflow --input=/home/node/.n8n/health_spicymila.json --activate=true
sudo docker exec -i n8n n8n import:workflow --input=/home/node/.n8n/health_mommyramona.json --activate=true
sudo docker exec -i n8n n8n list:workflow
sudo docker exec -i n8n n8n list:executions --limit=10 --status=success
sudo docker exec -i n8n sh -c "sqlite3 /home/node/.n8n/database.sqlite 'SELECT id,workflowId,finished,startedAt,stoppedAt FROM execution_entity ORDER BY id DESC LIMIT 10;'"
sudo apt install sqlite3 -y && sudo sqlite3 /opt/Tausendunde1nz/n8n/.n8n/database.sqlite 'SELECT id,workflowId,finished,startedAt,stoppedAt FROM execution_entity ORDER BY id DESC LIMIT 10;'
sudo chmod 644 /opt/Tausendunde1nz/n8n/.n8n/database.sqlite
sudo sqlite3 /opt/Tausendunde1nz/n8n/.n8n/database.sqlite 'SELECT id,workflowId,finished,startedAt,stoppedAt FROM execution_entity ORDER BY id DESC LIMIT 10;'
sudo find /opt/Tausendunde1nz/n8n -type f -name "database.sqlite"
sudo docker exec -it n8n sh -c "apk add --no-cache sqlite && sqlite3 /home/node/.n8n/database.sqlite 'SELECT id,workflowId,finished,startedAt,stoppedAt FROM execution_entity ORDER BY id DESC LIMIT 10;'"
sudo docker exec -u node -it n8n sh -c "sqlite3 /home/node/.n8n/database.sqlite 'SELECT id,workflowId,finished,startedAt,stoppedAt FROM execution_entity ORDER BY id DESC LIMIT 10;'"
sudo docker cp n8n:/home/node/.n8n/database.sqlite /opt/Tausendunde1nz/n8n/database.sqlite
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite 'SELECT id,workflowId,finished,startedAt,stoppedAt FROM execution_entity ORDER BY id DESC LIMIT 10;'
sudo docker exec -i n8n sh -c "sqlite3 /home/node/.n8n/database.sqlite \"UPDATE node_entity SET parameters = REPLACE(parameters, '\"value\": 30', '\"value\": 60') WHERE name = 'Cron';\""
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite "UPDATE node_entity SET parameters = REPLACE(parameters, '\"value\": 30', '\"value\": 60') WHERE name = 'Cron';"
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite ".tables"
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite "SELECT id, name, parameters FROM node_entity WHERE name = 'Cron';"
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite "SELECT id, name, nodes FROM workflow_entity WHERE nodes LIKE '%Cron%';"
sudo cp /opt/Tausendunde1nz/n8n/database.sqlite /opt/Tausendunde1nz/n8n/database_backup_before_cronchange.sqlite
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite "UPDATE workflow_entity SET nodes = REPLACE(nodes, '\"unit\":\"minutes\",\"value\":30', '\"unit\":\"minutes\",\"value\":60');"
sudo docker cp /opt/Tausendunde1nz/n8n/database.sqlite n8n:/home/node/.n8n/database.sqlite
sudo docker restart n8n
sudo sqlite3 /opt/Tausendunde1nz/n8n/database.sqlite "SELECT id, name, substr(nodes, instr(nodes, '\"unit\":\"minutes\"')-40, 120) FROM workflow_entity WHERE nodes LIKE '%Cron%';"
# 1) Verzeichnis & Basisdatei anlegen (falls nicht vorhanden)
sudo mkdir -p /opt/Tausendunde1nz/_Doku
sudo touch /opt/Tausendunde1nz/_Doku/System_Dokumentation.md
# 2) Heutigen Abschnitt anhängen (wie besprochen)
sudo tee -a /opt/Tausendunde1nz/_Doku/System_Dokumentation.md >/dev/null <<'MD'

## 🔧 Änderung: Cron-Intervalle auf stündlich gesetzt
**Datum:** 2025-10-10  
**Betroffene Workflows:** Bot Health Monitor, TrendWatch Health, SpicyMila Healthcheck, MommyRamona Healthcheck  
**Änderung:** Cron-Trigger von 30 → **60 Minuten** vereinheitlicht.  
**Nachweis (SQL-Auszug):** `"unit":"minutes","value":60` in allen Cron-Knoten.  
**Status:** erfolgreich, produktiv aktiv.
MD

# 3) Tools installieren (leichtgewichtig): HTML-Renderer + Markdown-Parser
#    (wir rendern MD -> HTML mit python3-markdown und daraus PDF mit wkhtmltopdf)
sudo apt-get update -y
sudo apt-get install -y wkhtmltopdf python3-markdown
# 4) Build-Script anlegen
sudo tee /usr/local/bin/build_system_doc.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DOC_DIR="/opt/Tausendunde1nz/_Doku"
MD="$DOC_DIR/System_Dokumentation.md"
HTML="$DOC_DIR/System_Dokumentation.html"
STAMP=$(date +'%Y-%m-%d_%H%M')
PDF="$DOC_DIR/System_Dokumentation_${STAMP}.pdf"
LATEST="$DOC_DIR/System_Dokumentation_latest.pdf"

# Markdown -> HTML
python3 - "$MD" "$HTML" <<'PY'
import sys, markdown, pathlib
md_path, html_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = md_path.read_text(encoding="utf-8")
html = markdown.markdown(text, extensions=["extra","toc","tables","sane_lists"])
html_full = f"""<!doctype html><html><head>
<meta charset="utf-8"><title>System_Dokumentation</title>
<style>
 body {{ font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif; margin: 24px; }}
 h1,h2,h3 {{ margin-top: 1.2em; }}
 code, pre {{ background:#f6f8fa; padding:2px 4px; }}
</style></head><body>{html}</body></html>"""
html_path.write_text(html_full, encoding="utf-8")
PY

# HTML -> PDF
wkhtmltopdf --quiet "$HTML" "$PDF"

# 'latest' Zeiger aktualisieren
cp -f "$PDF" "$LATEST"
echo "[OK] System-Dokumentation gebaut: $PDF"
EOF

sudo chmod +x /usr/local/bin/build_system_doc.sh
# 5) Einmalig jetzt bauen
sudo /usr/local/bin/build_system_doc.sh
# 6) Täglichen Job um 22:00 einrichten
echo "0 22 * * * root /usr/local/bin/build_system_doc.sh" | sudo tee /etc/cron.d/system_doc_build >/dev/null
# 1) Telegram-Konfiguration (ersetze DEIN_BOT_TOKEN und DEINE_CHAT_ID falls nötig)
BOT_TOKEN="DEIN_BOT_TOKEN"
CHAT_ID="DEINE_CHAT_ID"
# 2) Prüfsystem-Skript anlegen
sudo tee /usr/local/bin/check_system_doc.sh >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
DOC_DIR="/opt/Tausendunde1nz/_Doku"
LATEST="\$DOC_DIR/System_Dokumentation_latest.pdf"
LOG="/var/log/system_doc_check.log"
NOW=\$(date '+%Y-%m-%d %H:%M:%S')

# Existenz prüfen
if [ ! -f "\$LATEST" ]; then
  MSG="❌ System-Dokumentation fehlt! (\$NOW)"
elif test \$(find "\$LATEST" -mmin +90); then
  MSG="⚠️ System-Dokumentation wurde seit über 90 Minuten nicht aktualisiert (\$NOW)"
else
  MSG="✅ System-Dokumentation aktuell (\$NOW)"
fi

echo "\$MSG" | tee -a "\$LOG"
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"   -d chat_id="${CHAT_ID}" -d text="\$MSG" >/dev/null 2>&1
EOF

sudo chmod +x /usr/local/bin/check_system_doc.sh
# 3) Cron-Job alle 2 Stunden einrichten (damit’s nicht überlappt mit 22-Uhr-Job)
echo "0 */2 * * * root /usr/local/bin/check_system_doc.sh" | sudo tee /etc/cron.d/system_doc_check >/dev/null
# 4) Erste manuelle Prüfung starten
sudo /usr/local/bin/check_system_doc.sh
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep spicymila
docker logs --tail=50 spicymila_bot
docker logs spicymila_bot --tail=50
# Original-Startbefehl & Entrypoint des Containers anzeigen
docker inspect -f 'CMD={{.Config.Cmd}}  ENTRYPOINT={{.Config.Entrypoint}}  WORKDIR={{.Config.WorkingDir}}' spicymila_bot
docker exec -it spicymila_bot sh -lc 'ls -la /app; echo "--- grep Flask ---"; grep -R "Flask(" -n /app | head -n 10'
docker exec -it spicymila_bot sh -lc 'export FLASK_APP=main.py && flask run --host=0.0.0.0 --port=8090'
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose up -d
docker network connect tausendunde1nz_net n8n
docker exec -it n8n getent hosts spicymila_bot telegram_bot_mommyramona
docker network create tausendunde1nz_net || true
sudo nano /opt/n8n/docker-compose.yml
cd /opt/n8n && docker compose down && docker compose up -d && docker exec -it n8n getent hosts spicymila_bot telegram_bot_mommyramona
sudo tee /opt/n8n/docker-compose.yml >/dev/null <<'YAML'
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - N8N_HOST=n8n.mychatbuddy.dev
      - WEBHOOK_URL=https://n8n.mychatbuddy.dev/
      - N8N_PATH=/
      - N8N_DIAGNOSTICS_ENABLED=false
      - GENERIC_TIMEZONE=Europe/Berlin
    volumes:
      - /opt/n8n/data:/home/node/.n8n
      - /var/log:/var/log:ro
    networks:
      - tausendunde1nz_net
      - n8n_default

networks:
  tausendunde1nz_net:
    external: true
  n8n_default:
    external: false
YAML

cd /opt/n8n && docker compose down && docker compose up -d
docker exec -it n8n getent hosts spicymila_bot telegram_bot_mommyramona
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose up -d
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose up -d
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose up -d
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose config
docker compose up -d
curl -sS -i http://127.0.0.1:8090/health
sudo docker exec -it n8n n8n user-management:reset
sudo certbot certificates
sudo docker exec -it n8n n8n user-management:reset
sudo docker exec -it n8n n8n user-management:reset   --email admin@n8n.mychatbuddy.dev   --password 'N8n@2025!'
sudo docker exec -it n8n n8n user-management:reset --email admin@n8n.mychatbuddy.dev --password 'N8n@2025!' --force
sudo docker exec -it n8n n8n user-management:reset   --email admin@n8n.mychatbuddy.dev   --password 'N8n@2025!'
sudo docker stop n8n
sudo docker exec -it n8n n8n user-management:reset --instanceOwnerEmail "admin@n8n.mychatbuddy.dev" --password "N8n@2025!"
sudo docker start n8n
sudo docker ps | grep n8n
sudo docker exec -it n8n n8n user-management:reset --instanceOwnerEmail "admin@n8n.mychatbuddy.dev" --password "N8n@2025!"
sudo ls /opt/api_mychatbuddy_dev/routes/
ls /opt
sudo find /opt -type f -name "*status*.py" -o -name "*status*.js"
curl -sS -D- https://api.mychatbuddy.dev/status/mommyramona_bot
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
sudo docker logs api-mychatbuddy --tail 50 | grep "/status"
sudo docker exec -it api-mychatbuddy curl -s http://localhost:8080/routes
sudo ls /opt/api_mychatbuddy_dev
sudo docker inspect api-mychatbuddy | grep /opt
sudo docker exec -it api-mychatbuddy ls /
sudo docker exec -it api-mychatbuddy ls /app
sudo docker exec -it api-mychatbuddy cat /app/__main__.py
sudo docker exec -it api-mychatbuddy cat /app/main.py
sudo docker exec -it api-mychatbuddy curl -i http://localhost:8080/health
sudo docker exec -it api-mychatbuddy curl -i http://localhost:8000/health
sudo cat /etc/nginx/conf.d/api.mychatbuddy.dev.conf
sudo ls -1 /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null
sudo nano /etc/nginx/sites-enabled/api.mychatbuddy.dev
sudo docker ps --format "table {{.Names}}\t{{.Ports}}"
sudo nano /etc/nginx/sites-enabled/api.mychatbuddy.dev
sudo systemctl reload nginx
curl -i https://api.mychatbuddy.dev/spicy/health
sudo docker exec -it spicymila_bot netstat -tlnp | grep python
sudo docker logs spicymila_bot --tail 300 | grep -i "running on\|uvicorn\|http"
sudo nano /etc/nginx/sites-enabled/api.mychatbuddy.dev
sudo systemctl reload nginx
curl -i https://api.mychatbuddy.dev/spicy/health
curl -i http://127.0.0.1:8090/health
sudo nano /etc/nginx/sites-enabled/api.mychatbuddy.dev
sudo systemctl reload nginx
curl -i https://api.mychatbuddy.dev/spicy/health
sudo visudo
# Hauptordner für das Projekt anlegen
sudo mkdir -p /project_tausendunde1nz/{docs,backups,logs,automation}
# Bestehende System-Backups verlinken
sudo ln -s /root/bot_backups /project_tausendunde1nz/backups/system_backups
# Cron-Jobs / tägliche Automationen
sudo ln -s /etc/cron.daily /project_tausendunde1nz/automation/cron
# n8n-Verzeichnis vorbereiten (für spätere Flows)
sudo mkdir -p /project_tausendunde1nz/automation/n8n
# Scripts-Ordner für Bash/Python Hilfsprogramme
sudo mkdir -p /project_tausendunde1nz/automation/scripts
# Bots zentral referenzieren
sudo ln -s /opt /project_tausendunde1nz/automation/bots
sudo mkdir -p /project_tausendunde1nz/docs
# Erste Platzhalter anlegen
sudo touch /project_tausendunde1nz/docs/System_Dokumentation_2025-10-12.pdf
sudo touch /project_tausendunde1nz/docs/Projekt_Wording_und_Struktur_TausendundE1NZ.pdf
sudo bash -c 'echo "- Offene Punkte:\n- Nächste Schritte:\n" > /project_tausendunde1nz/docs/Agent_Notizen.md'
sudo chown -R $USER:$USER /project_tausendunde1nz
sudo chmod -R 750 /project_tausendunde1nz
sudo nano /project_tausendunde1nz/automation/scripts/doc_sync.sh
sudo chmod +x /project_tausendunde1nz/automation/scripts/doc_sync.sh
/project_tausendunde1nz/automation/scripts/doc_sync.sh
sudo nano /project_tausendunde1nz/automation/scripts/doc_sync.sh
sudo nano /project_tausendunde1nz/automation/scripts/doc_sync.sh
/project_tausendunde1nz/automation/scripts/doc_sync.sh
/project_tausendunde1nz/automation/scripts/doc_sync.sh
# Log anzeigen (die letzten Zeilen)
tail -n 50 /project_tausendunde1nz/logs/doc_sync.log
# Testdatei mit Datumsmuster erstellen (wird vom find-Regex erkannt)
echo "Test" > /project_tausendunde1nz/docs/Testdatei_2025-10-12.md
# Script erneut starten
/project_tausendunde1nz/automation/scripts/doc_sync.sh
# Log wieder prüfen
tail -n 50 /project_tausendunde1nz/logs/doc_sync.log
# prüft lokalen Health-Endpunkt inkl. HTTP-Status
curl -sS -m 5 -i http://127.0.0.1:8090/health
# Liste laufender Container kompakt
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
# Netzwerke der wichtigsten Container prüfen (Namen aus obiger Liste einsetzen)
docker inspect -f '{{json .NetworkSettings.Networks}}' n8n | jq
docker inspect -f '{{json .NetworkSettings.Networks}}' spicymila | jq
docker inspect -f '{{json .NetworkSettings.Networks}}' telegram_bot_mommyramona | jq
# 1) Gemeinsames Projekt-Netz anlegen (einmalig)
docker network create tausendunde1nz_net
# 2) Container an dieses Netz anschließen (Namen aus `docker ps`)
docker network connect tausendunde1nz_net n8n
docker network connect tausendunde1nz_net spicymila_bot
docker network connect tausendunde1nz_net telegram_bot_mommyramona
# (optional) trendwatch_bot, api-mychatbuddy, etc. ebenso
docker exec -it n8n curl -sS -i http://spicymila_bot:8090/health
docker exec -it n8n curl -sS -i http://telegram_bot_mommyramona:8081/health
# zeigt, auf welchem Interface Port 8090 lauscht
docker exec -it spicymila_bot sh -c 'ss -ltnp 2>/dev/null || netstat -tulpen 2>/dev/null || echo "no ss/netstat"'
# 1) Container-Startbefehl anzeigen
docker inspect -f '{{.Path}} {{join .Args " "}}' spicymila_bot
# 2) Liegt ein Compose-Stack vor?
ls -la /opt/spicymila_bot | egrep 'docker-compose|compose\.yml|compose\.yaml' || echo "kein compose gefunden"
# 3) Zeig mir die ersten Logs (oft steht da der Starter)
docker logs --tail=50 spicymila_bot
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose up -d
# Host -> SpicyMila (sollte 200 OK liefern wie vorher)
curl -sS -i http://127.0.0.1:8090/health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep spicymila
docker exec -it n8n getent hosts spicymila_bot
docker network connect tausendunde1nz_net n8n
docker inspect -f '{{.Name}} -> {{range $k,$v := .NetworkSettings.Networks}}{{printf "%s " $k}}{{end}}' n8n spicymila_bot
docker network connect tausendunde1nz_net spicymila_bot
docker exec -it n8n getent hosts spicymila_bot
docker exec -it n8n getent hosts telegram_bot_mommyramona
docker logs --tail=20 telegram_bot_mommyramona
curl -sS -i http://127.0.0.1:8090/health
docker exec -it n8n getent hosts spicymila_bot
curl -sS -i http://172.25.0.4:8080/health
ls -lh /var/log/rclone_backup.log
sudo chmod 644 /var/log/rclone_backup.log
sudo chmod 644 /var/log/rclone_backup.log
docker exec -it n8n ls -lh /var/log/rclone_backup.log
sudo nano /opt/n8n/docker-compose.yml
cd /opt/n8n && docker compose down && docker compose up -d
docker exec -it n8n ls -lh /var/log/rclone_backup.log
docker inspect -f '{{.Name}} -> {{range $k,$v := .NetworkSettings.Networks}}{{printf "%s " $k}}{{end}}' n8n spicymila_bot telegram_bot_mommyramona
# A) Container-Status + Port-Bind
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep spicymila
# B) Health vom Host (muss 200 liefern)
curl -sS -i http://127.0.0.1:8090/health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep spicymila
docker logs --tail=15 spicymila_bot
curl -sS -i http://127.0.0.1:8080/health
sudo nano /opt/spicymila_bot/docker-compose.yml
cd /opt/spicymila_bot
docker compose up -d
curl -sS -i http://127.0.0.1:8090/health
git --version
ssh-keygen -t ed25519 -C "chatops@tausendunde1nz"
cat ~/.ssh/id_ed25519.pub
ls -l ~/.ssh
ssh -T git@github.com || true            # kurzer Test
ssh -vT git@github.com 2>&1 | sed -n '1,120p'  # zeigt, welcher Key angeboten wird (look for "Offering public key")
for d in /opt/spicymila_bot /opt/mommyramona_bot /opt/infra /opt/trendwatch_bot; do   [ -d "$d/.git" ] || continue;   echo "=== $d ===";   (cd "$d" && git remote -v && git ls-remote 2>&1 | head -n2); done
ssh-keyscan github.com | sudo tee -a /etc/ssh/ssh_known_hosts > /dev/null
ssh-keyscan github.com | sudo tee -a /etc/ssh/ssh_known_hosts > /dev/null
# 1) Key-Dateien & Rechte prüfen
ls -l ~/.ssh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
# 2) Fingerprint checken (sollte mit dem bei GitHub hinterlegten Key übereinstimmen)
ssh-keygen -lf ~/.ssh/id_ed25519.pub
echo "----- PUBLIC KEY BEGIN -----"
cat ~/.ssh/id_ed25519.pub
echo "----- PUBLIC KEY END -----"
# 3) SSH-Config für GitHub anlegen/ersetzen
cat > ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  AddKeysToAgent yes
EOF

chmod 600 ~/.ssh/config
# 4) Agent starten und Key laden
eval "$(ssh-agent -s)"
ssh-add -D >/dev/null 2>&1 || true
ssh-add ~/.ssh/id_ed25519
# 5) Test
ssh -T git@github.com
# 1) Ins Projekt wechseln
cd /opt/spicymila_bot
# 2) Git-Repo initialisieren (Hauptbranch = main)
git init -b main
# 3) Commit-Identität setzen (repo-spezifisch)
git config user.name "chatops@tausendunde1nz"
git config user.email "chatops@tausendunde1nz"
# 4) sinnvolles .gitignore anlegen (nur ergänzen, falls nicht vorhanden)
cat >> .gitignore <<'EOF'
# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.venv/
.env

# Editor/OS
.vscode/
.idea/
.DS_Store

# Daten/Artefakte
*.sqlite
*.db
*.log
EOF

# 5) erste Version committen
git add .
git commit -m "Initial import of spicymila_bot from server"
# 6) Remote setzen (Repo existiert laut Screenshot bereits in der Org)
git remote add origin git@github.com:Tausendunde1nz/spicymila_bot.git
# 7) Push
git push -u origin main
cd /opt/spicymila_bot
git fetch origin main
git reset --soft origin/main || true
git push --force-with-lease origin main
# 1) SSH-Konfig für den Trend-Key anlegen/ergänzen
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat <<'EOF' >> ~/.ssh/config

Host github.com-trend
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_trend
  IdentitiesOnly yes
EOF

chmod 600 ~/.ssh/config
# 2) GitHub in known_hosts (falls noch nicht drin)
ssh-keyscan -H github.com | sudo tee -a /etc/ssh/ssh_known_hosts > /dev/null || true
# 3) SSH-Agent starten und NUR den Trend-Key laden
eval "$(ssh-agent -s)"
ssh-add -D >/dev/null 2>&1 || true
ssh-add ~/.ssh/id_ed25519_trend
# 4) Verbindung TESTEN mit dem Alias (wichtig!)
ssh -T github.com-trend || true
# Erwartet: "Hi <org/repo> ... successfully authenticated, but GitHub does not provide shell access."
# 5) Im Repo die Remote auf den Alias umstellen und pushen
cd /opt/trendwatch_bot
git remote remove origin 2>/dev/null || true
git remote add origin github.com-trend:Tausendunde1nz/trendwatch_bot.git
# Falls der Branch noch nicht existiert:
git symbolic-ref HEAD refs/heads/main 2>/dev/null || true
git add -A
git commit -m "Initial import from server" 2>/dev/null || true
# 6) Push
git push --set-upstream origin main
# 1) Ins Repo wechseln
cd /opt/trendwatch_bot
# 2) Remote auf den SSH-Alias setzen (achtet auf github.com-trend)
git remote remove origin 2>/dev/null || true
git remote add origin github.com-trend:Tausendunde1nz/trendwatch_bot.git
git remote -v
# 3) Sicherstellen, dass der Branch 'main' heißt, commit anlegen falls noch keiner da ist
git symbolic-ref HEAD refs/heads/main 2>/dev/null || true
git add -A
git commit -m "Initial import from server" || true
# 4) Pushen
git push --set-upstream origin main
# 2) Remote prüfen
git remote -v
# 3) Falls dort noch github.com steht -> auf den Alias umstellen
git remote set-url origin git@github.com-trend:Tausendunde1nz/trendwatch_bot.git
# 4) Nur den Trend-Key im Agenten laden
eval "$(ssh-agent -s)"
ssh-add -D >/dev/null 2>&1 || true
ssh-add ~/.ssh/id_ed25519_trend
# 5) Verbindung mit dem Alias testen (erwartet: "successfully authenticated, but GitHub does not provide shell access.")
ssh -T git@github.com-trend || true
# 6) Branch setzen & pushen
git branch -M mainserver
git push --set-upstream origin mainserver
cat ~/.ssh/id_ed25519_trend.pub
Host github.com-trend
  HostName github.com
  User git
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519_trend
Host github.com-trend
  HostName github.com
  User git
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519_trend
# 2) Remote prüfen
git remote -v
# 3) Falls dort noch github.com steht -> auf den Alias umstellen
git remote set-url origin git@github.com-trend:Tausendunde1nz/trendwatch_bot.git
# 4) Nur den Trend-Key im Agenten laden
eval "$(ssh-agent -s)"
ssh-add -D >/dev/null 2>&1 || true
ssh-add ~/.ssh/id_ed25519_trend
# 5) Verbindung mit dem Alias testen (erwartet: "successfully authenticated, but GitHub does not provide shell access.")
ssh -T git@github.com-trend || true
# 6) Branch setzen & pushen
git branch -M mainserver
git push --set-upstream origin mainserver
# im Repo /opt/trendwatch_bot
git branch -M main
git push -u origin main        # legt remote 'main' an und tracked ihn
# Danach in GitHub den Default Branch ggf. auf 'main' setzen
cd /opt/trendwatch_bot
git fetch origin main || true
git reset --soft origin/main || true
git push --force-with-lease origin main
git branch -a
git remote -v
git log --oneline -n 3
