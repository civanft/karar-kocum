#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "HATA: gitleaks kurulu değil. macOS: brew install gitleaks" >&2
  exit 2
fi

mode="${1:-history}"
case "$mode" in
  history)
    gitleaks git . --no-banner --redact=100
    ;;
  staged)
    gitleaks git . --staged --no-banner --redact=100
    ;;
  *)
    echo "Kullanım: $0 [history|staged]" >&2
    exit 2
    ;;
esac

echo "Secret taraması: PASS ($mode)"
