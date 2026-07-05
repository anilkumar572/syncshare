#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEPLOY_TARGETS="${1:-hosting,firestore:rules}"
FIREBASE_BIN="./node_modules/.bin/firebase"
SA_FILE="${RUNNER_TEMP:-/tmp}/firebase-service-account.json"

if [[ ! -x "$FIREBASE_BIN" ]]; then
  echo "Installing firebase-tools..."
  npm install
fi

if [[ ! -f "build/web/index.html" ]]; then
  echo "Web build not found. Run:"
  echo "  flutter build web --release --no-wasm-dry-run"
  exit 1
fi

setup_service_account() {
  local sa_json=""

  if [[ -n "${FIREBASE_SERVICE_ACCOUNT:-}" ]]; then
    sa_json="$FIREBASE_SERVICE_ACCOUNT"
  elif [[ -n "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]]; then
    sa_json="$FIREBASE_SERVICE_ACCOUNT_JSON"
  elif [[ -n "${GOOGLE_APPLICATION_CREDENTIALS_JSON:-}" ]]; then
    sa_json="$GOOGLE_APPLICATION_CREDENTIALS_JSON"
  fi

  if [[ -n "$sa_json" ]]; then
    printf '%s' "$sa_json" > "$SA_FILE"
    export GOOGLE_APPLICATION_CREDENTIALS="$SA_FILE"
    echo "Using service account from environment secret."
    return 0
  fi

  if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    echo "Using service account file: $GOOGLE_APPLICATION_CREDENTIALS"
    return 0
  fi

  return 1
}

deploy() {
  echo "Deploying to Firebase ($DEPLOY_TARGETS)..."
  "$FIREBASE_BIN" deploy --only "$DEPLOY_TARGETS"
}

if setup_service_account; then
  deploy
  exit 0
fi

if [[ -n "${FIREBASE_TOKEN:-}" ]]; then
  echo "Deploying with FIREBASE_TOKEN..."
  "$FIREBASE_BIN" deploy --only "$DEPLOY_TARGETS" --token "$FIREBASE_TOKEN"
  exit 0
fi

if "$FIREBASE_BIN" projects:list >/dev/null 2>&1; then
  echo "Deploying with local Firebase login..."
  deploy
  exit 0
fi

cat <<'EOF'

Firebase authentication failed.

Use your service account JSON (recommended for GitHub Actions):

  GitHub secret name (any one of these):
    - FIREBASE_SERVICE_ACCOUNT
    - FIREBASE_SERVICE_ACCOUNT_JSON
    - GOOGLE_APPLICATION_CREDENTIALS_JSON

  Secret value: paste the FULL contents of your service account .json file

  Required roles on that service account:
    - Firebase Hosting Admin
    - Firebase Rules Admin (or Editor)

Local deploy with service account file:
  export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
  npm run deploy

Or paste JSON into env:
  export FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
  npm run deploy

Fallback options:
  npx firebase login && npm run deploy
  npx firebase login:ci && export FIREBASE_TOKEN="..." && npm run deploy

Live URL after deploy:
  https://sharesync-56711.web.app

EOF
exit 1
