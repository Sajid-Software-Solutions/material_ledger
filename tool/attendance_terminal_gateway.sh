#!/usr/bin/env bash
# Builds the folder for the attendance terminals' own web address.
#
# A terminal can only be given a host name: it always calls /iclock/... at
# the root of that host. This folder is a tiny static site whose one rule
# passes /iclock/* to the `attendance-terminal` Edge Function of one Supabase
# project. It is deployed as its own Vercel project, apart from the Yorks web
# app, so the app's hosting is never touched and the terminals' address can
# stay the same if the app's address changes.
#
# Usage:
#   SUPABASE_URL=https://<project-ref>.supabase.co \
#     ./tool/attendance_terminal_gateway.sh [output-folder]
#
# It only writes the folder. Deploying it is a separate, deliberate step:
#   npx vercel deploy <output-folder> --prod
# See docs/yorks-v1/ATTENDANCE_TERMINALS.md.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${repo_root}/deploy/attendance-terminals"
output_dir="${1:-${repo_root}/build/attendance-terminal-gateway}"
supabase_url="${SUPABASE_URL:-}"

if [[ -z "${supabase_url}" ]]; then
  echo "SUPABASE_URL is required, for example https://abcdefghijklmnopqrst.supabase.co" >&2
  exit 64
fi
supabase_url="${supabase_url%/}"
if [[ ! "${supabase_url}" =~ ^https://[a-z0-9]{20}\.supabase\.co$ ]]; then
  echo "SUPABASE_URL must be a Supabase project address: https://<20 letters or digits>.supabase.co" >&2
  exit 64
fi

mkdir -p "${output_dir}"
sed "s|__SUPABASE_URL__|${supabase_url}|g" \
  "${source_dir}/vercel.template.json" > "${output_dir}/vercel.json"
cp "${source_dir}/index.html" "${output_dir}/index.html"

if grep -q "__SUPABASE_URL__" "${output_dir}/vercel.json"; then
  echo "The gateway rule was not filled in." >&2
  exit 70
fi

echo "Terminal gateway written to ${output_dir}"
echo "It passes /iclock/* to ${supabase_url}/functions/v1/attendance-terminal"
