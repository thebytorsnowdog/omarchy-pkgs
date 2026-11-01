#!/bin/bash
# Jobs that hold a signing key, a bucket credential, or the Basecamp webhook
# declare token scopes in the workflow file. The repository default is not
# the record of that limit.
set -euo pipefail
ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
failures=0
for workflow in "$ROOT"/.github/workflows/*.yml; do
  if grep -qE 'secrets\.(GPG_PRIVATE_KEY|GPG_PASSPHRASE|R2_ACCESS_KEY_ID|R2_SECRET_ACCESS_KEY|R2_ENDPOINT|BASECAMP_CHATBOT_URL)' "$workflow"; then
    if grep -q '^permissions:\|^    permissions:' "$workflow"; then
      echo "PASS: $(basename "$workflow") declares permissions"
    else
      echo "FAIL: $(basename "$workflow") uses a secret and does not declare permissions"
      failures=1
    fi
  fi
done
# test.yml runs scripts from the pull request. Its token is contents: read.
if grep -q '^permissions:' "$ROOT/.github/workflows/test.yml" && grep -q 'contents: read' "$ROOT/.github/workflows/test.yml"; then
  echo "PASS: test.yml pins contents: read"
else
  echo "FAIL: test.yml does not pin contents: read"
  failures=1
fi
exit "$failures"
