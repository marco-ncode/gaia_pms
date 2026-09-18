#!/usr/bin/env bash
# Gate CI: service_role non deve mai comparire nel codice client (apps/*) ne' con prefisso
# NEXT_PUBLIC_/VITE_. Vedi CLAUDE.md regola d'oro #3.
set -euo pipefail

if grep -rniE "service_role|NEXT_PUBLIC_.*SERVICE|VITE_.*SERVICE" \
    --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    apps/ 2>/dev/null; then
  echo "::error::Trovato riferimento a service_role (o env pubblica sospetta) in apps/*"
  exit 1
fi

echo "OK: nessun riferimento a service_role in apps/*"
