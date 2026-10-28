# MyLogbook Infrastructure

GitOps repository for MyLogbook. It contains the Docker Compose stacks, image tags and encrypted secrets for the QA and production environments.

Application code and Docker images live in the separate `gps_tracker` repository. Images publish to `docker.spoyla.com/devops-mylogbook-*` from the Azure Pipelines in that repository.

## Environments

| Service | QA | Production |
|---|---|---|
| API | `stacks/qa/api` | `stacks/production/api` |
| PWA | `stacks/qa/pwa` | `stacks/production/pwa` |
| Marketing website | `stacks/qa/marketing` | `stacks/production/marketing` |
| PostgreSQL | `stacks/release/db` | `stacks/release/db` |

The release database stack creates one PostgreSQL 16 container with separate `mylogbook_qa` and `mylogbook_prod` databases. It is self-contained and uses the `mylogbook_default` Docker network.

## Hostnames and ports

| Host | Service | Host port |
|---|---|---|
| `qa.mylogbook.co.za` | QA marketing | 8083 |
| `qapwa.mylogbook.co.za` | QA PWA | 8084 |
| `qaapi.mylogbook.co.za` | QA API | 8085 |
| `mylogbook.co.za`, `www.mylogbook.co.za` | Production marketing | 8080 |
| `pwa.mylogbook.co.za` | Production PWA | 8081 |
| `api.mylogbook.co.za` | Production API | 8082 |
| PostgreSQL | Release database | 7433 |

The host reverse proxy terminates TLS and forwards each hostname to the matching published port. The compose stacks do not contain proxy labels. The marketing container redirects `www.mylogbook.co.za` to `mylogbook.co.za` and returns `X-Robots-Tag: noindex` on the QA host.

Confirm every port is free on the target host before the first deployment. The production trio is 8080-8082; QA uses 8083-8085. The neighbouring Spoyla, SpinFlow and SprintClock stacks use 6060-6150, 7060-7090 and 7160-7195.

## Images

| Image | Built by |
|---|---|
| `docker.spoyla.com/devops-mylogbook-api` | `Api/MyLogbook.Api/azure-pipelines-api.yml` |
| `docker.spoyla.com/devops-mylogbook-dbup` | `Api/MyLogbook.Api/azure-pipelines-api.yml` |
| `docker.spoyla.com/devops-mylogbook-pwa` | `UI/Angular/MyLogbook.UI.Angular.Pwa/azure-pipelines-pwa.yml` |
| `docker.spoyla.com/devops-mylogbook-marketing` | `UI/Angular/MyLogbook.UI.Angular.Marketing.Web/azure-pipelines-marketing.yml` |

The API pipeline builds the API and DbUp images with the same build number. The PWA and marketing pipelines build QA and production variants: QA publishes `latest` and `<build>`, production publishes `latest-prod` and `<build>-prod`.

Each stack's `.env` holds only the image tag. Set it to a build number for a reproducible deployment; `latest` and `latest-prod` are useful for the first rollout.

## Layout

```text
mylogbook-infrastructure/
├── stacks/
│   ├── qa/
│   │   ├── api/docker-compose.yml       .env
│   │   ├── pwa/docker-compose.yml       .env
│   │   └── marketing/docker-compose.yml .env
│   ├── production/
│   │   ├── api/docker-compose.yml       .env
│   │   ├── pwa/docker-compose.yml       .env
│   │   └── marketing/docker-compose.yml .env
│   └── release/
│       └── db/
│           ├── docker-compose.yml
│           └── initdb/01-create-databases.sh
├── secrets/
│   ├── mylogbook.key                    (git-ignored)
│   ├── qa/api.env                       (git-ignored)
│   ├── qa/api.env.enc
│   ├── prod/api.env                     (git-ignored)
│   ├── prod/api.env.enc
│   ├── release/db.env                   (git-ignored)
│   └── release/db.env.enc
└── scripts/
    ├── encrypt-secrets.ps1
    └── decrypt-secrets.ps1
```

## Secrets

Secrets are encrypted with OpenSSL AES-256-CBC and PBKDF2. The encryption key is `secrets/mylogbook.key`; it is git-ignored and must be stored in a password manager or vault. Never commit a decrypted `.env` file or the key.

Decrypt for deployment:

```powershell
./scripts/decrypt-secrets.ps1
```

Encrypt after editing:

```powershell
./scripts/encrypt-secrets.ps1
```

The committed `api.env.enc` files contain strong generated database and token values, but the SMTP and social-login values are placeholders. Replace them before enabling email sign-in or social sign-in. The PWA's Google and Apple client IDs are compile-time values in `environment.qa.ts` and `environment.prod.ts` in the app repository, so set them there and rebuild the PWA images.

## First deployment

1. Confirm the host ports and DNS records.
2. Decrypt the secrets.
3. Start the database once:

   ```bash
   cd stacks/release/db
   docker compose --env-file ../../../secrets/release/db.env up -d
   ```

   Wait for the healthcheck. The init script creates `mylogbook_qa` and `mylogbook_prod` only when the volume is first initialised.

4. Start the QA API stack. The migration container runs to completion before the API starts:

   ```bash
   cd stacks/qa/api
   docker compose --env-file .env --env-file ../../../secrets/qa/api.env up -d
   ```

5. Start the QA PWA and marketing stacks:

   ```bash
   docker compose --env-file .env up -d
   ```

6. Repeat for `stacks/production`.

The API `GET /health` returns `200` when the database is reachable. The PWA and marketing containers expose `GET /health`.

## Database migrations

The API stack runs `devops-mylogbook-dbup` as a one-shot `migrator` service before the API. DbUp applies journaled schema scripts once and reapplies idempotent data and function scripts on every rollout.

A failed migration stops the API from starting. Inspect the migrator logs with:

```bash
docker compose logs migrator
```

## Rollback

Set the service tag in the stack `.env` back to the previous build number and let Dockhand or Compose redeploy. Do not roll back the database image independently of the API; schema scripts are forward-only.

## Backups

Back up the `mylogbook-postgres-data-release` volume and take regular `pg_dump` copies of both databases. A restore must be tested before it is needed.

## DNS and TLS

Create DNS records for all hostnames in the table above. Issue certificates for every hostname, including `www.mylogbook.co.za`, because the marketing container must answer HTTPS before it redirects to the apex.

The application expects the PWA and API to share the `mylogbook.co.za` registrable domain. Do not move either to a different domain; refresh-token cookies are same-site.
