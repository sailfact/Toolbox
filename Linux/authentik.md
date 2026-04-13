# Authentik — Complete Self-Hosted Guide

## What is authentik?

Authentik is an IdP (Identity Provider) and SSO (Single Sign-On) platform built with security at the forefront, with an emphasis on flexibility and versatility. It provides robust recovery actions, user profile and password management, and supports all major providers: OAuth2, SAML, LDAP, and SCIM.

The project emerged from a simple frustration: existing open-source IdPs were either too complex to maintain or too limited in features. Its architecture separates the core authentication engine from outpost components, enabling horizontal scaling and high availability.

In practical homelab terms: authentik lets you put a single login page in front of every service you run — Gitea, Nextcloud, Portainer, Grafana, Paperless-ngx, etc. — with MFA, group-based access policies, and full audit logging.

---

## Architecture Overview

Authentik has three moving parts you need to understand before deploying:

**Server** — the main process. Handles authentication flows, the admin UI, the API, and the embedded outpost (proxy). Written in Python (Django) with a Go component for the embedded proxy.

**Worker** — a background process that handles email delivery, scheduled tasks, certificate renewal, and SCIM syncs. The server and worker run the same container image; they're just started with different commands.

**PostgreSQL** — the only persistent store. As of version 2025.10, Redis is no longer required. Caching, tasks, and WebSocket connections have all been migrated to PostgreSQL, simplifying the deployment significantly. Note: with the removal of Redis, your PostgreSQL instance will handle approximately 50% more connections than before.

**Outposts** — lightweight proxy/protocol containers that authentik spins up and manages. The embedded outpost (built into the server) handles forward auth for Traefik/Nginx. An LDAP outpost exposes an LDAP server so legacy apps can authenticate against authentik's user directory.

---

## Section 1 — Installation (Docker Compose)

Docker Compose is the recommended method for small and homelab setups.

### 1.1 Directory and Environment Setup

```bash
mkdir -p /opt/authentik/{media,certs,custom-templates,postgres}
cd /opt/authentik
```

Generate secrets:

```bash
# PostgreSQL password
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env

# Secret key (must be long and random — used for session signing)
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
```

> Because of a PostgreSQL limitation, only passwords up to 99 characters are supported. The `openssl` commands above stay safely within that.

### 1.2 The `.env` File

Add the following to your `.env` file (in addition to the generated secrets above):

```env
# --- Generated secrets (already written by openssl commands above) ---
# PG_PASS=...
# AUTHENTIK_SECRET_KEY=...

# --- Version pin (always pin — never use :latest) ---
AUTHENTIK_TAG=2025.12.1

# --- PostgreSQL ---
PG_USER=authentik
PG_DB=authentik

# --- Email (optional but strongly recommended) ---
AUTHENTIK_EMAIL__HOST=smtp.your-provider.com
AUTHENTIK_EMAIL__PORT=587
AUTHENTIK_EMAIL__USERNAME=your@email.com
AUTHENTIK_EMAIL__PASSWORD=your-smtp-password
AUTHENTIK_EMAIL__USE_TLS=true
AUTHENTIK_EMAIL__FROM=authentik@yourdomain.com
```

> If you want to use an existing PostgreSQL instance instead of a dedicated one, skip the `postgresql` service in the Compose file and set `AUTHENTIK_POSTGRESQL__HOST`, `AUTHENTIK_POSTGRESQL__USER`, `AUTHENTIK_POSTGRESQL__PASSWORD`, and `AUTHENTIK_POSTGRESQL__NAME` in `.env` pointing to your existing server. Create the `authentik` database and user first.

### 1.3 `docker-compose.yml`

By default, authentik listens internally on port 9000 for HTTP and 9443 for HTTPS.

```yaml
services:
  postgresql:
    image: docker.io/library/postgres:16-alpine
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"]
      start_period: 20s
      interval: 30s
      retries: 5
      timeout: 5s
    volumes:
      - /opt/authentik/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${PG_PASS}
      POSTGRES_USER: ${PG_USER:-authentik}
      POSTGRES_DB: ${PG_DB:-authentik}

  server:
    image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG:-2025.12.1}
    restart: unless-stopped
    command: server
    environment:
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_EMAIL__HOST: ${AUTHENTIK_EMAIL__HOST:-localhost}
      AUTHENTIK_EMAIL__PORT: ${AUTHENTIK_EMAIL__PORT:-25}
      AUTHENTIK_EMAIL__USERNAME: ${AUTHENTIK_EMAIL__USERNAME:-""}
      AUTHENTIK_EMAIL__PASSWORD: ${AUTHENTIK_EMAIL__PASSWORD:-""}
      AUTHENTIK_EMAIL__USE_TLS: ${AUTHENTIK_EMAIL__USE_TLS:-false}
      AUTHENTIK_EMAIL__FROM: ${AUTHENTIK_EMAIL__FROM:-authentik@localhost}
    volumes:
      - /opt/authentik/media:/media
      - /opt/authentik/custom-templates:/templates
    ports:
      - "9000:9000"
      - "9443:9443"
    depends_on:
      postgresql:
        condition: service_healthy

  worker:
    image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG:-2025.12.1}
    restart: unless-stopped
    command: worker
    environment:
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: ${PG_USER:-authentik}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_POSTGRESQL__NAME: ${PG_DB:-authentik}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_EMAIL__HOST: ${AUTHENTIK_EMAIL__HOST:-localhost}
      AUTHENTIK_EMAIL__PORT: ${AUTHENTIK_EMAIL__PORT:-25}
      AUTHENTIK_EMAIL__USERNAME: ${AUTHENTIK_EMAIL__USERNAME:-""}
      AUTHENTIK_EMAIL__PASSWORD: ${AUTHENTIK_EMAIL__PASSWORD:-""}
      AUTHENTIK_EMAIL__USE_TLS: ${AUTHENTIK_EMAIL__USE_TLS:-false}
      AUTHENTIK_EMAIL__FROM: ${AUTHENTIK_EMAIL__FROM:-authentik@localhost}
    user: root  # Needed for Docker socket access (managed outposts)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/authentik/media:/media
      - /opt/authentik/certs:/certs
      - /opt/authentik/custom-templates:/templates
    depends_on:
      postgresql:
        condition: service_healthy
```

> **On 2025.10+:** Redis is no longer needed. Remove any `redis` service and all `AUTHENTIK_REDIS__HOST` environment variable references.

### 1.4 Start and First Login

```bash
docker compose up -d

# Watch logs to confirm healthy startup
docker compose logs -f server
```

Once running, navigate to:

```
http://<your-server-ip>:9000/if/flow/initial-setup/
```

> You will get a Not Found error if the initial setup URL doesn't include the trailing forward slash `/`. Verify that the server, worker, and PostgreSQL containers are all running and healthy before navigating there.

Set your admin username and password. The admin account is called `akadmin` by default.

---

## Section 2 — Core Concepts

Understanding these four concepts unlocks everything else in authentik.

### 2.1 Flows and Stages

Flows are the core of authentik. Instead of rigid configuration screens, authentik uses flows and stages — you build authentication pipelines by chaining stages together. Need a login flow that checks a password, then prompts for MFA, then requires email verification for new devices? You build that by chaining stages in a flow.

The default flows out of the box are:

| Flow slug | Purpose |
|---|---|
| `default-authentication-flow` | Standard login flow (username → password → MFA) |
| `default-authorization-flow` | OAuth/OIDC consent screen |
| `default-enrollment-flow` | New user self-registration |
| `default-recovery-flow` | Password reset |
| `default-invalidation-flow` | Logout |
| `default-provider-authorization-implicit-consent` | Authorization without requiring explicit consent — used for trusted internal apps |

Common stage types: Identification, Password, Authenticator Validation (MFA), User Write, Prompt, Email, Deny, Redirect.

### 2.2 Providers

A provider defines how authentik talks to a service — which protocol, which keys, which scopes. Every application needs exactly one provider. The main provider types are:

- **OAuth2/OpenID Connect** — for modern apps (Gitea, Nextcloud, Grafana, Portainer, Vaultwarden, code-server)
- **SAML** — for enterprise/legacy apps that only speak SAML
- **Proxy** — for apps with no native SSO support (adds an authentik login wall via your reverse proxy)
- **LDAP** — exposes authentik's user directory as an LDAP server so apps like Paperless-ngx or email servers can authenticate against it
- **RADIUS** — for network devices (Wi-Fi auth, VPN)
- **SCIM** — for provisioning users into downstream apps automatically

### 2.3 Applications

An Application is the configuration object that ties a Provider to an access policy and a UI entry in the user portal. Each application gets a slug (URL-safe identifier), a display name, an icon, and a launch URL. Applications appear on the user's "My Applications" dashboard at `https://auth.yourdomain.com/if/user/`.

### 2.4 Outposts

Outposts are separate containers that handle specific protocols. They connect back to the authentik server via WebSocket. The most important ones for a homelab are:

- **Embedded Proxy Outpost** — ships built into the server container. Handles forward auth for Traefik and Nginx Proxy Manager. No extra container needed.
- **LDAP Outpost** — a separate container that exposes an LDAP listener on port 3389/6636. Deploy this if you need LDAP authentication for any service.

---

## Section 3 — Adding Your First Application (OAuth2/OIDC)

This walkthrough uses **Gitea** as the example, but the process is identical for Portainer, Nextcloud, Grafana, Vaultwarden, and most other homelab services.

### Step 1 — Create the Application and Provider

In the Admin interface, go to **Applications → Applications → Create with wizard**.

**Application tab:**
- Name: `Gitea`
- Slug: `gitea`
- Group: `Development` (optional — for grouping in the user portal)
- Launch URL: `https://gitea.yourdomain.com`

**Provider tab — select OAuth2/OpenID:**
- Name: `Gitea Provider`
- Authorization flow: `default-provider-authorization-implicit-consent` (for trusted internal apps; use the explicit consent flow for anything external)
- Client type: `Confidential`
- Client ID: auto-generated (copy this)
- Client Secret: auto-generated (copy this)
- Redirect URIs: `https://gitea.yourdomain.com/user/oauth2/authentik/callback`
- Signing Key: `authentik Self-signed Certificate`

**Bindings tab:** Add a group binding here to restrict access. For example, bind the group `users` — only members of that group can access Gitea via authentik.

### Step 2 — Configure Gitea to Use authentik

In Gitea's admin panel under **Site Administration → Authentication Sources → Add Authentication Source:**

- Authentication type: `OAuth2`
- Name: `authentik`
- OAuth2 Provider: `OpenID Connect`
- Client ID: (paste from above)
- Client Secret: (paste from above)
- OpenID Connect Auto Discovery URL: `https://auth.yourdomain.com/application/o/gitea/.well-known/openid-configuration`

The discovery URL pattern is always:

```
https://<authentik-host>/application/o/<app-slug>/.well-known/openid-configuration
```

---

## Section 4 — Proxy Provider (Forward Auth for Apps with No SSO)

For apps that have no built-in OAuth/SAML support, the Proxy Provider puts an authentik login wall in front of them via your reverse proxy. This is how you secure things like a plain web app or a service that only has HTTP basic auth.

### How Forward Auth Works

```
User → Traefik → authentik outpost (auth check)
         ↓ if authenticated
       App backend
         ↓ if not authenticated
       Redirect to authentik login flow
```

Using forward auth means your existing reverse proxy does the proxying, and only the authentik outpost checks authentication and authorization. The difference between single-application mode and domain-level mode is the host you specify: for single application, use the domain the application runs on; for domain level, use the same domain as authentik.

### 4.1 Create a Proxy Provider

**Applications → Providers → Create → Proxy Provider:**

- Name: `My App Proxy`
- Authorization flow: `default-provider-authorization-implicit-consent`
- Mode: `Forward auth (single application)` — one per app, allows per-app access policies
- External host: `https://myapp.yourdomain.com`

Then create an Application as normal, link it to this provider, and add it to the Embedded Outpost under **Applications → Outposts → Edit → Applications** (shift-click to add).

### 4.2 Traefik Middleware Config

```yaml
# traefik dynamic config (e.g. /etc/traefik/dynamic/authentik.yml)
http:
  middlewares:
    authentik:
      forwardAuth:
        address: http://authentik_server:9000/outpost.goauthentik.io/auth/traefik
        trustForwardHeader: true
        authResponseHeaders:
          - X-authentik-username
          - X-authentik-groups
          - X-authentik-email
          - X-authentik-name
          - X-authentik-uid
          - X-authentik-jwt
```

Then on any Traefik router label you want protected, add:

```yaml
labels:
  traefik.http.routers.myapp.middlewares: authentik@file
```

### 4.3 Nginx Proxy Manager

In NPM, for the proxy host you want to protect, go to the **Advanced** tab and add:

```nginx
location /outpost.goauthentik.io {
    proxy_pass http://<authentik-server-ip>:9000/outpost.goauthentik.io;
    proxy_set_header Host $host;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
}

auth_request /outpost.goauthentik.io/auth/nginx;
error_page 401 = @goauthentik_proxy_signin;
auth_request_set $auth_cookie $upstream_http_set_cookie;
add_header Set-Cookie $auth_cookie;

location @goauthentik_proxy_signin {
    internal;
    return 302 /outpost.goauthentik.io/start?rd=$scheme://$http_host$request_uri;
}
```

---

## Section 5 — LDAP Outpost

The LDAP outpost is what you deploy when an app can only authenticate against an LDAP directory — some email clients, Paperless-ngx, some monitoring tools, and network devices can all use LDAP auth.

### Deploy the LDAP Outpost

Add to your `docker-compose.yml`:

```yaml
  ldap:
    image: ghcr.io/goauthentik/ldap:${AUTHENTIK_TAG:-2025.12.1}
    restart: unless-stopped
    environment:
      AUTHENTIK_HOST: https://auth.yourdomain.com
      AUTHENTIK_INSECURE: "false"
      AUTHENTIK_TOKEN: <token-from-admin-ui>
    ports:
      - "389:3389"    # LDAP
      - "636:6636"    # LDAPS
```

Get the token from **Applications → Outposts → Edit** — create an LDAP outpost first, then copy its service account token.

**LDAP bind DN pattern:**

```
cn=<authentik-username>,ou=users,dc=ldap,dc=goauthentik,dc=io
```

Apps connecting via LDAP search against: `ou=users,dc=ldap,dc=goauthentik,dc=io`

---

## Section 6 — Multi-Factor Authentication

By default, MFA is disabled in authentik. Authentik supports TOTP, Duo, SMS, WebAuthn/passkey, and more.

To enable TOTP: go to **Flows and Stages → Stages → default-authentication-flow** and add an **Authenticator Validation Stage** between the Password stage and the User Login stage.

Configure the Authenticator Validation Stage:
- Device classes: `TOTP Devices`, `WebAuthn Devices` (tick both)
- Not configured action: `Deny` (enforces MFA for all users) or `Skip` (makes it optional)

As of version 2025.12, authentik supports passkey autofill (WebAuthn Conditional UI), which automatically prompts users for a passkey at login instead of requiring them to manually select the option — providing a smoother passwordless experience.

For the most secure setup, enable both TOTP and WebAuthn, and set "Not configured action" to `Deny` — any user without a registered MFA device simply cannot log in.

---

## Section 7 — User and Group Management

### Groups and Access Control

Groups are the primary mechanism for access control. The recommended workflow is:

1. Create a group (e.g. `admins`, `users`, `media-users`)
2. Create users and add them to groups
3. In each Application's bindings, bind the appropriate group — only group members can access that app

Navigate to: **Directory → Groups → Create**

### Invitation-Based Enrollment

The cleanest way to add users is via invitation links rather than open self-registration. Go to **Directory → Invitations → Create** to generate a single-use link. The invited user clicks it, completes the enrollment flow, and lands in whatever group you assigned.

### User Impersonation

Useful for debugging. In **Directory → Users**, find the user, click the kebab menu, and select **Impersonate**. You'll be logged in as that user to verify what they see. Click **Stop impersonating** in the top bar when done.

---

## Section 8 — Blueprints (Infrastructure as Code)

Blueprints allow you to define entire authentication flows in YAML, store them in Git, version-control your identity infrastructure, and deploy changes through CI/CD pipelines. This eliminates manual configuration drift and enables disaster recovery in minutes.

Blueprints live in `/blueprints` inside the media volume. You can also mount them from a Git repo using the `blueprints_dir` setting.

A minimal example blueprint that creates groups:

```yaml
version: 1
metadata:
  name: Base Groups
entries:
  - model: authentik_core.group
    state: present
    identifiers:
      name: users
    attrs:
      name: users
  - model: authentik_core.group
    state: present
    identifiers:
      name: admins
    attrs:
      name: admins
      is_superuser: false
```

Apply a blueprint: **System → Blueprints → Import**, or place the file in the blueprints directory and it will be detected automatically.

---

## Section 9 — Upgrading

Authentik does not support downgrading. Upgrades must follow the sequence of major releases — do not skip directly from an older major version to the most recent. Always upgrade to the latest minor version within each major before moving to the next major.

Before upgrading, back up your PostgreSQL database. Database migrations run automatically on startup.

```bash
# Back up the database first
docker compose exec postgresql pg_dump -U authentik authentik > authentik-backup-$(date +%F).sql

# Pull new images and restart
docker compose pull
docker compose up -d

# Migrations run automatically — watch the worker logs to confirm
docker compose logs -f worker
```

> The version of the authentik server and all authentik outposts must match. If you have a standalone LDAP outpost container, update its image tag at the same time. Never use the `:latest` tag — always pin to a specific version like `:2025.12.1`.

---

## Section 10 — Production Considerations

### Data Layout

Keep authentik data isolated per-concern for easier backups and portability:

```
/opt/authentik/
  postgres/           → PostgreSQL data directory
  media/              → uploaded files, icons, branding assets
  certs/              → managed TLS certificates
  custom-templates/   → Jinja2 email and flow templates
```

### Using an Existing PostgreSQL Instance

If you want to use a pre-existing PostgreSQL instance rather than the bundled one, create a dedicated database and user:

```sql
CREATE USER authentik WITH PASSWORD 'your-strong-password';
CREATE DATABASE authentik OWNER authentik;
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;
```

Then set those credentials in `.env` and remove the `postgresql` service from `docker-compose.yml`.

### Reverse Proxy and TLS

If you're running Traefik or Nginx in front of authentik, leave authentik on 9000/9443 internally and have the reverse proxy terminate TLS on 443 with a valid certificate. Ensure the reverse proxy passes `X-Forwarded-For` and `X-Forwarded-Proto` headers so authentik sees the correct client IP and scheme.

### Timezone Warning

Do not mount `/etc/timezone` or `/etc/localtime` inside the authentik containers. The server assumes internal timezone is UTC. Mounting timezone files will cause problems with OAuth and SAML authentication.

---

## Integration Reference — Common Homelab Apps

| App | Provider type | Notes |
|---|---|---|
| Gitea | OAuth2/OIDC | Discovery URL: `.../application/o/<slug>/.well-known/openid-configuration` |
| Nextcloud | OAuth2/OIDC | Use the `social_login` app in Nextcloud; or SAML via the SSO & SAML plugin |
| Portainer | OAuth2/OIDC | Under Settings → Authentication → OAuth |
| Grafana | OAuth2/OIDC | `[auth.generic_oauth]` in `grafana.ini` |
| Vaultwarden | OAuth2/OIDC | Enable SSO in admin panel; set OIDC discovery URL |
| Paperless-ngx | LDAP outpost | Set `PAPERLESS_LDAP_*` env vars pointing to the LDAP outpost |
| Uptime Kuma | Proxy | No native SSO — use Proxy Provider + forward auth |
| Homarr | OAuth2/OIDC | Supported natively in recent versions |
| code-server | Proxy | No native SSO — Proxy Provider is the cleanest approach |
| OPNsense | RADIUS or LDAP | RADIUS outpost → OPNsense RADIUS auth for admin login |
| Woodpecker CI | OAuth2/OIDC | Configure OIDC directly or via Gitea OAuth passthrough |

---

## Quick Troubleshooting

**"no app for hostname" error** — the application is not added to the outpost. Go to Applications → Outposts → Edit the Embedded Outpost, and shift-click to add your application.

**Redirect URI mismatch** — the callback URL in your app doesn't exactly match what's configured in the Provider. Check trailing slashes and HTTP vs HTTPS.

**Worker shows unhealthy** — the worker lost its WebSocket connection to the server. Check that both containers are on the same Docker network, then run `docker compose restart worker`.

**OAuth2 flow loops** — usually caused by clock skew. Authentik is UTC-strict; confirm your host clock is accurate (`timedatectl status`).

**LDAP bind fails** — verify the bind DN format: `cn=<username>,ou=users,dc=ldap,dc=goauthentik,dc=io`. Also confirm the LDAP outpost token matches the one in the Admin UI.
