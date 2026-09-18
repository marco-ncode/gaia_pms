#!/usr/bin/env bash
# Gate CI: ogni blocco `create policy` nelle migrazioni deve referenziare auth.uid(),
# auth.jwt() o auth.role() (direttamente o via gli helper in private.*).
# Vedi CLAUDE.md §14 e §6.4.
set -euo pipefail

status=0
shopt -s nullglob

for file in supabase/migrations/*.sql; do
  awk '
    BEGIN { in_policy = 0; block = ""; }
    /create policy/ { in_policy = 1; block = ""; }
    {
      if (in_policy) block = block "\n" $0;
      if (in_policy && $0 ~ /;[[:space:]]*$/) {
        if (block !~ /auth\.(uid|jwt|role)\(\)/ && block !~ /private\.(current_tenant_id|has_tenant_role|has_property_access)/) {
          print FILENAME ": blocco create policy senza riferimento ad auth.*() o private.has_*";
          found = 1;
        }
        in_policy = 0;
      }
    }
    END { if (found) exit 1; }
  ' "$file" || status=1
done

exit $status
