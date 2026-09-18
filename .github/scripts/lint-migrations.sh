#!/usr/bin/env bash
# Gate CI: numerazione migrazioni strettamente crescente + piano di rollback nel commento di testa.
# Vedi CLAUDE.md §14 e §4.
set -euo pipefail

migrations_dir="supabase/migrations"
prev=-1
status=0

if [ ! -d "$migrations_dir" ]; then
  echo "Nessuna directory $migrations_dir trovata, salto il controllo."
  exit 0
fi

shopt -s nullglob
for file in "$migrations_dir"/*.sql; do
  base="$(basename "$file")"

  if [[ ! "$base" =~ ^([0-9]{4})_[a-z0-9_]+\.sql$ ]]; then
    echo "::error file=$file::Nome migrazione non conforme a NNNN_nome_descrittivo.sql"
    status=1
    continue
  fi

  num="${BASH_REMATCH[1]}"
  num_int=$((10#$num))
  if [ "$num_int" -le "$prev" ]; then
    echo "::error file=$file::Numerazione non strettamente crescente (atteso > $prev, trovato $num_int)"
    status=1
  fi
  prev="$num_int"

  if ! head -n 10 "$file" | grep -qi "rollback"; then
    echo "::error file=$file::Manca il piano di rollback nel commento di testa"
    status=1
  fi
done

exit $status
