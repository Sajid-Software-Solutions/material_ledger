#!/usr/bin/env bash
# Replays what a ZKTeco attendance terminal sends, against the Yorks
# receiver, and checks every answer. Use it to prove the whole path before a
# real terminal is plugged in: the address, the Edge Function and the
# database.
#
# Usage:
#   ./tool/attendance_terminal_simulator.sh \
#     --base-url https://<terminals address> --serial SIM-0001 [--pin 999001]
#
#   --base-url   Where a terminal would call, without /iclock. For a local
#                stack: http://127.0.0.1:<api port>/functions/v1/attendance-terminal
#   --serial     A serial number registered in Yorks for the simulator. It
#                must start with SIM- unless --allow-real-serial is given.
#   --pin        The terminal user ID to punch as (default 999001).
#   --zone       The terminal's time zone (default Asia/Dubai).
#   --skip-refusals  Do not try an unregistered serial number.
#
# Punches are kept for good: the punch log is append-only. Register the
# simulator as its own terminal with no place, so nothing it sends can ever
# count as attendance:
#   select public.v1_wf_register_terminal('SIM-0001', 'Simulator');
set -euo pipefail

base_url=""
serial=""
pin="999001"
zone="Asia/Dubai"
allow_real_serial="false"
skip_refusals="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) base_url="${2:-}"; shift 2 ;;
    --serial) serial="${2:-}"; shift 2 ;;
    --pin) pin="${2:-}"; shift 2 ;;
    --zone) zone="${2:-}"; shift 2 ;;
    --allow-real-serial) allow_real_serial="true"; shift ;;
    --skip-refusals) skip_refusals="true"; shift ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "${base_url}" || -z "${serial}" ]]; then
  echo "--base-url and --serial are required. See --help." >&2
  exit 64
fi
base_url="${base_url%/}"
if [[ ! "${serial}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{3,39}$ ]]; then
  echo "--serial is not a serial number." >&2
  exit 64
fi
if [[ "${allow_real_serial}" != "true" && ! "${serial}" =~ ^[Ss][Ii][Mm]- ]]; then
  echo "--serial must start with SIM- so test punches never land under a real terminal." >&2
  echo "Pass --allow-real-serial only if you mean it." >&2
  exit 64
fi
if [[ ! "${pin}" =~ ^[0-9]{1,9}$ ]]; then
  echo "--pin must be a number of up to nine digits." >&2
  exit 64
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
passed=0
failed=0

# The terminal's clock, shifted by a number of seconds from now.
local_time() {
  local epoch=$(( $(date +%s) + $1 ))
  TZ="${zone}" date -r "${epoch}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || TZ="${zone}" date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S"
}

# call <label> <method> <path and query> <expected status> <expected body pattern> [body file]
call() {
  local label="$1" method="$2" path="$3" want_status="$4" want_body="$5"
  local body_file="${6:-}"
  local out="${work_dir}/response"
  local status
  if [[ -n "${body_file}" ]]; then
    status="$(curl -sS --max-time 30 -o "${out}" -w '%{http_code}' \
      -X "${method}" -H 'Content-Type: text/plain' \
      --data-binary "@${body_file}" "${base_url}${path}")" || status="000"
  else
    status="$(curl -sS --max-time 30 -o "${out}" -w '%{http_code}' \
      -X "${method}" "${base_url}${path}")" || status="000"
  fi
  local first_line
  first_line="$(head -n 1 "${out}" 2>/dev/null | tr -d '\r' || true)"
  if [[ "${status}" == "${want_status}" ]] \
    && grep -q -E "${want_body}" "${out}" 2>/dev/null; then
    passed=$((passed + 1))
    printf 'PASS  %-46s %s  %s\n' "${label}" "${status}" "${first_line}"
  else
    failed=$((failed + 1))
    printf 'FAIL  %-46s %s  %s  (wanted %s matching %s)\n' \
      "${label}" "${status}" "${first_line}" "${want_status}" "${want_body}"
  fi
}

now_stamp="$(date +%s)"
check_in="$(local_time 0)"

echo "Terminal ${serial} calling ${base_url} as user ${pin}"
echo

call "handshake" GET \
  "/iclock/cdata?SN=${serial}&options=all&pushver=2.4.1&language=69" \
  200 "^GET OPTION FROM: "
if [[ -s "${work_dir}/response" ]]; then
  sed 's/^/      /' "${work_dir}/response"
fi

printf '~DeviceName=Yorks simulator,FWVersion=Ver 0.0.0-simulator\n' \
  > "${work_dir}/options"
call "its own options" POST "/iclock/cdata?SN=${serial}&table=options" \
  200 "^OK" "${work_dir}/options"

printf '%s\t%s\t0\t15\t0\t0\n' "${pin}" "${check_in}" > "${work_dir}/one"
call "one check-in" POST \
  "/iclock/cdata?SN=${serial}&table=ATTLOG&Stamp=${now_stamp}" \
  200 "^OK: 1$" "${work_dir}/one"
call "the same check-in sent again" POST \
  "/iclock/cdata?SN=${serial}&table=ATTLOG&Stamp=${now_stamp}" \
  200 "^OK: 1$" "${work_dir}/one"

{
  printf '%s\t%s\t0\t15\t0\t0\r\n' "${pin}" "$(local_time -180)"
  printf '%s\t%s\t255\t1\t0\t0\r\n' "${pin}" "$(local_time -120)"
  printf '%s\t%s\t1\t15\t0\t0\r\n' "${pin}" "$(local_time -60)"
} > "${work_dir}/batch"
call "three punches held during an outage" POST \
  "/iclock/cdata?SN=${serial}&table=ATTLOG&Stamp=$((now_stamp + 1))" \
  200 "^OK: 3$" "${work_dir}/batch"

printf 'this is not an attendance line\n' > "${work_dir}/garbage"
call "a line that cannot be read (kept)" POST \
  "/iclock/cdata?SN=${serial}&table=ATTLOG&Stamp=$((now_stamp + 2))" \
  200 "^OK: 1$" "${work_dir}/garbage"

{
  printf 'USER PIN=%s\tName=Simulated Person\tPri=0\tPasswd=\tCard=\n' "${pin}"
  printf 'FP PIN=%s\tFID=0\tSize=24\tValid=1\tTMP=SIMULATEDTEMPLATEDATA\n' "${pin}"
} > "${work_dir}/operlog"
call "a name and a fingerprint (dropped)" POST \
  "/iclock/cdata?SN=${serial}&table=OPERLOG&Stamp=1" \
  200 "^OK$" "${work_dir}/operlog"

call "asking for instructions" GET \
  "/iclock/getrequest?SN=${serial}&INFO=Ver%200.0.0-simulator,1,0,5,127.0.0.1" \
  200 "^OK$"
call "ping" GET "/iclock/ping?SN=${serial}" 200 "^OK$"
: > "${work_dir}/empty"
printf 'ID=1&Return=0&CMD=INFO\n' > "${work_dir}/result"
call "a command result" POST "/iclock/devicecmd?SN=${serial}" \
  200 "^OK$" "${work_dir}/result"
call "an endpoint Yorks does not speak" POST \
  "/iclock/registry?SN=${serial}" 404 "." "${work_dir}/empty"
call "a call without a serial number" GET "/iclock/cdata?options=all" \
  400 "^ERROR$"

if [[ "${skip_refusals}" != "true" ]]; then
  call "an unregistered terminal" GET \
    "/iclock/cdata?SN=${serial}-UNREGISTERED&options=all" 403 "^ERROR$"
  printf '%s\t%s\t0\t15\t0\t0\n' "${pin}" "${check_in}" > "${work_dir}/refused"
  call "its punches are not taken" POST \
    "/iclock/cdata?SN=${serial}-UNREGISTERED&table=ATTLOG&Stamp=1" \
    403 "^ERROR$" "${work_dir}/refused"
fi

echo
echo "${passed} passed, ${failed} failed."
if [[ "${failed}" -gt 0 ]]; then
  echo "See docs/yorks-v1/ATTENDANCE_TERMINALS.md, \"When a check fails\"." >&2
  exit 1
fi
echo "Sent as user ${pin}: 4 punches stored once each, 1 unread line kept."
