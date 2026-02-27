#!/usr/bin/env bash
# Install AgentCockpit gateway as a systemd service on VPS
# Run as: bash install-service.sh
set -euo pipefail

GATEWAY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="agentcockpit-gateway"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "[install] Gateway dir: $GATEWAY_DIR"
echo "[install] Installing npm dependencies..."
cd "$GATEWAY_DIR"
npm ci --production=false

echo "[install] Building TypeScript..."
npm run build

echo "[install] Creating systemd service at $SERVICE_FILE..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=AgentCockpit WebSocket Gateway
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$GATEWAY_DIR
ExecStart=/usr/bin/node $GATEWAY_DIR/dist/server.js
Restart=on-failure
RestartSec=5s
Environment=NODE_ENV=production
EnvironmentFile=$GATEWAY_DIR/.env

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=agentcockpit-gateway

[Install]
WantedBy=multi-user.target
EOF

echo "[install] Creating .env file template (edit with your token)..."
if [ ! -f "$GATEWAY_DIR/.env" ]; then
  cat > "$GATEWAY_DIR/.env" << 'ENVEOF'
# AgentCockpit Gateway Environment
# REQUIRED: Set a strong random token
AGENTCOCKPIT_TOKEN=change-me-to-a-strong-random-token
AGENTCOCKPIT_PORT=19000
ENVEOF
  echo "[install] Created .env — EDIT IT and set AGENTCOCKPIT_TOKEN before starting!"
fi

echo "[install] Reloading systemd..."
systemctl daemon-reload

echo "[install] Enabling service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "=== Installation complete ==="
echo "1. Edit $GATEWAY_DIR/.env and set AGENTCOCKPIT_TOKEN"
echo "2. Start service: systemctl start $SERVICE_NAME"
echo "3. Check status: systemctl status $SERVICE_NAME"
echo "4. Follow logs: journalctl -u $SERVICE_NAME -f"
