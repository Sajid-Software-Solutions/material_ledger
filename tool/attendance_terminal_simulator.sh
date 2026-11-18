#!/usr/bin/env bash
# Plays the part of a ZKTeco attendance terminal against the Yorks receiver,
# so the whole path can be tried before a real terminal exists: the address,
# the Edge Function and the database.
#
# It does one of three things:
#
#   (nothing extra)  Check the path: every kind of call a terminal makes, and
#                    the answer each one should get.
#   --check-in       One punch as one labourer, now. --check-out is the same
#   --check-out      for leaving. --at "2026-11-18 06:31:05" sets the time.
#   --day            A whole working day for a group of labourers: arrivals,
#                    a few late, departures, a few staying late or leaving
#                    early, someone who forgets to check out, a double punch,
#                    and one upload sent twice.
#
# Usage:
#   ./tool/attendance_terminal_simulator.sh --base-url <address> --serial SIM-0001
#   ./tool/attendance_terminal_simulator.sh --base-url <address> --serial SIM-0001 --check-in --pin 418
#   ./tool/attendance_terminal_simulator.sh --base-url <address> --serial SIM-0001 --day --pins 1-40
#
#   --base-url   Where a terminal would call, without /iclock. Staging:
#                https://yorks-terminals-staging.vercel.app
#   --serial     A serial number registered in Yorks for the simulator. It
#                must start with SIM- unless --allow-real-serial is given.
#   --pin        The terminal user ID to punch as: the digits of the worker
#                number, so WR-000418 is 418 (default 999001, nobody).
#   --pins       For --day: the user IDs, as a list and ranges, "1-40" or
#                "3,7,12-20" (default 1-20).
#   --date       For --day: the day to play, YYYY-MM-DD (default yesterday).
#                Today is allowed; punches later than now are left out.
#   --shift      For --day: the usual shift, HH:MM-HH:MM (default 06:30-14:30).
#   --seed       For --day: the same seed plays the same day again (default 1).
#   --zone       The terminal's time zone (default Asia/Dubai).
#   --dry-run    Print what would be sent and call nothing.
#   --live       Needed for an address that is not staging or a local stack.
#   --skip-refusals  When checking the path, do not try an unregistered serial.
#
# Every punch is kept for good: the punch log is append-only. Use staging,
# and register the simulator as its own terminal:
#   select public.v1_wf_register_terminal('SIM-0001', 'Simulator');
set -euo pipefail

base_url=""
serial=""
pin="999001"
pins="1-20"
zone="Asia/Dubai"
mode="check"
punch_state="0"
punch_at=""
day_date=""
shift_spec="06:30-14:30"
seed="1"
dry_run="false"
live="false"
allow_real_serial="false"
skip_refusals="false"

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) base_url="${2:-}"; shift 2 ;;
    --serial) serial="${2:-}"; shift 2 ;;
    --pin) pin="${2:-}"; shift 2 ;;
    --pins) pins="${2:-}"; shift 2 ;;
    --zone) zone="${2:-}"; shift 2 ;;
    --check-in) mode="punch"; punch_state="0"; shift ;;
    --check-out) mode="punch"; punch_state="1"; shift ;;
    --at) punch_at="${2:-}"; shift 2 ;;
    --day) mode="day"; shift ;;
    --date) day_date="${2:-}"; shift 2 ;;
    --shift) shift_spec="${2:-}"; shift 2 ;;
    --seed) seed="${2:-}"; shift 2 ;;
    --dry-run) dry_run="true"; shift ;;
    --live) live="true"; shift ;;
    --allow-real-serial) allow_real_serial="true"; shift ;;
    --skip-refusals) skip_refusals="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

fail_usage() {
  echo "$1" >&2
  exit 64
}

[[ -n "${serial}" ]] || fail_usage "--serial is required. See --help."
[[ "${serial}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{3,39}$ ]] \
  || fail_usage "--serial is not a serial number."
if [[ "${allow_real_serial}" != "true" && ! "${serial}" =~ ^[Ss][Ii][Mm]- ]]; then
  echo "--serial must start with SIM- so test punches never land under a real terminal." >&2
  echo "Pass --allow-real-serial only if you mean it." >&2
  exit 64
fi
[[ "${pin}" =~ ^[0-9]{1,9}$ ]] && (( 10#${pin} > 0 )) \
  || fail_usage "--pin must be a number above zero, of up to nine digits."
[[ "${seed}" =~ ^[0-9]{1,5}$ ]] || fail_usage "--seed must be a number up to 99999."

if [[ "${dry_run}" != "true" ]]; then
  [[ -n "${base_url}" ]] || fail_usage "--base-url is required. See --help."
  base_url="${base_url%/}"
  case "${base_url}" in
    *staging*|http://127.0.0.1*|http://localhost*) ;;
    *)
      if [[ "${live}" != "true" ]]; then
        echo "This address does not look like staging or a local stack." >&2
        echo "Every punch is kept for good. Add --live to send anyway." >&2
        exit 64
      fi
      ;;
  esac
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

# upload <label> <file of attendance lines> <stamp>: sends them as one upload
# and expects every line acknowledged.
upload() {
  local label="$1" file="$2" stamp="$3"
  local count
  count="$(grep -c '' "${file}" || true)"
  if [[ "${dry_run}" == "true" ]]; then
    printf -- '-- %s (%s line(s))\n' "${label}" "${count}"
    cat "${file}"
    return 0
  fi
  call "${label}" POST \
    "/iclock/cdata?SN=${serial}&table=ATTLOG&Stamp=${stamp}" \
    200 "^OK: ${count}\$" "${file}"
}

finish() {
  if [[ "${dry_run}" == "true" ]]; then
    echo
    echo "Dry run: nothing was sent."
    exit 0
  fi
  echo
  echo "${passed} passed, ${failed} failed."
  if [[ "${failed}" -gt 0 ]]; then
    echo "See docs/yorks-v1/ATTENDANCE_TERMINALS.md, \"When a check fails\"." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# One punch as one labourer.
# ---------------------------------------------------------------------------
run_punch() {
  local when="${punch_at:-$(local_time 0)}"
  [[ "${when}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] \
    || fail_usage "--at must look like \"2026-11-18 06:31:05\"."
  local what="check-in"
  [[ "${punch_state}" == "1" ]] && what="check-out"
  echo "Terminal ${serial}: ${what} as user ${pin} at ${when} (${zone})"
  echo
  printf '%s\t%s\t%s\t15\t0\t0\n' "${pin}" "${when}" "${punch_state}" \
    > "${work_dir}/punch"
  upload "${what} as user ${pin}" "${work_dir}/punch" "$(date +%s)"
  finish
  echo "Stored once. Sending the same punch again changes nothing."
}

# ---------------------------------------------------------------------------
# A whole working day for a group of labourers.
# ---------------------------------------------------------------------------

# "1-5,9" as one user ID per line. Fails on anything that is not a list.
expand_pins() {
  local spec="$1" part from to n
  local old_ifs="${IFS}"
  IFS=','
  # shellcheck disable=SC2086
  set -- ${spec}
  IFS="${old_ifs}"
  [[ $# -gt 0 ]] || return 1
  for part in "$@"; do
    if [[ "${part}" =~ ^([0-9]{1,9})-([0-9]{1,9})$ ]]; then
      from=$(( 10#${BASH_REMATCH[1]} ))
      to=$(( 10#${BASH_REMATCH[2]} ))
      (( from > 0 && to >= from && to - from < 2000 )) || return 1
      for (( n = from; n <= to; n++ )); do echo "${n}"; done
    elif [[ "${part}" =~ ^[0-9]{1,9}$ ]]; then
      (( 10#${part} > 0 )) || return 1
      echo $(( 10#${part} ))
    else
      return 1
    fi
  done
}

# Minutes since midnight and a second, as HH:MM:SS.
clock() {
  printf '%02d:%02d:%02d' $(( $1 / 60 )) $(( $1 % 60 )) "$2"
}

# Whether YYYY-MM-DD is a day that exists (30 February is not).
real_date() {
  local same
  same="$(date -j -f '%Y-%m-%d' "$1" '+%Y-%m-%d' 2>/dev/null \
    || date -d "$1" '+%Y-%m-%d' 2>/dev/null)" || return 1
  [[ "${same}" == "$1" ]]
}

run_day() {
  [[ "${shift_spec}" =~ ^([0-9]{2}):([0-9]{2})-([0-9]{2}):([0-9]{2})$ ]] \
    || fail_usage "--shift must look like 06:30-14:30."
  local start=$(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
  local end=$(( 10#${BASH_REMATCH[3]} * 60 + 10#${BASH_REMATCH[4]} ))
  (( start >= 60 && end <= 1200 && end - start >= 240 )) \
    || fail_usage "--shift must start at 01:00 or later, end by 20:00 and last four hours or more."

  local now today
  now="$(local_time 0)"
  today="${now%% *}"
  if [[ -z "${day_date}" ]]; then
    day_date="$(local_time -86400)"
    day_date="${day_date%% *}"
  fi
  [[ "${day_date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && real_date "${day_date}" \
    || fail_usage "--date must be a real date such as 2026-11-17."
  [[ ! "${day_date}" > "${today}" ]] \
    || fail_usage "--date is in the future. A terminal cannot punch tomorrow."

  expand_pins "${pins}" | sort -n -u > "${work_dir}/pins" \
    || fail_usage "--pins must be a list such as 1-40 or 3,7,12-20."
  local people
  people="$(grep -c '' "${work_dir}/pins" || true)"
  (( people > 0 )) || fail_usage "--pins must be a list such as 1-40 or 3,7,12-20."

  # The same seed plays the same day.
  RANDOM="${seed}"
  local came=0 absent=0 late=0 stayed=0 early=0 no_out=0 doubles=0
  local id roll in_min out_min verify second
  : > "${work_dir}/arrivals"
  : > "${work_dir}/departures"
  while read -r id; do
    roll=$(( RANDOM % 100 ))
    if (( roll < 4 )); then
      absent=$((absent + 1))
      continue
    fi
    came=$((came + 1))

    roll=$(( RANDOM % 100 ))
    if (( roll < 10 )); then
      in_min=$(( start + 16 + RANDOM % 45 ))
      late=$((late + 1))
    else
      in_min=$(( start - 20 + RANDOM % 31 ))
    fi
    verify=15
    roll=$(( RANDOM % 10 ))
    (( roll == 0 )) && verify=1
    # Every draw happens here, not inside $(...), so a seed replays the day.
    second=$(( RANDOM % 60 ))
    printf '%s|%s\t%s %s\t0\t%s\t0\t0\n' \
      "$(clock "${in_min}" "${second}")" "${id}" \
      "${day_date}" "$(clock "${in_min}" "${second}")" "${verify}" \
      >> "${work_dir}/arrivals"
    roll=$(( RANDOM % 100 ))
    if (( roll < 5 )); then
      # Punched twice to be sure, within the next minute.
      doubles=$((doubles + 1))
      second=$(( RANDOM % 20 ))
      printf '%s|%s\t%s %s\t0\t%s\t0\t0\n' \
        "$(clock $(( in_min + 1 )) "${second}")" \
        "${id}" "${day_date}" "$(clock $(( in_min + 1 )) "${second}")" \
        "${verify}" >> "${work_dir}/arrivals"
    fi

    roll=$(( RANDOM % 100 ))
    if (( roll < 5 )); then
      no_out=$((no_out + 1))
      continue
    elif (( roll < 10 )); then
      out_min=$(( end - 30 - RANDOM % 151 ))
      early=$((early + 1))
    elif (( roll < 25 )); then
      out_min=$(( end + 61 + RANDOM % 120 ))
      stayed=$((stayed + 1))
    else
      out_min=$(( end - 5 + RANDOM % 21 ))
    fi
    if (( out_min <= in_min + 2 )); then
      out_min=$(( in_min + 30 ))
    fi
    second=$(( RANDOM % 60 ))
    printf '%s|%s\t%s %s\t1\t%s\t0\t0\n' \
      "$(clock "${out_min}" "${second}")" "${id}" \
      "${day_date}" "$(clock "${out_min}" "${second}")" "${verify}" \
      >> "${work_dir}/departures"
  done < "${work_dir}/pins"

  # In time order, as a terminal holds them. On today's date nothing later
  # than now is sent: a terminal cannot punch in the future.
  local part left_out=0 total=0
  for part in arrivals departures; do
    sort "${work_dir}/${part}" | cut -d'|' -f2- > "${work_dir}/${part}.all"
    awk -F'\t' -v now="${now}" '$2 <= now' "${work_dir}/${part}.all" \
      > "${work_dir}/${part}.lines"
    left_out=$(( left_out
      + $(grep -c '' "${work_dir}/${part}.all" || true)
      - $(grep -c '' "${work_dir}/${part}.lines" || true) ))
    total=$(( total + $(grep -c '' "${work_dir}/${part}.lines" || true) ))
  done

  echo "Terminal ${serial}: ${day_date}, shift ${shift_spec}, ${people} labourer(s), seed ${seed}"
  echo

  local stamp chunk index first_chunk=""
  stamp="$(date +%s)"
  for part in arrivals departures; do
    [[ -s "${work_dir}/${part}.lines" ]] || continue
    split -l 25 "${work_dir}/${part}.lines" "${work_dir}/${part}.chunk."
    index=0
    for chunk in "${work_dir}/${part}.chunk."*; do
      index=$((index + 1))
      stamp=$((stamp + 1))
      [[ -n "${first_chunk}" ]] || first_chunk="${chunk}"
      upload "${part}, upload ${index}" "${chunk}" "${stamp}"
    done
  done
  if [[ -n "${first_chunk}" ]]; then
    upload "the first upload sent again" "${first_chunk}" "${stamp}"
  fi

  echo
  echo "The day played:"
  echo "  ${people} labourer(s): ${came} came, ${absent} did not"
  echo "  ${late} arrived more than 15 minutes late"
  echo "  ${stayed} stayed more than an hour late"
  echo "  ${early} left at least half an hour early"
  echo "  ${no_out} did not check out"
  echo "  ${doubles} punched twice on arriving"
  echo "  ${total} punch(es) sent, each stored once"
  if (( left_out > 0 )); then
    echo "  ${left_out} punch(es) later than now were left out"
  fi
  finish
}

# ---------------------------------------------------------------------------
# Check the path: every kind of call, and the answer each should get.
# ---------------------------------------------------------------------------
run_check() {
  [[ "${dry_run}" != "true" ]] \
    || fail_usage "--dry-run goes with --check-in, --check-out or --day."
  local now_stamp check_in
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

  finish
  echo "Sent as user ${pin}: 4 punches stored once each, 1 unread line kept."
}

case "${mode}" in
  punch) run_punch ;;
  day) run_day ;;
  *) run_check ;;
esac
