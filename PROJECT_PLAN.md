# AI Central Development Server – Comprehensive Project Plan

## 1. Executive Summary
You are building a centralized “Developer Control Plane” at `mcp.jcn.digital` to unify:
- MCP Gateway + workflow automation (n8n + n8n-mcp)
- Central Docker environment & multi-host management (Portainer)
- Web IDE (code-server)
- Object storage abstraction / S3-like endpoint (MinIO)
- Supporting data stores (Redis, Postgres – optionally external Neon / Supabase instead)
- **Automated Neon Database branching for PR previews** (integrated via GitHub Actions)
- Future observability (Grafana + Prometheus stack)
- An “Admin AI Agent” MCP service able to assist/configure infrastructure and expose tools to other agents
- Secure remote access (later via WireGuard)

The result: all agents, development environments (Codespaces, local IDEs, HuggingFace Spaces), and workflow automation will reference a **single credential + tooling hub**, minimizing repeated setup and improving consistency.

**NEW**: Neon database integration workflow automatically creates preview branches for pull requests, enabling isolated testing environments. See [NEON_INTEGRATION.md](NEON_INTEGRATION.md) for details.

---

## 2. Goals & Non-Goals

### Goals
- Centralize credentials and tool access for agents.
- Standardize deployment procedures (Copilot / automation agent friendly).
- Provide secure, TLS-enabled endpoints for each core service.
- Enable incremental addition of observability and AI admin tooling.
- Simplify multi-cloud storage workflows via MinIO + supplemental scripts.
- Support future multi-node expansion (split heavy services onto new Linodes).

### Non-Goals (initial phase)
- High-availability clustering (single-node acceptable now).
- Kubernetes orchestration (Docker Compose sufficient).
- Advanced IAM / multi-user RBAC (single user “jblast” focus).
- Production-grade secrets management (will evolve later).

---

## 3. High-Level Architecture

```
                 Internet
                    |
              +--------------+
              | Nginx Proxy  |  (Nginx Proxy Manager)
              |   Manager    |
              +--+-------+---+
                 |       |
   TLS vhosts (HTTPS)    |
   ---------------------------
   mcp.jcn.digital  --> n8n-mcp (MCP server)
   n8n.jcn.digital  --> n8n (workflow engine)
   portainer.jcn.digital --> Portainer (Docker mgmt)
   minio.jcn.digital --> MinIO Console
   code.jcn.digital  --> code-server IDE
   (future) admin.jcn.digital --> Admin AI MCP Agent
   (future) grafana.jcn.digital --> Grafana dashboards
   ---------------------------

   Internal Network (Docker bridge):
   - redis
   - postgres (optional; external Neon/Supabase recommended)
   - future: prometheus, node-exporter, alertmanager
```

---

## 4. Core Services & Purpose

| Service | Purpose | Public Host | Port (internal) | Persistence |
|---------|---------|-------------|-----------------|-------------|
| Nginx Proxy Manager | Reverse proxy + TLS | :80/:443/:81 | 80/443/81 | ./nginx |
| n8n | Workflow creation/execution | n8n.jcn.digital | 5678 | ./n8n_data |
| n8n-mcp | MCP bridge to n8n | mcp.jcn.digital | 4000 | (stateless) |
| Portainer | Docker mgmt multi-host | portainer.jcn.digital | 9443 | ./portainer/data |
| code-server | Web IDE | code.jcn.digital | 8080 | ./projects + ./code-server/config |
| MinIO | S3-compatible storage | minio.jcn.digital | 9000 (API), 9001 (console) | ./minio/data |
| Redis | Cache / queues | (internal only) | 6379 | ./redis/data |
| Postgres | Local DB (optional) | (internal only) | 5432 | ./postgres/data |
| Admin MCP Agent (future) | AI infra assistant | admin.jcn.digital | TBD (e.g. 4500) | depends |
| Grafana (future) | Dashboards | grafana.jcn.digital | 3000 | ./grafana |
| Prometheus (future) | Metrics store | (internal) | 9090 | ./prometheus |

---

## 5. Environment Variables Reference

Place in `.env` (do NOT commit secrets publicly if making repo public – use `.env.local` and add `.env` to `.gitignore` if necessary).

| Variable | Required | Default/Example | Description |
|----------|----------|-----------------|-------------|
| N8N_BASIC_AUTH_ACTIVE | Yes | true | Enables simple auth |
| N8N_BASIC_AUTH_USER | Yes | user-jblast | n8n UI/API user |
| N8N_BASIC_AUTH_PASSWORD | Yes | admin4ai! | CHANGE AFTER DEPLOY |
| N8N_HOST | Yes | n8n.jcn.digital | External host used for webhook URLs |
| N8N_PROTOCOL | Yes | https | External protocol |
| N8N_EDITOR_BASE_URL | Yes | https://n8n.jcn.digital | Editor public base URL |
| DB_TYPE | Yes | sqlite (or postgresdb) | n8n DB backend |
| DB_POSTGRESDB | If Postgres | devdb | Database name |
| DB_POSTGRES_HOST | If Postgres | postgres | Host (internal) or external Neon |
| DB_POSTGRES_PORT | If Postgres | 5432 | Port |
| DB_POSTGRES_USER | If Postgres | dev | Username |
| DB_POSTGRES_PASSWORD | If Postgres | change_me | Password |
| DB_POSTGRES_SSL | If external | true | SSL mode toggle |
| CODESERVER_PASSWORD | Yes | admin4ai! | Web IDE password (CHANGE) |
| MINIO_ROOT_USER | Yes | minioadmin | MinIO root user |
| MINIO_ROOT_PASSWORD | Yes | admin4ai! | MinIO root password |
| PG_USER | Optional local | dev | Local Postgres user |
| PG_PASSWORD | Optional local | change_me | Local Postgres password |
| PG_DB | Optional local | devdb | Local Postgres DB name |
| REDIS_PASSWORD | Optional | (blank) | If you add auth via custom image |
| MCP_ADMIN_USER | Future admin agent | user-jblast | Admin agent login |
| MCP_ADMIN_PASSWORD | Future admin agent | admin4ai! | CHANGE post-deploy |
| SUPABASE_URL | Optional external | https://XYZ.supabase.co | If connecting n8n workflows |
| SUPABASE_SERVICE_ROLE_KEY | Optional | (secret) | Service role key (protect) |
| NEON_DATABASE_URL | Optional | (secret DSN) | Neon connection string |
| S3_EXTERNAL_CONFIG_DIR | Optional | ./s3-profiles | Directory for multi-cloud profiles |
| WIREGUARD_ENABLE | Optional | false | Flag for future WG integration |
| WIREGUARD_PEER_PUBLIC_KEY | Optional | (key) | Peer config |
| WIREGUARD_PEER_ALLOWED_IPS | Optional | 10.0.0.0/24 | Allowed subnet |
| GRAFANA_ADMIN_USER | Future | admin | Grafana user |
| GRAFANA_ADMIN_PASSWORD | Future | admin4ai! | CHANGE |
| PROMETHEUS_RETENTION | Future | 15d | Metrics retention |
| LOG_LEVEL | Many services | info | Logging verbosity |

---

## 6. Instance Sizing Recommendations

| Phase | Recommended Linode Plan | Rationale |
|-------|-------------------------|-----------|
| Initial dev (all services, light workflows) | Shared CPU 4GB (e.g. Linode 4GB) | Enough RAM for n8n, Portainer, MinIO, Postgres, Redis |
| Moderate automation (increasing workflows, some storage) | Shared CPU 8GB | Headroom for Redis buffers, MinIO caching, code-server usage |
| Heavy workflows / large file ops / added Grafana + Prometheus | Dedicated CPU 8GB or 16GB | Stable performance for concurrent agent builds |
| Split architecture (n8n heavy, storage heavy) | One 8GB for automation, one 4–8GB for data | Isolation & scalability |

Start with **Linode 4GB Shared**. Monitor:
- If average RAM > 70% or CPU saturates → upgrade to 8GB.
- Use Portainer and `docker stats`, and consider node-exporter + Grafana later.

---

## 7. Deployment Workflow (Copilot / Automation Agent Instructions)

### Pre-Requisites
1. DNS A records for:
   - `mcp.jcn.digital`
   - `n8n.jcn.digital`
   - `portainer.jcn.digital`
   - `minio.jcn.digital`
   - `code.jcn.digital`
2. Linode fresh Ubuntu (22.04 or 24.04).
3. SSH access with sudo.

### Steps
1. Clone repo:
   ```bash
   git clone https://github.com/bbj4t/AI-Central-Development-Server.git
   cd AI-Central-Development-Server
   ```
2. Create `.env` from `.env.example` (update secrets immediately).
3. Run setup:
   ```bash
   sudo ./setup-mcp-server.sh
   ```
   (If you move script under `infra/`, adjust path.)
4. Access Nginx Proxy Manager at `http://<IP>:81`:
   - Change default admin.
   - Create Proxy Hosts:
     - `n8n.jcn.digital` → `http://n8n:5678`
     - `mcp.jcn.digital` → `http://n8n-mcp:4000`
     - `portainer.jcn.digital` → `https://portainer:9443` (Enable “Ignore Invalid SSL” upstream)
     - `minio.jcn.digital` → `http://minio:9001`
     - `code.jcn.digital` → `http://code-server:8080`
   - Request Let’s Encrypt certs (Force SSL).
5. Login:
   - n8n: `https://n8n.jcn.digital` (user: `user-jblast`, pass: `admin4ai!`)
   - Portainer: set initial admin password (choose strong).
   - MinIO: root credentials.
   - code-server: password from `.env`.
6. Rotate initial passwords immediately.
7. (Optional) Add external Docker endpoints in Portainer for other hosts:
   - Deploy Portainer Agent on remote machine:
     ```bash
     docker run -d \
       -p 9001:9001 \
       --name portainer_agent \
       --restart=always \
       -v /var/run/docker.sock:/var/run/docker.sock \
       -v /var/lib/docker/volumes:/var/lib/docker/volumes \
       portainer/agent:latest
     ```
   - Register endpoint in Portainer UI (remote IP + 9001).
8. Add MinIO mc profiles for external providers (`aws`, `wasabi`, `gcp`) via a future script.

### Automation Agent Pseudocode
```
1. Ensure DNS resolves target domains.
2. SSH into server (key-based auth).
3. Pull repo -> checkout deployment branch.
4. Verify/patch .env with secrets (avoid plaintext commit).
5. Run setup script.
6. Wait for docker compose health checks.
7. Configure NPM via API or manual (phase 1: manual acceptable).
8. Register remote Docker endpoints in Portainer via its API (optional).
9. Output service status JSON for monitoring.
```

---

## 8. Project Roadmap & Phases

| Phase | Milestone | Tasks |
|-------|-----------|-------|
| 0 | Prep | DNS, Linode provisioning, repository finalization |
| 1 | Core Stack Online | Run setup, NPM proxy hosts, baseline security |
| 2 | Multi-Cloud Storage | Add MinIO external mc profiles & S3 credential workflows in n8n |
| 3 | Observability | Add Prometheus + node-exporter, then Grafana dashboards |
| 4 | Admin AI Agent | Select repo / implement MCP agent with tools (Docker, FS, n8n actions) |
| 5 | Hardening | Enable WireGuard, move sensitive services to VPN-only, secrets vault |
| 6 | Scaling Split | If needed: separate heavy services to a second Linode |

---

## 9. Task Breakdown (Initial Backlog)

### Must-Do (Phase 1)
- [ ] Populate `.env` with secure (temporary) passwords.
- [ ] Run `setup-mcp-server.sh`.
- [ ] Configure NPM proxy & HTTPS.
- [ ] Change all initial passwords.
- [ ] Document baseline access in `ACCESS.md`.
- [x] **Configure Neon Database integration workflow for PR previews**.

### Should-Do (Phase 2–3)
- [ ] Add script: `scripts/configure-minio-mc.sh` (multi-cloud profiles).
- [ ] Create n8n workflows for bucket sync / credential rotation.
- [ ] Add Prometheus + node-exporter services in `docker-compose.yml`.
- [ ] Add Grafana service + initial dashboard JSONs.
- [ ] **Set up database migrations for Neon preview branches**.
- [ ] **Configure n8n to use Neon database in production**.

### Future / Optional
- [ ] Integrate Vault or Doppler for secrets.
- [ ] WireGuard auto-join script.
- [ ] Admin MCP agent container (replace placeholder).
- [ ] Automated Portainer endpoint registration script.
- [ ] CI pipeline for building n8n-mcp image (GitHub Actions).

---

## 10. Security & Compliance Considerations

| Area | Action |
|------|--------|
| Credentials | Replace `admin4ai!` immediately after deploy. Use a password manager. |
| Secrets in repo | Add `.env` to `.gitignore` if public. Commit only `.env.example`. |
| Network | Restrict direct Portainer (9443) if unneeded; rely on NPM + IP allowlist. |
| TLS | Enforce HTTPS on all proxy hosts. |
| Docker Socket | Portainer & n8n have indirect access; avoid exposing externally. |
| MinIO | Rotate root credentials; create scoped access keys for workflows. |
| Logs | Future: centralize logs (Promtail + Loki or ELK stack). |
| VPN | Add WireGuard to protect admin-only services when multi-user grows. |
| Backups | Nightly tar of data directories: `n8n_data`, `minio/data`, `postgres/data`, `redis/data`. |
| Monitoring | Add Prometheus exporters to watch resource trends for scaling decisions. |

---

## 11. Risk Register (Early)

| Risk | Impact | Mitigation |
|------|--------|------------|
| Single-node failure | Full downtime | Regular backups; future second node |
| Passwords exposed during early phase | Credential compromise | Immediate rotation; do not commit real secrets |
| Resource contention (MinIO + n8n heavy flows) | Slow workflows | Monitor & scale vertically |
| Lack of observability early | Hidden bottlenecks | Add Prometheus/Grafana Phase 3 |
| Manual NPM config errors | Misrouting / downtime | Script NPM API config later |
| Agent over-permissions | Accidental destructive ops | Implement scoped MCP tools; read-only mode first |
| Secrets drift across services | Failed workflows | Centralize env + adopt Vault later |

---

## 12. Future Enhancements (Ideas)

- Add Service Mesh (not urgent).
- Add OpenAI / Anthropic / Local LLM proxy microservice for consistent model access.
- Deploy a workflow to auto-provision new project scaffolds via code-server + n8n triggers.
- Set up GitHub Actions CI to build & push `n8n-mcp` image with tags (e.g. semantic versioning).
- Add `admin-agent-mcp` embedding retrieval (vector DB) for infra docs.

---

## 13. Maintenance Checklist (Weekly)

| Item | Action |
|------|--------|
| Docker images | `docker compose pull` + `up -d` |
| TLS certs | Verify renewal (NPM handles automatically) |
| Backups | Verify latest snapshot integrity |
| Logs | Check container logs for errors |
| Resource metrics | CPU/RAM/disk growth trends |
| Security | Confirm no default passwords remain |
| Workflow health | n8n queue success/failure patterns |
| MinIO | Storage capacity / object growth |

---

## 14. Appendices

### A. Directory Layout (Proposed)
```
AI-Central-Development-Server/
  docker-compose.yml
  setup-mcp-server.sh
  .env.example
  infra/
    README.md
    scripts/
      configure-minio-mc.sh (future)
      register-portainer-endpoints.sh (future)
      add-wireguard-peer.sh (future)
  n8n-mcp/
    Dockerfile (build n8n-mcp)
  docs/
    PROJECT_PLAN.md
    ACCESS.md (service URLs & roles)
    BACKUPS.md (procedures)
```

### B. Adding Grafana + Prometheus (Future Snippet)
```yaml
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus:/etc/prometheus
    networks:
      - internal
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
    volumes:
      - ./grafana:/var/lib/grafana
    networks:
      - proxy
    restart: unless-stopped
```

---

## 15. Immediate Action Items (Summary)
1. Provision Linode (4GB) & set DNS A records.
2. Clone repo & populate `.env`.
3. Run setup script & bring stack online.
4. Configure NPM proxy hosts + TLS.
5. Change all bootstrap credentials.
6. Validate service access & basic workflows.
7. Plan next sprint: MinIO multi-cloud integration + Admin MCP agent selection.

---

> IMPORTANT: The password `admin4ai!` is a placeholder. Rotate it for every service immediately after initial deployment. Do NOT commit real secrets to the repository.

---

## 16. Contact / Operator Identity
Primary operator user: `user-jblast`  
(Ensure this user reference persists consistently across services and agents.)

---

End of Project Plan.