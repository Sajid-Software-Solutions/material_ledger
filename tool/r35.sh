#!/usr/bin/env bash
set -euo pipefail

# Canonical Yorks V1 R35 launcher. Keep every R35 define in this one place so
# Chrome, web release and Android release builds cannot drift into a mixed V7
# configuration. Legacy V7 flags are intentionally absent.

usage() {
  cat <<'USAGE'
Usage: ./tool/r35.sh <run|build-web|build-apk|build-ios|build-macos> [additional Flutter arguments]

Examples:
  cp tool/r35.env.example .r35.env
  # Edit .r35.env once with the explicit local/staging/production backend.
  ./tool/r35.sh run
  ./tool/r35.sh build-web
  ./tool/r35.sh build-ios --no-codesign
  ./tool/r35.sh build-macos
  R35_CONFIG_FILE=.r35.staging.env ./tool/r35.sh build-web
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 64
fi

command="$1"
shift

# Explicit process environment wins over an ignored operator file. This is
# essential for CI: a developer's local production-targeted .r35.env must not
# silently replace CI's harmless placeholder backend during a build.
operator_supabase_url="${SUPABASE_URL:-}"
operator_supabase_key="${SUPABASE_ANON_KEY:-}"
operator_r35_environment="${R35_ENVIRONMENT:-}"
operator_firebase_web_vapid_key="${FIREBASE_WEB_VAPID_KEY:-}"
operator_accounts_flag="${YORKS_V1_ACCOUNTS:-}"
operator_company_material_requests_flag="${YORKS_V1_COMPANY_MATERIAL_REQUESTS:-}"
operator_workforce_flag="${YORKS_V1_WORKFORCE:-}"
operator_analytics_flag="${YORKS_V1_ANALYTICS:-}"
operator_posthog_enabled="${POSTHOG_ENABLED:-}"
operator_posthog_project_token="${POSTHOG_PROJECT_TOKEN:-}"
operator_posthog_host="${POSTHOG_HOST:-}"
operator_posthog_environment="${POSTHOG_ENV:-}"
operator_posthog_debug="${POSTHOG_DEBUG:-}"

# Configuration is deliberately explicit. A missing file is acceptable only
# when CI/operator environment variables already provide the complete pair.
# Never add a shared remote URL/key as a fallback here.
r35_config_file="${R35_CONFIG_FILE:-.r35.env}"
if [[ -f "$r35_config_file" ]]; then
  # This is an operator-owned, ignored key=value file. Its values are passed
  # only as Flutter dart-defines and are never committed or printed.
  # shellcheck disable=SC1090
  source "$r35_config_file"
fi

supabase_url="${operator_supabase_url:-${SUPABASE_URL:-}}"
supabase_key="${operator_supabase_key:-${SUPABASE_ANON_KEY:-}}"
r35_environment="${operator_r35_environment:-${R35_ENVIRONMENT:-}}"
firebase_web_vapid_key="${operator_firebase_web_vapid_key:-${FIREBASE_WEB_VAPID_KEY:-}}"
accounts_flag="${operator_accounts_flag:-${YORKS_V1_ACCOUNTS:-false}}"
company_material_requests_flag="${operator_company_material_requests_flag:-${YORKS_V1_COMPANY_MATERIAL_REQUESTS:-false}}"
workforce_flag="${operator_workforce_flag:-${YORKS_V1_WORKFORCE:-false}}"
analytics_flag="${operator_analytics_flag:-${YORKS_V1_ANALYTICS:-false}}"
posthog_enabled="${operator_posthog_enabled:-${POSTHOG_ENABLED:-false}}"
posthog_project_token="${operator_posthog_project_token:-${POSTHOG_PROJECT_TOKEN:-}}"
posthog_host="${operator_posthog_host:-${POSTHOG_HOST:-https://us.i.posthog.com}}"
posthog_environment="${operator_posthog_environment:-${POSTHOG_ENV:-${r35_environment:-production}}}"
posthog_debug="${operator_posthog_debug:-${POSTHOG_DEBUG:-false}}"

# A developer's ignored production file must not silently enable Accounts in a
# CI build. An explicit process-level value still wins for a deliberate CI
# rollout rehearsal.
if [[ "$r35_environment" == "ci" && -z "$operator_accounts_flag" ]]; then
  accounts_flag=false
fi
if [[ "$r35_environment" == "ci" && -z "$operator_company_material_requests_flag" ]]; then
  company_material_requests_flag=false
fi
if [[ "$r35_environment" == "ci" && -z "$operator_workforce_flag" ]]; then
  workforce_flag=false
fi
if [[ "$r35_environment" == "ci" && -z "$operator_analytics_flag" ]]; then
  analytics_flag=false
fi
if [[ "$r35_environment" == "ci" ]]; then
  posthog_enabled=false
  posthog_project_token=""
  posthog_environment=ci
  posthog_debug=false
fi

if [[ -z "$r35_environment" ]]; then
  echo "R35_ENVIRONMENT must be local, staging, production, or ci." >&2
  exit 64
fi
case "$r35_environment" in
  local|staging|production|ci) ;;
  *)
    echo "R35_ENVIRONMENT must be local, staging, production, or ci." >&2
    exit 64
    ;;
esac
if [[ -z "$supabase_url" || -z "$supabase_key" ]]; then
  echo "Missing explicit Supabase configuration. Create .r35.env from" >&2
  echo "tool/r35.env.example or set SUPABASE_URL and SUPABASE_ANON_KEY." >&2
  exit 64
fi
case "$accounts_flag" in
  true|false) ;;
  *)
    echo "YORKS_V1_ACCOUNTS must be true or false." >&2
    exit 64
    ;;
esac
case "$company_material_requests_flag" in
  true|false) ;;
  *)
    echo "YORKS_V1_COMPANY_MATERIAL_REQUESTS must be true or false." >&2
    exit 64
    ;;
esac
case "$workforce_flag" in
  true|false) ;;
  *)
    echo "YORKS_V1_WORKFORCE must be true or false." >&2
    exit 64
    ;;
esac
case "$analytics_flag" in
  true|false) ;;
  *)
    echo "YORKS_V1_ANALYTICS must be true or false." >&2
    exit 64
    ;;
esac
case "$posthog_enabled" in
  true|false) ;;
  *)
    echo "POSTHOG_ENABLED must be true or false." >&2
    exit 64
    ;;
esac
case "$posthog_debug" in
  true|false) ;;
  *)
    echo "POSTHOG_DEBUG must be true or false." >&2
    exit 64
    ;;
esac
case "$posthog_environment" in
  local|development|staging|production|ci) ;;
  *)
    echo "POSTHOG_ENV must be local, development, staging, production, or ci." >&2
    exit 64
    ;;
esac
if [[ "$r35_environment" == "local" ]]; then
  if [[ "$posthog_environment" != "local" && "$posthog_environment" != "development" ]]; then
    echo "POSTHOG_ENV must match the local R35 environment." >&2
    exit 64
  fi
elif [[ "$posthog_environment" != "$r35_environment" ]]; then
  echo "POSTHOG_ENV must match R35_ENVIRONMENT." >&2
  exit 64
fi
if [[ "$posthog_debug" == "true" && "$r35_environment" != "local" ]]; then
  echo "POSTHOG_DEBUG may be enabled only for local development." >&2
  exit 64
fi
if [[ "$posthog_enabled" == "true" && -z "$posthog_project_token" ]]; then
  echo "POSTHOG_PROJECT_TOKEN is required when POSTHOG_ENABLED=true." >&2
  exit 64
fi
if [[ "$posthog_enabled" == "true" ]]; then
  if [[ ! "$posthog_project_token" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "POSTHOG_PROJECT_TOKEN contains unsupported characters." >&2
    exit 64
  fi
  if [[ ! "$posthog_host" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$ ]]; then
    echo "POSTHOG_HOST must be a simple HTTPS origin." >&2
    exit 64
  fi
else
  # Do not embed an unused environment token in a disabled artifact.
  posthog_project_token=""
fi
if [[ "$r35_environment" == "production"
   && ("$command" == "run" || "$command" == "build-web")
   && -z "$firebase_web_vapid_key" ]]; then
  echo "FIREBASE_WEB_VAPID_KEY is required for a production web build." >&2
  echo "Copy the public Web Push certificate key from Firebase Console" >&2
  echo "into the operator environment or ignored R35 config file." >&2
  exit 64
fi

# Source identity comes from this checkout, never an operator-supplied label.
# Keep application version/build semantics unchanged. Dirty includes untracked
# files, so an uncommitted candidate cannot masquerade as the clean revision.
r35_source_root="$(cd "$(dirname "$0")/.." && pwd)"
r35_release_id=unknown
if r35_revision="$(git -C "$r35_source_root" rev-parse --verify HEAD 2>/dev/null)"; then
  r35_release_id="$r35_revision"
  if [[ -n "$(git -C "$r35_source_root" status --porcelain --untracked-files=normal)" ]]; then
    r35_release_id="${r35_release_id}-dirty"
  fi
fi

r35_defines=(
  "--dart-define=YORKS_RELEASE_ID=${r35_release_id}"
  "--dart-define=SUPABASE_URL=${supabase_url}"
  "--dart-define=SUPABASE_ANON_KEY=${supabase_key}"
  "--dart-define=R35_ENVIRONMENT=${r35_environment}"
  "--dart-define=YORKS_WEB_PUSH_ORIGIN=${YORKS_WEB_PUSH_ORIGIN:-https://yorks-r35.vercel.app}"
  '--dart-define=YORKS_V1_FOUNDATION=true'
  '--dart-define=YORKS_V1_PROJECTS=true'
  '--dart-define=YORKS_V1_BOQ=true'
  '--dart-define=YORKS_V1_EXCEL=true'
  '--dart-define=YORKS_V1_REQUESTS=true'
  '--dart-define=YORKS_V1_ARRANGEMENT=true'
  '--dart-define=YORKS_V1_LOGISTICS=true'
  '--dart-define=YORKS_V1_RETURNS_DOCUMENTS=true'
  '--dart-define=YORKS_V1_DOCUMENTS=true'
  "--dart-define=YORKS_V1_ACCOUNTS=${accounts_flag}"
  "--dart-define=YORKS_V1_COMPANY_MATERIAL_REQUESTS=${company_material_requests_flag}"
  "--dart-define=YORKS_V1_WORKFORCE=${workforce_flag}"
  "--dart-define=YORKS_V1_ANALYTICS=${analytics_flag}"
  "--dart-define=POSTHOG_ENABLED=${posthog_enabled}"
  "--dart-define=POSTHOG_PROJECT_TOKEN=${posthog_project_token}"
  "--dart-define=POSTHOG_HOST=${posthog_host}"
  "--dart-define=POSTHOG_ENV=${posthog_environment}"
  "--dart-define=POSTHOG_DEBUG=${posthog_debug}"
  '--dart-define=YORKS_R38_TEAM_CHAT=true'
  '--dart-define=YORKS_R38_9_INVENTORY_SUPPLIERS=true'
  '--dart-define=use_arabic=true'
)

# This rollout state is safe to print and provides release evidence without
# exposing backend configuration, telemetry tokens or public-notification credentials.
echo "Yorks Accounts rollout: ${accounts_flag}" >&2
echo "Yorks Company Material Requests rollout: ${company_material_requests_flag}" >&2
echo "Yorks Workforce rollout: ${workforce_flag}" >&2
echo "Yorks Analytics rollout: ${analytics_flag}" >&2
echo "Yorks PostHog telemetry: ${posthog_enabled}" >&2

# The VAPID public key is not a secret, but it is environment-specific. It is
# mandatory for production browser commands and may be omitted by native or
# CI/local builds that do not exercise the browser Push API.
if [[ -n "$firebase_web_vapid_key" ]]; then
  r35_defines+=("--dart-define=FIREBASE_WEB_VAPID_KEY=${firebase_web_vapid_key}")
fi

case "$command" in
  run)
    exec flutter run -d chrome "${r35_defines[@]}" "$@"
    ;;
  build-web)
    # Flutter does not guarantee removal of unrelated files already present in
    # build/web. Refuse to package a directory containing deployment metadata
    # or dotenv files; start from `flutter clean` and rebuild instead.
    if [[ -e build/web/.env.local || -d build/web/.vercel ]]; then
      echo "Refusing a web build with stale build/web credentials or Vercel metadata." >&2
      echo "Run flutter clean, then rebuild from explicit R35 configuration." >&2
      exit 65
    fi
    flutter build web --release "${r35_defines[@]}" "$@"
    dart run tool/verify_startup_performance.dart build/web
    ;;
  build-apk)
    exec flutter build apk --release "${r35_defines[@]}" "$@"
    ;;
  build-ios)
    exec flutter build ios --release "${r35_defines[@]}" "$@"
    ;;
  build-macos)
    exec flutter build macos --release "${r35_defines[@]}" "$@"
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
