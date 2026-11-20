#!/usr/bin/env bash
# =============================================================================
# Run the SAME checks as the GitHub Actions CI pipeline, locally, before pushing.
#
# Usage (inside WSL Ubuntu, from the project root):
#   bash scripts/ci-local.sh
#
# Uses the same tool versions as .github/workflows/ci.yml. Stops at the first failure.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

HADOLINT_IMAGE=hadolint/hadolint:v2.15.1
GITLEAKS_IMAGE=zricethezav/gitleaks:v8.30.1
TRIVY_IMAGE=aquasec/trivy:0.76.2
TRIVY="docker run --rm -v trivy-cache:/root/.cache/ -v /var/run/docker.sock:/var/run/docker.sock"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "1/8 Build test image"
docker build -q --target test -t taskapi:test app >/dev/null

step "2/8 ruff check + ruff format --check"
docker run --rm taskapi:test ruff check .
docker run --rm taskapi:test ruff format --check .

step "3/8 hadolint"
docker run --rm -i "$HADOLINT_IMAGE" < app/Dockerfile && echo "no findings"

step "4/8 gitleaks (git history)"
docker run --rm -v "$PWD:/repo" "$GITLEAKS_IMAGE" git /repo --no-banner --redact

step "5/8 Trivy dependency scan"
$TRIVY -v "$PWD:/src" "$TRIVY_IMAGE" fs --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 /src/app

step "6/8 Unit + integration tests (own throwaway database)"
docker compose run --rm tests
docker compose rm -sf test-db >/dev/null 2>&1

step "7/8 Build runtime image"
docker build -q -t taskapi:ci app >/dev/null && echo "built taskapi:ci"

step "8/8 Trivy image scan (fixable HIGH/CRITICAL)"
$TRIVY "$TRIVY_IMAGE" image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 taskapi:ci

printf '\n\033[1;32mAll CI checks passed locally.\033[0m\n'
