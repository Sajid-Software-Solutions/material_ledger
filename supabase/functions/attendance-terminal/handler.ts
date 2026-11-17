// Yorks attendance terminal receiver.
//
// A biometric attendance terminal (ZKTeco attendance push) calls this
// function by itself. The function answers in the terminal's own plain-text
// protocol and hands what it was sent to Postgres, which decides everything:
// whether the receiver is on, whether the serial number is registered, what
// is stored and what is a duplicate.
//
// Three rules hold whatever a terminal sends:
//   * "OK" is only ever answered after Postgres has stored the lines. Any
//     failure answers an error, so the terminal keeps its punches and sends
//     them again.
//   * Only attendance lines are passed on. Any other body (users,
//     fingerprints, faces, photos) is counted by kind and dropped here; it is
//     never stored and never logged.
//   * Nothing here touches attendance days. The punch log is the only thing
//     written.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  handshakeText,
  lineKinds,
  MAX_BODY_BYTES,
  MAX_LINES,
  parseAttendanceLines,
  parseDeviceOptions,
  parseInfo,
  queryKeys,
  queryValue,
  routeFor,
  serialNumber,
  splitLines,
} from "./protocol.ts";

type RpcResult = {
  data: unknown;
  error: { message?: string; code?: string } | null;
};

/** The one thing this function needs from the database client. */
export type TerminalClient = {
  rpc: (name: string, args: Record<string, unknown>) => PromiseLike<RpcResult>;
};

export type TerminalDependencies = {
  env: (name: string) => string | undefined;
  createClient: (
    url: string,
    key: string,
    options: Record<string, unknown>,
  ) => TerminalClient;
  log: (entry: Record<string, unknown>) => void;
};

export const defaultDependencies: TerminalDependencies = {
  env: (name: string) => Deno.env.get(name),
  createClient: (url, key, options) =>
    createClient(url, key, options) as unknown as TerminalClient,
  log: (entry) => console.log(JSON.stringify(entry)),
};

function text(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/plain",
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
    },
  });
}

/** What the terminal is told when Postgres did not say "ok". */
function refusal(outcome: string): Response {
  switch (outcome) {
    case "receiver_off":
      return text("ERROR\n", 503);
    case "unknown_terminal":
    case "inactive_terminal":
      return text("ERROR\n", 403);
    case "invalid":
      return text("ERROR\n", 400);
    default:
      return text("ERROR\n", 500);
  }
}

function remoteIp(request: Request): string | undefined {
  const forwarded = request.headers.get("x-forwarded-for") ?? "";
  const first = forwarded.split(",")[0].trim();
  return first === "" ? undefined : first.slice(0, 64);
}

type Outcome = Record<string, unknown> & { outcome: string };

function outcomeOf(result: RpcResult): Outcome | null {
  if (result.error) return null;
  const data = result.data;
  if (
    typeof data !== "object" || data === null ||
    typeof (data as Outcome).outcome !== "string"
  ) {
    return null;
  }
  return data as Outcome;
}

export async function handleTerminal(
  request: Request,
  dependencies: TerminalDependencies = defaultDependencies,
): Promise<Response> {
  const url = new URL(request.url);
  const method = request.method.toUpperCase();
  const route = routeFor(method, url.pathname, url.searchParams);
  if (route === null) return text("NOT FOUND\n", 404);
  if (method !== "GET" && method !== "POST") return text("ERROR\n", 405);

  const serial = serialNumber(queryValue(url.searchParams, "SN"));
  if (serial === null) return text("ERROR\n", 400);

  const supabaseUrl = dependencies.env("SUPABASE_URL") ?? "";
  const serviceKey = dependencies.env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) return text("ERROR\n", 503);

  let body = "";
  let bodyBytes = 0;
  if (method === "POST") {
    const declared = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
      return text("ERROR\n", 413);
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.byteLength > MAX_BODY_BYTES) return text("ERROR\n", 413);
    bodyBytes = bytes.byteLength;
    body = new TextDecoder("utf-8").decode(bytes);
  }

  const details: Record<string, unknown> = {
    method,
    path: url.pathname.slice(-120),
    query_keys: queryKeys(url.searchParams),
    remote_ip: remoteIp(request),
    user_agent: request.headers.get("user-agent") ?? undefined,
  };
  if (method === "POST") {
    details.body_bytes = bodyBytes;
    details.content_type = request.headers.get("content-type") ?? undefined;
  }

  const admin = dependencies.createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Why the database call failed, for the function's own log. It is the
  // database's error code and the start of its message, never a body.
  let failure: string | undefined;

  const finish = (
    response: Response,
    outcome: string,
    counts: Record<string, unknown> = {},
  ): Response => {
    dependencies.log({
      function: "attendance-terminal",
      endpoint: route.endpoint,
      serial_number: serial,
      outcome,
      status: response.status,
      ...counts,
      ...(failure === undefined ? {} : { failure }),
    });
    return response;
  };

  const ask = async (
    name: string,
    args: Record<string, unknown>,
  ): Promise<Outcome | null> => {
    const result = await admin.rpc(name, args);
    if (result.error) {
      failure = `${result.error.code ?? "error"}: ${
        (result.error.message ?? "").slice(0, 120)
      }`;
    }
    const answer = outcomeOf(result);
    if (answer === null && failure === undefined) {
      failure = "unexpected answer";
    }
    return answer;
  };

  try {
    if (route.endpoint === "handshake") {
      details.push_version = queryValue(url.searchParams, "pushver") ??
        undefined;
      details.language = queryValue(url.searchParams, "language") ?? undefined;
      details.device_type = queryValue(url.searchParams, "DeviceType") ??
        undefined;
      const answer = await ask("v1_wf_terminal_handshake", {
        p_serial_number: serial,
        p_details: details,
      });
      if (answer === null) return finish(refusal("error"), "error");
      if (answer.outcome !== "ok") {
        return finish(refusal(answer.outcome), answer.outcome);
      }
      const extra = Array.isArray(answer.extra_option_lines)
        ? answer.extra_option_lines.filter((line): line is string =>
          typeof line === "string"
        )
        : [];
      return finish(
        text(handshakeText({
          serialNumber: serial,
          attlogStamp: String(answer.attlog_stamp ?? "None"),
          pollSeconds: Number(answer.poll_seconds ?? 60),
          errorDelaySeconds: Number(answer.error_delay_seconds ?? 60),
          realtime: answer.realtime !== false,
          transTimes: String(answer.trans_times ?? "00:00;14:05"),
          transIntervalMinutes: Number(answer.trans_interval_minutes ?? 1),
          transFlag: String(answer.trans_flag ?? "100000000000"),
          utcOffsetMinutes: Number(answer.utc_offset_minutes ?? 240),
          extraOptionLines: extra,
        })),
        "ok",
      );
    }

    if (route.endpoint === "punches") {
      const lines = parseAttendanceLines(body);
      if (lines.length > MAX_LINES) {
        return finish(refusal("invalid"), "invalid");
      }
      const stamp = queryValue(url.searchParams, "Stamp") ?? "";
      details.stamp = stamp;
      details.line_count = lines.length;
      const answer = await ask("v1_wf_terminal_punches", {
        p_serial_number: serial,
        p_stamp: stamp,
        p_lines: lines,
        p_details: details,
      });
      if (answer === null) return finish(refusal("error"), "error");
      if (answer.outcome !== "ok") {
        return finish(refusal(answer.outcome), answer.outcome);
      }
      // Every line is now stored, already held, or kept as unreadable.
      return finish(text(`OK: ${lines.length}\n`), "ok", {
        received: answer.received,
        stored: answer.stored,
        duplicates: answer.duplicates,
        rejected: answer.rejected,
      });
    }

    let table: string | null = null;
    if (route.endpoint === "data") {
      // Not attendance: counted by kind and dropped. The body goes no
      // further than this function's memory.
      table = route.table;
      details.line_count = splitLines(body).length;
      details.line_kinds = lineKinds(body);
      if (table.toLowerCase() === "options") {
        Object.assign(details, parseDeviceOptions(body));
      }
    } else if (route.endpoint === "poll") {
      const info = queryValue(url.searchParams, "INFO");
      if (info) {
        details.info = info;
        Object.assign(details, parseInfo(info));
      }
    } else if (route.endpoint === "other") {
      details.note = `endpoint ${route.name}`;
    }

    const answer = await ask("v1_wf_terminal_seen", {
      p_serial_number: serial,
      p_endpoint: route.endpoint,
      p_table_name: table,
      p_details: details,
    });
    if (answer === null) return finish(refusal("error"), "error");
    if (answer.outcome !== "ok") {
      return finish(refusal(answer.outcome), answer.outcome);
    }
    // An endpoint Yorks does not speak is recorded, then refused, so a
    // terminal never takes silence for an answer.
    if (route.endpoint === "other") {
      return finish(text("NOT FOUND\n", 404), "unsupported");
    }
    return finish(text("OK\n"), "ok");
  } catch (error) {
    failure = `thrown: ${String(error).slice(0, 120)}`;
    return finish(refusal("error"), "error");
  }
}
