#!/bin/bash
# ugly-forge uninstall.sh
# Deaktiviert die Softwareschmiede -- ugly-stack bleibt unveraendert

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$FORGE_DIR")/ugly-stack"

if [ ! -d "$STACK_DIR" ]; then
  STACK_DIR="$(dirname "$FORGE_DIR")/VPS_Bootstrap"
fi

STACK_ENV="$STACK_DIR/.env"

echo -e "${COLOR_YELLOW}ugly-forge Deinstallation...${COLOR_NC}"
echo ""

# ----------------------------------------------------------------
# 1. VOLUME MOUNT ENTFERNEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[1/4] Entferne Volume Mount...${COLOR_NC}"
sed -i "/ugly-forge\/workspace/d" "$STACK_DIR/docker-compose.yml"
sed -i "/ugly-forge\/db/d" "$STACK_DIR/docker-compose.yml"
echo -e "${COLOR_GREEN}OK Volume Mount entfernt${COLOR_NC}"

# ----------------------------------------------------------------
# 2. NGINX BLOCK ENTFERNEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[2/4] Entferne nginx dashboard Block...${COLOR_NC}"

NGINX_CONF="$STACK_DIR/nginx/conf.d/default.conf"

if grep -q "dashboard.beautymolt.com" "$NGINX_CONF" 2>/dev/null; then
  python3 - <<PYEOF
import re
with open("$NGINX_CONF", "r") as f:
    content = f.read()
cleaned = re.sub(
    r'\\n*server\\s*\\{[^}]*server_name[^}]*dashboard\\.beautymolt\\.com[^}]*\\}',
    '', content, flags=re.DOTALL
)
with open("$NGINX_CONF", "w") as f:
    f.write(cleaned.strip() + "\\n")
PYEOF
  echo -e "${COLOR_GREEN}OK nginx: dashboard.beautymolt.com Block entfernt${COLOR_NC}"
else
  echo -e "  v nginx: kein dashboard Block gefunden"
fi

# ----------------------------------------------------------------
# 3. CLOUDFLARE TUNNEL EINTRAG ENTFERNEN
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[3/4] Entferne Cloudflare Tunnel Eintrag...${COLOR_NC}"

if [ -f "$STACK_ENV" ]; then
  source "$STACK_ENV"
fi

if [ -n "$CF_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ] && [ -n "$CF_TUNNEL_ID" ]; then
  TUNNEL_CONFIG=$(curl -s \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
    -H "Authorization: Bearer ${CF_TOKEN}")

  if echo "$TUNNEL_CONFIG" | jq -e '.success' | grep -q true; then
    if ! echo "$TUNNEL_CONFIG" | jq -e '.result.config.ingress[] | select(.hostname == "dashboard.beautymolt.com")' > /dev/null 2>&1; then
      echo -e "  v Cloudflare Tunnel: dashboard.beautymolt.com nicht vorhanden"
    else
      NEW_INGRESS=$(echo "$TUNNEL_CONFIG" | jq '
        .result.config.ingress = (
          [.result.config.ingress[] | select(.hostname != "dashboard.beautymolt.com" and .hostname != null and (has("service") and .service != "http_status:404"))] +
          [{"service": "http_status:404"}]
        )
        | {config: {ingress: .result.config.ingress, "warp-routing": .result.config["warp-routing"]}}
      ')

      PUT_RESULT=$(curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$NEW_INGRESS")

      if echo "$PUT_RESULT" | jq -e '.success' | grep -q true; then
        echo -e "  ${COLOR_GREEN}OK Cloudflare Tunnel: dashboard.beautymolt.com entfernt${COLOR_NC}"
      else
        echo -e "  ${COLOR_YELLOW}! Cloudflare Tunnel Update fehlgeschlagen:${COLOR_NC}"
        echo "$PUT_RESULT" | jq -r '.errors[0].message // "unbekannt"'
      fi
    fi
  else
    echo -e "  ${COLOR_YELLOW}! Cloudflare Tunnel Config konnte nicht gelesen werden${COLOR_NC}"
  fi
else
  echo -e "  ${COLOR_YELLOW}! CF_TOKEN/CF_ACCOUNT_ID/CF_TUNNEL_ID fehlen -- Tunnel manuell bereinigen${COLOR_NC}"
fi

# ----------------------------------------------------------------
# 4. OPENCLAW + NGINX NEU STARTEN + ARCHIVIERUNG
# ----------------------------------------------------------------
echo -e "${COLOR_YELLOW}[4/4] Starte OpenClaw + nginx neu...${COLOR_NC}"
docker compose -f "$STACK_DIR/docker-compose.yml" restart openclaw nginx
echo -e "${COLOR_GREEN}OK OpenClaw + nginx neugestartet${COLOR_NC}"

echo ""
read -p "projects.db nach ~/ugly-forge-backup.db kopieren? (j/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Jj]$ ]]; then
  cp "$FORGE_DIR/db/projects.db" ~/ugly-forge-backup.db
  echo -e "${COLOR_GREEN}OK Backup gespeichert: ~/ugly-forge-backup.db${COLOR_NC}"
fi

echo ""
echo -e "${COLOR_GREEN}================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}ugly-forge deinstalliert${COLOR_NC}"
echo -e "${COLOR_GREEN}ugly-stack laeuft unveraendert weiter.${COLOR_NC}"
echo -e "${COLOR_GREEN}================================================${COLOR_NC}"
echo ""
