#!/bin/bash
# One-time setup script for the AI Central Development Server on a fresh Ubuntu Linode.
# Installs Docker, Docker Compose plugin, firewall, and brings up the docker-compose stack.

set -euo pipefail

# === Config you might tweak ===
HOSTNAME="mcp.jcn.digital"
PROJECT_DIR="/opt/mcp-stack"
LINUX_USER="${SUDO_USER:-$(whoami)}"   # user to add to docker group
DOCKER_COMPOSE_VERSION="v2.29.7"

echo "[*] Updating system and setting hostname..."
apt-get update -y
apt-get upgrade -y
hostnamectl set-hostname "$HOSTNAME"

echo "[*] Installing dependencies..."
apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  lsb-release \
  ufw

echo "[*] Installing Docker..."
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh

echo "[*] Enabling Docker..."
systemctl enable docker --now

if id -u "$LINUX_USER" >/dev/null 2>&1; then
  echo "[*] Adding $LINUX_USER to docker group..."
  usermod -aG docker "$LINUX_USER"
fi

echo "[*] Installing docker compose plugin ($DOCKER_COMPOSE_VERSION)..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -sSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

echo "[*] Creating project directory at $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "[*] Writing docker-compose.yml and env template..."
cat > docker-compose.yml <<'EOF'
version: "3.8"

services:
  # === Ingress / management ===
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - ./nginx/data:/data
      - ./nginx/letsencrypt:/etc/letsencrypt
    networks:
      - proxy
      - internal

  portainer:
    image: portainer/portainer-ce:latest
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    ports:
      - "9443:9443"   # direct access (optionally restrict via firewall/VPN)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer/data:/data
    networks:
      - proxy
      - internal

  # === Automation / MCP ===
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      # DB settings (if you later use Postgres/Supabase/Neon)
      - DB_TYPE=${DB_TYPE}
      - DB_POSTGRESDB=${DB_POSTGRESDB}
      - DB_POSTGRES_HOST=${DB_POSTGRES_HOST}
      - DB_POSTGRES_PORT=${DB_POSTGRES_PORT}
      - DB_POSTGRES_USER=${DB_POSTGRES_USER}
      - DB_POSTGRES_PASSWORD=${DB_POSTGRES_PASSWORD}
      - DB_POSTGRES_SSL=${DB_POSTGRES_SSL}
    volumes:
      - ./n8n_data:/home/node/.n8n
    networks:
      - proxy
      - internal

  n8n-mcp:
    build:
      context: ./n8n-mcp
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      - n8n
    environment:
      - PORT=4000
      - N8N_API_URL=http://n8n:5678
      - MCP_HTTP_MODE=http
      - LOG_LEVEL=info
    networks:
      - proxy
      - internal

  # === Dev tooling ===
  code-server:
    image: coder/code-server:latest
    restart: unless-stopped
    environment:
      - PASSWORD=${CODESERVER_PASSWORD}
    volumes:
      - ./projects:/home/coder/projects
      - ./code-server/config:/home/coder/.local/share/code-server
    networks:
      - proxy
      - internal

  # === S3-like storage (MinIO) ===
  minio:
    image: quay.io/minio/minio:latest
    command: server /data --console-address ":9001"
    restart: unless-stopped
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
    volumes:
      - ./minio/data:/data
    expose:
      - "9000"
      - "9001"
    networks:
      - proxy
      - internal

  # === Datastores ===
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ./redis/data:/data
    networks:
      - internal

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_USER=${PG_USER}
      - POSTGRES_PASSWORD=${PG_PASSWORD}
      - POSTGRES_DB=${PG_DB}
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
    networks:
      - internal

  # === (Future) Admin MCP agent ===
  admin-agent-mcp:
    image: alpine:3.20
    command: ["sh", "-c", "echo 'admin MCP agent placeholder'; sleep infinity"]
    restart: unless-stopped
    networks:
      - internal
      - proxy

networks:
  proxy:
    driver: bridge
  internal:
    driver: bridge
EOF

cat > .env <<'EOF'
# === n8n basic auth and URLs ===
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=change_me_now
N8N_HOST=n8n.jcn.digital
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://n8n.jcn.digital

# === n8n DB (optional – if using external Postgres, override these) ===
DB_TYPE=sqlite
DB_POSTGRESDB=
DB_POSTGRES_HOST=
DB_POSTGRES_PORT=
DB_POSTGRES_USER=
DB_POSTGRES_PASSWORD=
DB_POSTGRES_SSL=true

# === code-server auth ===
CODESERVER_PASSWORD=change_me_now

# === MinIO root credentials ===
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=change_me_now

# === Local Postgres (if you decide to use it) ===
PG_USER=dev
PG_PASSWORD=change_me_now
PG_DB=devdb
EOF

echo "[*] Preparing n8n-mcp build context..."
mkdir -p n8n-mcp
cat > n8n-mcp/Dockerfile <<'EOF'
FROM node:20-alpine AS builder
RUN apk add --no-cache git python3 make g++ libc6-compat
WORKDIR /src

ARG N8N_MCP_REPO=https://github.com/czlonkowski/n8n-mcp.git
ARG N8N_MCP_REF=main

RUN git clone --depth 1 --branch ${N8N_MCP_REF} ${N8N_MCP_REPO} .

RUN npm ci
RUN npm run build

FROM node:20-alpine
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /src/package.json /src/package-lock.json ./
COPY --from=builder /src/dist ./dist
COPY --from=builder /src/bin ./bin

EXPOSE 4000
ENV NODE_ENV=production
CMD ["node", "dist/mcp/server.js"]
EOF

echo "[*] Starting docker compose stack..."
/usr/local/lib/docker/cli-plugins/docker-compose up -d

echo "[*] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
# Optional direct access to Portainer https (you can remove if only using via NPM)
ufw allow 9443/tcp
ufw --force enable

echo
echo "=============================="
echo "Setup complete."
echo "Next steps:"
echo "1) Make sure DNS A records for:"
echo "   - mcp.jcn.digital"
echo "   - n8n.jcn.digital"
echo "   - portainer.jcn.digital"
echo "   - minio.jcn.digital"
echo "   - code.jcn.digital"
echo "   point to this Linode's IP."
echo "2) Visit http://<IP>:81 to configure Nginx Proxy Manager."
echo "3) In NPM, add Proxy Hosts:"
echo "   - n8n.jcn.digital -> http://n8n:5678 (Enable SSL, Let's Encrypt)"
echo "   - mcp.jcn.digital -> http://n8n-mcp:4000 (Enable SSL)"
echo "   - portainer.jcn.digital -> https://portainer:9443 (Trust upstream cert)"
echo "   - minio.jcn.digital -> http://minio:9001 (Enable SSL)"
echo "   - code.jcn.digital -> http://code-server:8080 (Enable SSL)"
echo "4) Edit $PROJECT_DIR/.env to change all 'change_me_now' secrets,"
echo "   then run: docker compose down && docker compose up -d"
echo "=============================="