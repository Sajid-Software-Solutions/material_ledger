// The ZKTeco attendance push protocol, as far as Yorks speaks it.
//
// A terminal calls the server; the server never calls the terminal. Every
// call names the terminal by serial number (SN) under a path ending in
// /iclock/<endpoint>:
//
//   GET  /iclock/cdata?SN=..&options=all      handshake: "how should I behave?"
//   POST /iclock/cdata?SN=..&table=ATTLOG     check-ins and check-outs
//   POST /iclock/cdata?SN=..&table=<other>    data Yorks does not keep
//   GET  /iclock/getrequest?SN=..             "any instructions?"
//   POST /iclock/devicecmd?SN=..              the result of an instruction
//   GET  /iclock/ping?SN=..                   "are you there?"
//
// Everything here is a pure function: no network and no database.

/** A request body larger than this is refused unread. */
export const MAX_BODY_BYTES = 4 * 1024 * 1024;

/** The most attendance lines one call may carry (the database refuses more). */
export const MAX_LINES = 50_000;

/** A raw line is sent on up to this length; the database keeps 300. */
const RAW_LINE_LIMIT = 400;

export type TerminalRoute =
  | { endpoint: "handshake" }
  | { endpoint: "punches" }
  | { endpoint: "data"; table: string }
  | { endpoint: "poll" }
  | { endpoint: "command_result" }
  | { endpoint: "ping" }
  | { endpoint: "other"; name: string };

/** One attendance line, split into its fields and kept as it arrived. */
export type AttendanceLine = {
  raw: string;
  pin: string | null;
  time: string | null;
  state: string | null;
  verify: string | null;
  work_code: string | null;
};

export type HandshakeOptions = {
  serialNumber: string;
  attlogStamp: string;
  pollSeconds: number;
  errorDelaySeconds: number;
  realtime: boolean;
  transTimes: string;
  transIntervalMinutes: number;
  transFlag: string;
  utcOffsetMinutes: number;
  extraOptionLines: string[];
};

const serialPattern = /^[A-Z0-9][A-Z0-9_-]{3,39}$/;

/** The serial number as Yorks stores it, or null when it is not one. */
export function serialNumber(raw: string | null | undefined): string | null {
  const value = (raw ?? "").trim().toUpperCase();
  return serialPattern.test(value) ? value : null;
}

/** A query value by name, whatever case the terminal used for the name. */
export function queryValue(
  params: URLSearchParams,
  name: string,
): string | null {
  const wanted = name.toLowerCase();
  for (const [key, value] of params) {
    if (key.toLowerCase() === wanted) return value;
  }
  return null;
}

/** The names of the query values, for the diagnostic log (never the values). */
export function queryKeys(params: URLSearchParams): string[] {
  const keys: string[] = [];
  for (const key of params.keys()) {
    if (/^[A-Za-z0-9_~.-]{1,32}$/.test(key) && !keys.includes(key)) {
      keys.push(key);
    }
    if (keys.length >= 24) break;
  }
  return keys;
}

/**
 * What a call is, from its method and path. Null when the path is not a
 * terminal path at all. The path may carry any prefix before /iclock/ (the
 * function's own name, for one).
 */
export function routeFor(
  method: string,
  pathname: string,
  params: URLSearchParams,
): TerminalRoute | null {
  const match = /\/iclock\/([^/?#]+)\/?$/i.exec(pathname);
  if (!match) return null;
  const name = match[1].toLowerCase();
  const post = method.toUpperCase() === "POST";
  switch (name) {
    case "cdata": {
      if (!post) return { endpoint: "handshake" };
      const table = (queryValue(params, "table") ?? "").trim();
      if (table.toUpperCase() === "ATTLOG") return { endpoint: "punches" };
      return {
        endpoint: "data",
        table: /^[A-Za-z0-9_]{1,32}$/.test(table) ? table : "unknown",
      };
    }
    case "getrequest":
      return { endpoint: "poll" };
    case "devicecmd":
      return { endpoint: "command_result" };
    case "ping":
      return { endpoint: "ping" };
    default:
      return {
        endpoint: "other",
        name: /^[a-z0-9_.-]{1,32}$/.test(name) ? name : "unknown",
      };
  }
}

/** The lines of a body, without blank ones. */
export function splitLines(body: string): string[] {
  return body.split(/\r\n|\r|\n/).filter((line) => line.trim() !== "");
}

const spacedLine =
  /^(\S+)\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\s+(\S+))?(?:\s+(\S+))?(?:\s+(\S+))?/;

/** One field of a line. Longer than any real value means it is not one. */
function field(value: string | undefined): string | null {
  const trimmed = (value ?? "").trim().slice(0, 64);
  return trimmed === "" ? null : trimmed;
}

/**
 * Attendance lines: user ID, time, state, verify mode and work code, tab
 * separated ("418\t2026-11-17 06:31:05\t0\t15\t0\t0"). A line this cannot
 * split still goes on with its raw text, so the database keeps it instead of
 * losing it.
 */
export function parseAttendanceLines(body: string): AttendanceLine[] {
  const lines: AttendanceLine[] = [];
  for (const line of splitLines(body)) {
    const raw = line.slice(0, RAW_LINE_LIMIT);
    let parts = line.split("\t");
    if (parts.length < 2) {
      const spaced = spacedLine.exec(line.trim());
      parts = spaced ? spaced.slice(1) : parts;
    }
    lines.push({
      raw,
      pin: field(parts[0]),
      time: field(parts[1]),
      state: field(parts[2]),
      verify: field(parts[3]),
      work_code: field(parts[4]),
    });
  }
  return lines;
}

/**
 * How many lines of each kind a body Yorks does not keep had ("USER", "FP",
 * "OPLOG"). Only the first word of a line is read; nothing else leaves here.
 */
export function lineKinds(body: string): Record<string, number> {
  const kinds: Record<string, number> = {};
  let scanned = 0;
  for (const line of splitLines(body)) {
    if (++scanned > 5000) break;
    const word = /^[~]?([A-Za-z_]{2,24})(?=[\s=]|$)/.exec(line);
    const kind = word ? word[1].toUpperCase() : "OTHER";
    if (kinds[kind] === undefined && Object.keys(kinds).length >= 16) continue;
    kinds[kind] = (kinds[kind] ?? 0) + 1;
  }
  return kinds;
}

/**
 * The handshake answer. Stamps say where the terminal should carry on from;
 * TransFlag says which data it uploads (attendance only by default).
 */
export function handshakeText(options: HandshakeOptions): string {
  const hours = Math.trunc(options.utcOffsetMinutes / 60);
  return [
    `GET OPTION FROM: ${options.serialNumber}`,
    `ATTLOGStamp=${options.attlogStamp}`,
    "OPERLOGStamp=9999",
    "ATTPHOTOStamp=None",
    `ErrorDelay=${options.errorDelaySeconds}`,
    `Delay=${options.pollSeconds}`,
    `TransTimes=${options.transTimes}`,
    `TransInterval=${options.transIntervalMinutes}`,
    `TransFlag=${options.transFlag}`,
    `TimeZone=${hours}`,
    `Realtime=${options.realtime ? 1 : 0}`,
    "Encrypt=None",
    ...options.extraOptionLines,
  ].join("\n") + "\n";
}

/**
 * The INFO value a terminal sends when it asks for instructions:
 * "Ver 8.0.4.2-20200710,<users>,<fingerprints>,<punches>,<its address>,..."
 */
export function parseInfo(info: string | null): {
  firmware_version?: string;
  user_count?: number;
  punch_count?: number;
} {
  if (!info) return {};
  const parts = info.split(",").map((part) => part.trim());
  const facts: {
    firmware_version?: string;
    user_count?: number;
    punch_count?: number;
  } = {};
  if (parts[0]) facts.firmware_version = parts[0].slice(0, 80);
  if (/^\d{1,9}$/.test(parts[1] ?? "")) facts.user_count = Number(parts[1]);
  if (/^\d{1,9}$/.test(parts[3] ?? "")) facts.punch_count = Number(parts[3]);
  return facts;
}

/**
 * The model and firmware from a terminal's own options
 * ("~DeviceName=SpeedFace-V5L,FWVersion=Ver 8.0.4.2,..."). Nothing else in
 * that body is read.
 */
export function parseDeviceOptions(body: string): {
  device_name?: string;
  firmware_version?: string;
} {
  const facts: { device_name?: string; firmware_version?: string } = {};
  for (const piece of body.split(/[,\r\n]+/)) {
    const match = /^\s*~?([A-Za-z]+)=(.*)$/.exec(piece);
    if (!match) continue;
    const key = match[1].toLowerCase();
    const value = match[2].trim().slice(0, 80);
    if (value === "") continue;
    if (key === "devicename") facts.device_name = value;
    if (key === "fwversion") facts.firmware_version = value;
  }
  return facts;
}
