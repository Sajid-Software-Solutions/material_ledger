import { assertEquals } from "jsr:@std/assert@1";
import { handleTerminal, type TerminalDependencies } from "./handler.ts";

type Call = { name: string; args: Record<string, unknown> };

const handshakeAnswer = {
  outcome: "ok",
  serial_number: "CGXH201260122",
  attlog_stamp: "None",
  poll_seconds: 60,
  error_delay_seconds: 60,
  realtime: true,
  trans_times: "00:00;14:05",
  trans_interval_minutes: 1,
  trans_flag: "100000000000",
  utc_offset_minutes: 240,
  extra_option_lines: [],
};

/** A stand-in for Postgres: answers each function with what the test set. */
function harness(
  answers: Record<string, unknown> = {},
  options: { fail?: string; configured?: boolean; reject?: boolean } = {},
) {
  const calls: Call[] = [];
  const logs: Record<string, unknown>[] = [];
  const dependencies: TerminalDependencies = {
    env: (name) =>
      options.configured === false
        ? undefined
        : name === "SUPABASE_URL"
        ? "https://example.invalid"
        : "service-key",
    createClient: () => ({
      rpc: (name, args) => {
        calls.push({ name, args });
        if (options.reject) return Promise.reject(new Error("network"));
        if (options.fail === name) {
          return Promise.resolve({ data: null, error: { message: "lost" } });
        }
        return Promise.resolve({
          data: answers[name] ?? { outcome: "ok" },
          error: null,
        });
      },
    }),
    log: (entry) => logs.push(entry),
  };
  return { calls, logs, dependencies };
}

const base = "https://example.invalid/attendance-terminal";

function get(path: string, headers: Record<string, string> = {}) {
  return new Request(base + path, { method: "GET", headers });
}

function post(path: string, body: BodyInit) {
  return new Request(base + path, {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body,
  });
}

Deno.test("a registered terminal's handshake is answered in its own format", async () => {
  const { calls, dependencies } = harness({
    v1_wf_terminal_handshake: handshakeAnswer,
  });
  const response = await handleTerminal(
    get(
      "/iclock/cdata?SN=cgxh201260122&options=all&pushver=2.4.1&language=69",
      { "x-forwarded-for": "203.0.113.7, 10.0.0.1" },
    ),
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("content-type"), "text/plain");
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(
    await response.text(),
    "GET OPTION FROM: CGXH201260122\n" +
      "ATTLOGStamp=None\n" +
      "OPERLOGStamp=9999\n" +
      "ATTPHOTOStamp=None\n" +
      "ErrorDelay=60\n" +
      "Delay=60\n" +
      "TransTimes=00:00;14:05\n" +
      "TransInterval=1\n" +
      "TransFlag=100000000000\n" +
      "TimeZone=4\n" +
      "Realtime=1\n" +
      "Encrypt=None\n",
  );
  assertEquals(calls.length, 1);
  assertEquals(calls[0].name, "v1_wf_terminal_handshake");
  assertEquals(calls[0].args.p_serial_number, "CGXH201260122");
  const details = calls[0].args.p_details as Record<string, unknown>;
  assertEquals(details.push_version, "2.4.1");
  assertEquals(details.remote_ip, "203.0.113.7");
  assertEquals(details.query_keys, ["SN", "options", "pushver", "language"]);
});

Deno.test("check-ins are handed to Postgres and acknowledged line for line", async () => {
  const { calls, logs, dependencies } = harness({
    v1_wf_terminal_punches: {
      outcome: "ok",
      received: 2,
      stored: 1,
      duplicates: 1,
      rejected: 0,
    },
  });
  const response = await handleTerminal(
    post(
      "/iclock/cdata?SN=CGXH201260122&table=ATTLOG&Stamp=745820765",
      "418\t2026-11-17 06:31:05\t0\t15\t0\t0\n" +
        "7\t2026-11-17 06:32:40\t255\t1\t0\t0\n",
    ),
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "OK: 2\n");
  assertEquals(calls.length, 1);
  assertEquals(calls[0].name, "v1_wf_terminal_punches");
  assertEquals(calls[0].args.p_stamp, "745820765");
  assertEquals(calls[0].args.p_lines, [
    {
      raw: "418\t2026-11-17 06:31:05\t0\t15\t0\t0",
      pin: "418",
      time: "2026-11-17 06:31:05",
      state: "0",
      verify: "15",
      work_code: "0",
    },
    {
      raw: "7\t2026-11-17 06:32:40\t255\t1\t0\t0",
      pin: "7",
      time: "2026-11-17 06:32:40",
      state: "255",
      verify: "1",
      work_code: "0",
    },
  ]);
  assertEquals(logs[0].stored, 1);
  assertEquals(logs[0].duplicates, 1);
});

Deno.test("OK is never answered when Postgres did not store the lines", async () => {
  const body = "418\t2026-11-17 06:31:05\t0\t15\t0\t0\n";
  const path = "/iclock/cdata?SN=CGXH201260122&table=ATTLOG&Stamp=1";

  const failed = harness({}, { fail: "v1_wf_terminal_punches" });
  let response = await handleTerminal(post(path, body), failed.dependencies);
  assertEquals(response.status, 500);
  assertEquals((await response.text()).startsWith("OK"), false);
  assertEquals(failed.logs[0].failure, "error: lost");

  const thrown = harness({}, { reject: true });
  response = await handleTerminal(post(path, body), thrown.dependencies);
  assertEquals(response.status, 500);
  assertEquals((await response.text()).startsWith("OK"), false);
  assertEquals(thrown.logs[0].failure, "thrown: Error: network");

  const malformed = harness({ v1_wf_terminal_punches: "nonsense" });
  response = await handleTerminal(post(path, body), malformed.dependencies);
  assertEquals(response.status, 500);
  assertEquals((await response.text()).startsWith("OK"), false);
  assertEquals(malformed.logs[0].failure, "unexpected answer");
  for (const { logs } of [failed, thrown, malformed]) {
    assertEquals(JSON.stringify(logs).includes("2026-11-17"), false);
  }
});

Deno.test("a terminal Postgres refuses is refused, each way with its own status", async () => {
  const path = "/iclock/cdata?SN=CGXH201260122&table=ATTLOG&Stamp=1";
  const body = "418\t2026-11-17 06:31:05\t0\t15\t0\t0\n";
  for (
    const [outcome, status] of [
      ["receiver_off", 503],
      ["unknown_terminal", 403],
      ["inactive_terminal", 403],
      ["invalid", 400],
      ["something_new", 500],
    ] as const
  ) {
    const { dependencies } = harness({
      v1_wf_terminal_punches: { outcome },
      v1_wf_terminal_handshake: { outcome },
      v1_wf_terminal_seen: { outcome },
    });
    for (
      const request of [
        post(path, body),
        get("/iclock/cdata?SN=CGXH201260122&options=all"),
        get("/iclock/getrequest?SN=CGXH201260122"),
      ]
    ) {
      const response = await handleTerminal(request, dependencies);
      assertEquals(response.status, status);
      assertEquals(await response.text(), "ERROR\n");
    }
  }
});

Deno.test("fingerprints, faces and names are counted and go no further", async () => {
  const { calls, logs, dependencies } = harness();
  const body = "USER PIN=418\tName=Private Person\tPri=0\tPasswd=1234\n" +
    "FP PIN=418\tFID=0\tSize=1024\tValid=1\tTMP=SECRETTEMPLATEDATA\n" +
    "BIODATA Pin=418\tNo=0\tType=9\tTmp=SECRETFACEDATA\n";
  const response = await handleTerminal(
    post("/iclock/cdata?SN=CGXH201260122&table=OPERLOG&Stamp=5", body),
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "OK\n");
  assertEquals(calls.length, 1);
  assertEquals(calls[0].name, "v1_wf_terminal_seen");
  assertEquals(calls[0].args.p_endpoint, "data");
  assertEquals(calls[0].args.p_table_name, "OPERLOG");
  const details = calls[0].args.p_details as Record<string, unknown>;
  assertEquals(details.line_count, 3);
  assertEquals(details.line_kinds, { USER: 1, FP: 1, BIODATA: 1 });
  const sent = JSON.stringify(calls) + JSON.stringify(logs);
  for (
    const secret of ["SECRETTEMPLATEDATA", "SECRETFACEDATA", "Private", "1234"]
  ) {
    assertEquals(sent.includes(secret), false);
  }
});

Deno.test("a photo upload is acknowledged and dropped", async () => {
  const { calls, dependencies } = harness();
  const bytes = new Uint8Array(2048).fill(255);
  const response = await handleTerminal(
    post("/iclock/cdata?SN=CGXH201260122&table=ATTPHOTO&Stamp=5", bytes),
    dependencies,
  );
  assertEquals(await response.text(), "OK\n");
  const details = calls[0].args.p_details as Record<string, unknown>;
  assertEquals(details.body_bytes, 2048);
  assertEquals(calls[0].args.p_table_name, "ATTPHOTO");
});

Deno.test("the terminal's own options give its model and firmware only", async () => {
  const { calls, dependencies } = harness();
  const response = await handleTerminal(
    post(
      "/iclock/cdata?SN=CGXH201260122&table=options",
      "~DeviceName=SpeedFace-V5L,MAC=00:17:61:12:34:56,FWVersion=Ver 8.0.4.2-20200710,IPAddress=192.168.1.201",
    ),
    dependencies,
  );
  assertEquals(await response.text(), "OK\n");
  const details = calls[0].args.p_details as Record<string, unknown>;
  assertEquals(details.device_name, "SpeedFace-V5L");
  assertEquals(details.firmware_version, "Ver 8.0.4.2-20200710");
  assertEquals(JSON.stringify(details).includes("00:17:61"), false);
});

Deno.test("asking for instructions is answered OK and marks the terminal seen", async () => {
  const { calls, dependencies } = harness();
  const response = await handleTerminal(
    get(
      "/iclock/getrequest?SN=CGXH201260122&INFO=Ver%208.0.4.2-20200710,107,0,3520,192.168.1.201,10,39",
    ),
    dependencies,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "OK\n");
  assertEquals(calls[0].name, "v1_wf_terminal_seen");
  assertEquals(calls[0].args.p_endpoint, "poll");
  assertEquals(calls[0].args.p_table_name, null);
  const details = calls[0].args.p_details as Record<string, unknown>;
  assertEquals(details.firmware_version, "Ver 8.0.4.2-20200710");
  assertEquals(details.user_count, 107);
  assertEquals(details.punch_count, 3520);
});

Deno.test("pings and command results are answered OK", async () => {
  const { calls, dependencies } = harness();
  let response = await handleTerminal(
    get("/iclock/ping?SN=CGXH201260122"),
    dependencies,
  );
  assertEquals(await response.text(), "OK\n");
  response = await handleTerminal(
    post("/iclock/devicecmd?SN=CGXH201260122", "ID=1&Return=0&CMD=INFO"),
    dependencies,
  );
  assertEquals(await response.text(), "OK\n");
  assertEquals(calls.map((call) => call.args.p_endpoint), [
    "ping",
    "command_result",
  ]);
  assertEquals(JSON.stringify(calls).includes("Return=0"), false);
});

Deno.test("an endpoint Yorks does not speak is recorded and refused", async () => {
  const { calls, dependencies } = harness();
  const response = await handleTerminal(
    post("/iclock/registry?SN=CGXH201260122", "DeviceType=acc"),
    dependencies,
  );
  assertEquals(response.status, 404);
  assertEquals(calls[0].args.p_endpoint, "other");
  const details = calls[0].args.p_details as Record<string, unknown>;
  assertEquals(details.note, "endpoint registry");
});

Deno.test("requests that are not a terminal's never reach Postgres", async () => {
  const { calls, dependencies } = harness();
  for (
    const [request, status] of [
      [get("/"), 404],
      [get("/iclock/"), 404],
      [get("/something/else?SN=CGXH201260122"), 404],
      [get("/iclock/cdata"), 400],
      [get("/iclock/cdata?SN=ab"), 400],
      [get("/iclock/cdata?SN=A1B2%27%3B--"), 400],
      [
        new Request(base + "/iclock/cdata?SN=CGXH201260122", {
          method: "DELETE",
        }),
        405,
      ],
    ] as const
  ) {
    const response = await handleTerminal(request, dependencies);
    assertEquals(response.status, status);
  }
  assertEquals(calls.length, 0);
});

Deno.test("an oversized body is refused unread", async () => {
  const { calls, dependencies } = harness();
  const declared = new Request(
    base + "/iclock/cdata?SN=CGXH201260122&table=ATTLOG",
    {
      method: "POST",
      headers: { "content-length": String(5 * 1024 * 1024) },
      body: "418\t2026-11-17 06:31:05\t0\t15\n",
    },
  );
  assertEquals((await handleTerminal(declared, dependencies)).status, 413);
  const actual = post(
    "/iclock/cdata?SN=CGXH201260122&table=ATTLOG",
    new Uint8Array(4 * 1024 * 1024 + 1).fill(65),
  );
  assertEquals((await handleTerminal(actual, dependencies)).status, 413);
  assertEquals(calls.length, 0);
});

Deno.test("without its configuration the function answers unavailable", async () => {
  const { calls, dependencies } = harness({}, { configured: false });
  const response = await handleTerminal(
    get("/iclock/cdata?SN=CGXH201260122&options=all"),
    dependencies,
  );
  assertEquals(response.status, 503);
  assertEquals(calls.length, 0);
});

Deno.test("every call is logged without its body", async () => {
  const { logs, dependencies } = harness({
    v1_wf_terminal_punches: {
      outcome: "ok",
      received: 1,
      stored: 1,
      duplicates: 0,
      rejected: 0,
    },
  });
  await handleTerminal(
    post(
      "/iclock/cdata?SN=CGXH201260122&table=ATTLOG&Stamp=1",
      "418\t2026-11-17 06:31:05\t0\t15\t0\t0\n",
    ),
    dependencies,
  );
  assertEquals(logs, [{
    function: "attendance-terminal",
    endpoint: "punches",
    serial_number: "CGXH201260122",
    outcome: "ok",
    status: 200,
    received: 1,
    stored: 1,
    duplicates: 0,
    rejected: 0,
  }]);
});
