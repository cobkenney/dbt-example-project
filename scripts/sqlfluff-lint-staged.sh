#!/usr/bin/env bash
# Lint staged dbt model SQL with sqlfluff.
#
# Runs as a *local* pre-commit hook rather than the upstream sqlfluff repo hook,
# because the dbt templater has to compile the project to resolve {{ ref() }}
# and {{ dbt_utils.* }} — which needs this repo's venv and Snowflake
# credentials. pre-commit's isolated hook environments have neither.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sqlfluff="$repo_root/.venv/bin/sqlfluff"
env_file="$repo_root/.env"

if [[ ! -x "$sqlfluff" ]]; then
    echo "sqlfluff not found at $sqlfluff" >&2
    echo "Run: .venv/bin/pip install -r requirements.txt" >&2
    exit 1
fi

# The dbt templater connects to Snowflake to resolve the project, so
# profiles.yml's env_var() references must be populated.
if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
else
    echo "No .env at $env_file — copy .env.example and fill it in." >&2
    exit 1
fi

# Paths arrive repo-relative; sqlfluff must run from the dbt project dir so it
# picks up .sqlfluff and resolves project_dir correctly.
staged=()
for path in "$@"; do
    staged+=("${path#dbt/}")
done

if [[ ${#staged[@]} -eq 0 ]]; then
    exit 0
fi

cd "$repo_root/dbt"
exec "$sqlfluff" lint "${staged[@]}"
