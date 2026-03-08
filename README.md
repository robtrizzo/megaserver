# megaserver

## Getting Started

### Tools required

- **Bash** (scripts use `set -euo pipefail`)
- **AWS CLI** (`aws`) – for ECR, ECS, EC2; must be configured
- **Docker** – for building and pushing the API image (build / build-deploy)
- **Terraform** (≥ 1.2) – for environment standup/teardown only (`scripts/env.sh`)
- **jq** – only for deploy steps (register task definition, update ECS service)

### Credentials

- **AWS**  
  - Standard AWS credentials (e.g. `~/.aws/credentials` or `AWS_SHARED_CREDENTIALS_FILE`).  

### Env file (required to run the API and for Docker build)

Create **`.env.local`** in the repo root. It is sourced by the scripts and passed into the Docker image as the app’s `.env` at runtime.

**Required for the docker build:**

- `CLERK_SECRET_KEY` – Clerk secret key (backend auth).

**Required for Terraform (scripts/env.sh standup/teardown):**

- `AWS_ACCOUNT_ID` – AWS account ID (used for assume_role in Terraform provider).

**Optional / useful:**

- `REGION` – AWS region (default `us-east-1`).
- `ENVIRONMENT` – e.g. `dev`, `prod` (default `dev`).
- `VITE_CLERK_PUBLISHABLE_KEY` – for frontend Clerk.
- `VITE_API_URL` – e.g. `http://localhost:4000/` for local frontend.

### Quick start

1. Install the tools above and configure AWS (credentials + assume role if needed).
2. Create `.env.local`.
3. Stand up the environment (once):  
   `./scripts/env.sh standup -e dev -v main`
4. Build and deploy the API:  
   `./scripts/ms.sh build-deploy`  
   (use `./scripts/ms.sh --help` for options.)
