# MyLogbook Infrastructure

GitOps repository for MyLogbook. It contains the Docker Compose stacks, image tags and encrypted secrets for the QA and production environments.

Application code and Docker images live in the sibling `MyLogbook` repository. Images publish to `docker.spoyla.com/devops-mylogbook-*` from the Azure Pipelines in that repository.

## Environments

| Service | QA | Production |
|---|---|---|
| API | `stacks/qa/api` | `stacks/production/api` |
| Worker Service | `stacks/qa/workerservice` | `stacks/production/workerservice` |
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
| `docker.spoyla.com/devops-mylogbook-workerservice` | `Service/MyLogbook.Service.SystemEvent.WS/azure-pipelines-workerservice.yml` |
| `docker.spoyla.com/devops-mylogbook-pwa` | `UI/Angular/MyLogbook.UI.Angular.Pwa/azure-pipelines-pwa.yml` |
| `docker.spoyla.com/devops-mylogbook-marketing` | `UI/Angular/MyLogbook.UI.Angular.Marketing.Web/azure-pipelines-marketing.yml` |

The PWA and marketing pipelines build QA and production variants: QA publishes `latest` and `<build>`, production publishes `latest-prod` and `<build>-prod`.

Each stack's `.env` holds only the image tag. Set it to a build number for a reproducible deployment; `latest` and `latest-prod` are useful for the first rollout.

## Layout

```text
mylogbook-infrastructure/
├── stacks/
│   ├── qa/
│   │   ├── api/docker-compose.yml       .env
│   │   ├── workerservice/docker-compose.yml .env
│   │   ├── pwa/docker-compose.yml       .env
│   │   └── marketing/docker-compose.yml .env
│   ├── production/
│   │   ├── api/docker-compose.yml       .env
│   │   ├── workerservice/docker-compose.yml .env
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
│   ├── qa/workerservice.env             (git-ignored)
│   ├── qa/workerservice.env.enc
│   ├── prod/api.env                     (git-ignored)
│   ├── prod/api.env.enc
│   ├── prod/workerservice.env           (git-ignored)
│   ├── prod/workerservice.env.enc
│   ├── release/db.env                   (git-ignored)
│   └── release/db.env.enc
└── scripts/
    ├── deploy-workerservice.ps1
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

Each environment has two secret files. `api.env` holds the API's database connection, token signing secret, CORS, OTP and social-login settings. `workerservice.env` holds the worker's database connection, SMTP connection and credentials, the PWA URL used in account-deletion links, and the OTP expiry and attempt limit. The API never sends email, so SMTP settings live only in `workerservice.env`. The database connection and the OTP settings appear in both files and must match. The PWA's Google and Apple client IDs are compile-time values in `environment.qa.ts` and `environment.prod.ts` in the app repository, so set them there and rebuild the PWA images.

## First deployment

1. Confirm the host ports and DNS records.
2. Decrypt the secrets.
3. Start the database once:

   ```bash
   cd stacks/release/db
   docker compose --env-file ../../../secrets/release/db.env up -d
   ```

   Wait for the healthcheck. The init script creates `mylogbook_qa` and `mylogbook_prod` only when the volume is first initialised.

4. Run the QA database release so DbUp migrates `mylogbook_qa`, then start the QA API stack:

   ```bash
   cd stacks/qa/api
   docker compose --env-file .env --env-file ../../../secrets/qa/api.env up -d
   ```

5. Configure SMTP in `secrets/qa/workerservice.env`: set the SMTP host, port, sender and any required credentials. Re-encrypt the updated file. From the repository root, validate and start the QA worker after migration `0022_CreateSystemEvents`:

   ```powershell
   ./scripts/deploy-workerservice.ps1 -Environment qa -ValidateOnly
   ./scripts/deploy-workerservice.ps1 -Environment qa
   ```

   This pulls the selected worker image and starts the worker. It requires the database stack's network and checks the database connection, SMTP configuration and PWA URL without printing credentials. It does not test SMTP connectivity or message delivery.

6. Start the QA PWA and marketing stacks:

   ```bash
   docker compose --env-file .env up -d
   ```

7. Request an OTP from the QA app and verify it reaches the intended inbox and no `Failed` row appears in `system_events`. Repeat the rollout for `stacks/production`, using `-Environment prod` for the worker.

The API `GET /health` returns `200` when the database is reachable. The PWA and marketing containers expose `GET /health`.

Register `Service/MyLogbook.Service.SystemEvent.WS/azure-pipelines-workerservice.yml` as an Azure DevOps pipeline and run it to publish the worker image. A YAML file in the application repository does not create or enable that pipeline automatically. Register both worker Compose folders in Dockhand or run the deployment helper on the Docker host; having these files in source does not start either worker. This repository contains no automatic deployment pipeline.

## Database migrations

Migrations are not part of the compose stacks. `DB/azure-pipelines-db.yml` in the app repository runs when `DB/**` changes and publishes the `MyLogbook.DbUp` build artifact. An Azure release pipeline deploys that artifact and runs it against each database:

```bash
dotnet MyLogbook.DB.DbUp.dll "<connection string>"
```

DbUp applies journaled schema scripts once and reapplies idempotent data and function scripts on every run. It exits non-zero on a failed script. Run the database release before deploying an API build that depends on new schema.

## Rollback

Set the service tag in the stack `.env` back to the previous build number and let Dockhand or Compose redeploy. Schema scripts are forward-only; a rolled-back API must still work against the current schema.

## Backups

Back up the `mylogbook-postgres-data-release` volume and take regular `pg_dump` copies of both databases. A restore must be tested before it is needed.

## DNS and TLS

Create DNS records for all hostnames in the table above. Issue certificates for every hostname, including `www.mylogbook.co.za`, because the marketing container must answer HTTPS before it redirects to the apex.

The application expects the PWA and API to share the `mylogbook.co.za` registrable domain. Do not move either to a different domain; refresh-token cookies are same-site.


## Worker service and Sentry

Deploy the matching `workerservice` stack alongside each API after migration `0022_CreateSystemEvents`. It has no
published port and `.env` selects `WORKER_IMAGE_TAG`. Use the same release's API and worker images.
The QA worker reads `../../../secrets/qa/workerservice.env`; production reads `../../../secrets/prod/workerservice.env`.
Use `scripts/deploy-workerservice.ps1 -Environment qa` or `-Environment prod` from the repository root.
The worker needs no token secret.

The worker processes the `system_events` table. The API adds a row for each sign-in code, account deletion request and contact message, and the matching worker sends the email. Email always uses SMTP. Configure a real SMTP host and sender before deploying; the committed example files contain no usable SMTP credentials. There is no email disable setting, file delivery mode or email storage volume. Local development must also use an SMTP server.

Email workers never retry. A send that fails, times out or is interrupted is marked `Failed` and is not sent again, so a user never receives the same email twice. The user requests a new code or link instead.

After rollout, check worker logs with `docker compose --env-file .env --env-file ../../../secrets/qa/workerservice.env logs --tail 100 workerservice` from the QA worker folder, or substitute `prod` for production. A running worker container or healthy API does not prove queue processing or SMTP delivery. Processed events are deleted, so look for events that are stuck or failed:

```sql
SELECT e.id, n.name, s.name AS status, e.retry_count, e.exception, e.created_at, e.updated_at
FROM system_events e
JOIN system_event_names n ON n.id = e.system_event_name_id
JOIN system_event_statuses s ON s.id = e.system_event_status_id
ORDER BY e.id DESC
LIMIT 20;
```

For the acceptance test, request one fresh OTP, retrieve the code from the inbox and complete login before it expires. The event should be gone from `system_events`. A `Failed` row means the email was not sent, and its `exception` column holds the redacted reason. SMTP acceptance still depends on the mail server's forwarding and spam handling.

Public DSNs are in application source (API project 24, worker project 28). Stacks explicitly set
`Sentry__Environment=qa` or `production`, even though QA uses the Production runtime. Current
pipelines need no private Sentry upload token. API `/health` checks database connectivity; a
delivered email separately verifies worker operation and migrations.
