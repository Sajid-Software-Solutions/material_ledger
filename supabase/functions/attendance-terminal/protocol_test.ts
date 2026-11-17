import { assertEquals } from "jsr:@std/assert@1";
import {
  handshakeText,
  lineKinds,
  parseAttendanceLines,
  parseDeviceOptions,
  parseInfo,
  queryKeys,
  queryValue,
  routeFor,
  serialNumber,
} from "./protocol.ts";

const params = (query: string) => new URLSearchParams(query);

Deno.test("a serial number is trimmed and upper case, or refused", () => {
  assertEquals(serialNumber(" cgxh201260122 "), "CGXH201260122");
  assertEquals(serialNumber("SIM-0001"), "SIM-0001");
  assertEquals(serialNumber("abc"), null);
  assertEquals(serialNumber("-ABCD"), null);
  assertEquals(serialNumber("AB CD12"), null);
  assertEquals(serialNumber("X".repeat(41)), null);
  assertEquals(serialNumber("ABCD';--"), null);
  assertEquals(serialNumber(null), null);
});

Deno.test("query names are read whatever their case", () => {
  const query = params("sn=A1&TABLE=ATTLOG&stamp=12");
  assertEquals(queryValue(query, "SN"), "A1");
  assertEquals(queryValue(query, "table"), "ATTLOG");
  assertEquals(queryValue(query, "Stamp"), "12");
  assertEquals(queryValue(query, "missing"), null);
});

Deno.test("only the names of query values are kept for the log", () => {
  assertEquals(
    queryKeys(params("SN=A1&options=all&pushver=2.4.1&SN=again&bad key=1")),
    ["SN", "options", "pushver"],
  );
});

Deno.test("calls are told apart by method and the path's last part", () => {
  assertEquals(
    routeFor("GET", "/iclock/cdata", params("SN=A&options=all")),
    { endpoint: "handshake" },
  );
  assertEquals(
    routeFor(
      "POST",
      "/attendance-terminal/iclock/cdata",
      params("SN=A&table=ATTLOG&Stamp=9"),
    ),
    { endpoint: "punches" },
  );
  assertEquals(
    routeFor("POST", "/iclock/cdata", params("SN=A&table=attlog")),
    { endpoint: "punches" },
  );
  assertEquals(
    routeFor("POST", "/iclock/cdata", params("SN=A&table=OPERLOG")),
    { endpoint: "data", table: "OPERLOG" },
  );
  assertEquals(
    routeFor("POST", "/iclock/cdata", params("SN=A&table=a%20b")),
    { endpoint: "data", table: "unknown" },
  );
  assertEquals(
    routeFor("POST", "/iclock/cdata", params("SN=A")),
    { endpoint: "data", table: "unknown" },
  );
  assertEquals(
    routeFor(
      "GET",
      "/functions/v1/attendance-terminal/ICLOCK/GetRequest",
      params("SN=A"),
    ),
    { endpoint: "poll" },
  );
  assertEquals(
    routeFor("POST", "/iclock/devicecmd", params("SN=A")),
    { endpoint: "command_result" },
  );
  assertEquals(routeFor("GET", "/iclock/ping/", params("SN=A")), {
    endpoint: "ping",
  });
  assertEquals(routeFor("POST", "/iclock/registry", params("SN=A")), {
    endpoint: "other",
    name: "registry",
  });
});

Deno.test("a path that is not a terminal path is not routed", () => {
  assertEquals(routeFor("GET", "/", params("")), null);
  assertEquals(routeFor("GET", "/iclock/", params("")), null);
  assertEquals(routeFor("GET", "/attendance-terminal", params("")), null);
  assertEquals(routeFor("GET", "/iclock/cdata/extra", params("")), null);
  assertEquals(routeFor("GET", "/notiClock/cdata", params("")), null);
});

Deno.test("attendance lines are split on tabs and kept as they arrived", () => {
  const body = "418\t2026-11-17 06:31:05\t0\t15\t0\t0\t0\r\n" +
    "\n" +
    "7\t2026-11-17 14:02:11\t1\t1\t\t\r" +
    "22\t2026-11-17 06:40:00\t255\t25\tWC1";
  assertEquals(parseAttendanceLines(body), [
    {
      raw: "418\t2026-11-17 06:31:05\t0\t15\t0\t0\t0",
      pin: "418",
      time: "2026-11-17 06:31:05",
      state: "0",
      verify: "15",
      work_code: "0",
    },
    {
      raw: "7\t2026-11-17 14:02:11\t1\t1\t\t",
      pin: "7",
      time: "2026-11-17 14:02:11",
      state: "1",
      verify: "1",
      work_code: null,
    },
    {
      raw: "22\t2026-11-17 06:40:00\t255\t25\tWC1",
      pin: "22",
      time: "2026-11-17 06:40:00",
      state: "255",
      verify: "25",
      work_code: "WC1",
    },
  ]);
});

Deno.test("a line with spaces instead of tabs is still read", () => {
  assertEquals(parseAttendanceLines("2 2020-07-10 16:34:02 255 15 0 0 10"), [
    {
      raw: "2 2020-07-10 16:34:02 255 15 0 0 10",
      pin: "2",
      time: "2020-07-10 16:34:02",
      state: "255",
      verify: "15",
      work_code: "0",
    },
  ]);
});

Deno.test("a line that cannot be split goes on with its raw text", () => {
  const lines = parseAttendanceLines("garbage\n" + "x".repeat(900));
  assertEquals(lines.length, 2);
  assertEquals(lines[0], {
    raw: "garbage",
    pin: "garbage",
    time: null,
    state: null,
    verify: null,
    work_code: null,
  });
  assertEquals(lines[1].raw.length, 400);
  assertEquals(lines[1].time, null);
  assertEquals(parseAttendanceLines("\r\n\n"), []);
});

Deno.test("data Yorks does not keep is only counted by kind", () => {
  const body = "USER PIN=418\tName=Somebody\tPri=0\n" +
    "FP PIN=418\tFID=0\tSize=1024\tTMP=AAAA\n" +
    "FP PIN=418\tFID=1\tSize=1024\tTMP=BBBB\n" +
    "OPLOG 4\t0\t2026-11-17 06:00:00\n" +
    "~DeviceName=SpeedFace-V5L\n" +
    "\u0001\u0002binary";
  assertEquals(lineKinds(body), {
    USER: 1,
    FP: 2,
    OPLOG: 1,
    DEVICENAME: 1,
    OTHER: 1,
  });
  assertEquals(JSON.stringify(lineKinds(body)).includes("AAAA"), false);
  assertEquals(JSON.stringify(lineKinds(body)).includes("Somebody"), false);
});

Deno.test("the handshake answer is exactly what a terminal expects", () => {
  assertEquals(
    handshakeText({
      serialNumber: "CGXH201260122",
      attlogStamp: "None",
      pollSeconds: 60,
      errorDelaySeconds: 60,
      realtime: true,
      transTimes: "00:00;14:05",
      transIntervalMinutes: 1,
      transFlag: "100000000000",
      utcOffsetMinutes: 240,
      extraOptionLines: [],
    }),
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
});

Deno.test("the handshake carries the stamp, the zone and extra lines", () => {
  const answer = handshakeText({
    serialNumber: "A1B2C3",
    attlogStamp: "0",
    pollSeconds: 120,
    errorDelaySeconds: 30,
    realtime: false,
    transTimes: "00:00",
    transIntervalMinutes: 5,
    transFlag: "TransData AttLog",
    utcOffsetMinutes: -300,
    extraOptionLines: ["ServerVer=2.4.1", "PushProtVer=2.4.1"],
  });
  assertEquals(answer.includes("ATTLOGStamp=0\n"), true);
  assertEquals(answer.includes("Delay=120\n"), true);
  assertEquals(answer.includes("TimeZone=-5\n"), true);
  assertEquals(answer.includes("Realtime=0\n"), true);
  assertEquals(answer.includes("TransFlag=TransData AttLog\n"), true);
  assertEquals(answer.endsWith("ServerVer=2.4.1\nPushProtVer=2.4.1\n"), true);
});

Deno.test("the terminal's own facts are read from INFO and options", () => {
  assertEquals(
    parseInfo("Ver 8.0.4.2-20200710,107,0,3520,192.168.1.201,10,39,12,2,11110"),
    {
      firmware_version: "Ver 8.0.4.2-20200710",
      user_count: 107,
      punch_count: 3520,
    },
  );
  assertEquals(parseInfo(null), {});
  assertEquals(parseInfo("Ver 1,x,,y"), { firmware_version: "Ver 1" });
  assertEquals(
    parseDeviceOptions(
      "~DeviceName=SpeedFace-V5L,MAC=00:17:61:12:34:56,TransactionCount=3520,FWVersion=Ver 8.0.4.2-20200710,IPAddress=192.168.1.201",
    ),
    { device_name: "SpeedFace-V5L", firmware_version: "Ver 8.0.4.2-20200710" },
  );
  assertEquals(parseDeviceOptions("nothing useful"), {});
});
