#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEPLOY_TARGETS="${1:-hosting,firestore:rules}"
FIREBASE_BIN="./node_modules/.bin/firebase"

if [[ ! -x "$FIREBASE_BIN" ]]; then
  echo "Installing firebase-tools..."
  npm install
fi

if [[ ! -f "build/web/index.html" ]]; then
  echo "Web build not found. Run:"
  echo "  flutter build web --release --no-wasm-dry-run"
  exit 1
fi

deploy_with_token() {
  echo "Deploying with FIREBASE_TOKEN..."
  "$FIREBASE_BIN" deploy --only "$DEPLOY_TARGETS" --token "$FIREBASE_TOKEN"
}

deploy_interactive() {
  echo "Deploying with local Firebase login..."
  "$FIREBASE_BIN" deploy --only "$DEPLOY_TARGETS"
}

if [[ -n "${FIREBASE_TOKEN:-}" ]]; then
  deploy_with_token
  exit 0
fi

if "$FIREBASE_BIN" projects:list >/dev/null 2>&1; then
  deploy_interactive
  exit 0
fi

cat <<'EOF'

Firebase authentication failed.

The "npm fund" message is harmless. The real issue is Firebase CLI is not logged in.

Choose ONE option:

Option A — Login on this machine (interactive)
  npx firebase login
  npm run deploy

Option B — Use a CI token (works in scripts / GitHub Actions)
  npx firebase login:ci
  export FIREBASE_TOKEN="paste-token-here"
  npm run deploy

Option C — Deploy rules only from Firebase Console
  https://console.firebase.google.com/project/sharesync-56711/firestore/rules
  Paste the contents of firestore.rules and publish.

After a successful deploy, your app will be live at:
  https://sharesync-56711.web.app

EOF
exit 1
