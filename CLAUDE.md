# CLAUDE.md

Guidance for Claude Code in this repository.

## What this repository is

GitOps configuration for MyLogbook. It contains Docker Compose stacks, image tags and encrypted secrets for QA and production. It contains no application code and must not contain decrypted secrets.

Application source is in the sibling `MyLogbook` repository. Images are built by the Azure Pipelines in that repository and published to `docker.spoyla.com/devops-mylogbook-*`.

## Git

Do not run git commands unless the user explicitly asks for that exact operation in their current message. The user stages and commits their own work unless they ask for a commit or push.

## Secrets workflow

Secrets live in `secrets/{qa,prod,release}/*.env` (plaintext, git-ignored) and `secrets/{qa,prod,release}/*.env.enc` (encrypted, committed). The key is `secrets/mylogbook.key` (git-ignored).

```powershell
./scripts/decrypt-secrets.ps1
./scripts/encrypt-secrets.ps1
```

Never commit a decrypted `.env`, the key, an SMTP password, a real connection string or a social-login secret.

## Stacks

- QA: `stacks/qa/{api,workerservice,pwa,marketing}`
- Production: `stacks/production/{api,workerservice,pwa,marketing}`
- Release database: `stacks/release/db`

Each application stack directory has a `.env` containing only its image tag. The API stack reads variables from `secrets/<env>/api.env` and the worker stack from `secrets/<env>/workerservice.env`. SMTP settings belong only in `workerservice.env`; the API never sends email.

Deploy the email worker with `./scripts/deploy-workerservice.ps1 -Environment qa` or `-Environment prod` after database migrations. Its preflight requires configured SMTP for every deployment. `-ValidateOnly` checks configuration without deployment. The helper never prints resolved configuration or credentials. The worker reads `secrets/<env>/workerservice.env`, shares the API's database and needs no token secret. Email workers never retry, so a failed send is marked `Failed` in `system_events` and is not repeated. Email always uses SMTP, including local development; there is no disable setting or file delivery mode.

Database migrations are not part of the stacks. An Azure release pipeline runs the `MyLogbook.DbUp` build artifact against each database before the API is deployed.

## Commands

```bash
cd stacks/qa/api
docker compose --env-file .env --env-file ../../../secrets/qa/api.env up -d

cd stacks/release/db
docker compose --env-file ../../../secrets/release/db.env up -d
```

Validate a stack without starting it:

```bash
docker compose --env-file .env --env-file ../../../secrets/qa/api.env config
```

## Conventions

- No comments in compose files, shell scripts or SQL.
- Keep host ports and image tags in `.env` files, not in the compose files.
- Keep the API, PWA and marketing site on the `mylogbook.co.za` registrable domain.
- Do not add a database container to an application stack.
- Do not edit an image tag on the host; change the committed `.env` file.
- The production marketing stack serves the apex and `www` hostnames. The QA host is noindex.
