import { assertEquals } from "jsr:@std/assert@1";
import { defaultDependencies, handlePush } from "./handler.ts";

const id = "11000000-0000-4000-8000-000000000001";
function harness(
  tokens = ["device-a", "device-b"],
  origin = "test",
  retiredAt: string | null = null,
) {
  const ledger = new Map<string, string>();
  const finishes: Record<string, unknown>[] = [];
  const sends: string[] = [];
  let failure: number | null = 503;
  let failRecord = false;
  let configured = true;
  const client = {
    from: () => ({
      select: () => ({
        eq: () =>
          Promise.resolve({
            data: tokens.map((token) => ({
              token,
              platform: "web",
              web_origin: origin,
              installation_id: id,
              retired_at: retiredAt,
            })),
            error: null,
          }),
      }),
    }),
    rpc: (name: string, args: Record<string, unknown>) => {
      let data: unknown = true;
      if (name === "v1_claim_notification_push") {
        data = {
          claimId: id,
          notificationId: id,
          recipientAuthUserId: id,
          eventCode: "material_request_submitted",
          entityType: "material_request",
          entityId: id,
          attemptCount: 1,
        };
      }
      if (name === "v1_begin_push_device") {
        const hash = String(args.p_token_hash);
        data = ledger.get(hash) === "sent" ? "sent" : "ready";
      }
      if (name === "v1_finish_push_device") {
        if (failRecord) {
          return Promise.resolve({ data: null, error: { message: "lost" } });
        }
        ledger.set(
          String(args.p_token_hash),
          args.p_error_code ? "retry_wait" : "sent",
        );
      }
      if (name === "v1_finish_notification_push") finishes.push(args);
      return Promise.resolve({ data, error: null });
    },
  };
  const deps: typeof defaultDependencies = {
    env: (name) =>
      name === "FCM_SERVICE_ACCOUNT_JSON"
        ? configured
          ? JSON.stringify({
            project_id: "test",
            client_email: "test",
            private_key: "test",
          })
          : undefined
        : "test",
    createClient:
      (() => client) as unknown as typeof defaultDependencies.createClient,
    getFcmAccessToken: () => Promise.resolve("fake-access"),
    fetch: ((_url: unknown, init: RequestInit) => {
      const token = JSON.parse(String(init.body)).message.token;
      sends.push(token);
      if (failure === -1) {
        return Promise.reject(new Error("ambiguous transport"));
      }
      return Promise.resolve(
        new Response("{}", {
          status: token === "device-b" && failure ? failure : 200,
        }),
      );
    }) as typeof fetch,
  };
  return {
    ledger,
    finishes,
    sends,
    deps,
    setFailure: (value: number | null) => {
      failure = value;
    },
    failRecord: () => {
      failRecord = true;
    },
    unconfigure: () => {
      configured = false;
    },
    run: () =>
      handlePush(
        new Request("https://test.invalid", {
          method: "POST",
          body: JSON.stringify({ notificationId: id }),
        }),
        deps,
      ),
  };
}
Deno.test("handler retries rejected device without resending accepted device", async () => {
  const h = harness();
  assertEquals((await h.run()).status, 503);
  assertEquals(h.finishes[0].p_status, "retryable");
  h.setFailure(null);
  assertEquals((await h.run()).status, 200);
  assertEquals(h.sends, ["device-a", "device-b", "device-b"]);
  assertEquals(h.finishes[1].p_sent_device_count, 2);
});
Deno.test("handler never reports success when device acknowledgement is lost", async () => {
  const h = harness();
  h.failRecord();
  assertEquals((await h.run()).status, 503);
  assertEquals(h.sends, ["device-a"]);
  assertEquals(h.finishes, []);
});
Deno.test("handler terminalizes ambiguous transport rather than retrying", async () => {
  const h = harness(["device-a"]);
  h.setFailure(-1);
  assertEquals((await h.run()).status, 422);
  assertEquals(h.finishes[0].p_status, "terminal");
  assertEquals(h.finishes[0].p_error_code, "DELIVERY_OUTCOME_UNKNOWN");
});
Deno.test("handler missing configuration performs no external send", async () => {
  const h = harness();
  h.unconfigure();
  assertEquals((await h.run()).status, 503);
  assertEquals(h.sends, []);
  assertEquals(h.finishes[0].p_error_code, "FCM_NOT_CONFIGURED");
});
Deno.test("handler no devices completes without Firebase credentials", async () => {
  const h = harness([]);
  h.unconfigure();
  assertEquals((await h.run()).status, 200);
  assertEquals(h.finishes[0].p_status, "no_devices");
});

Deno.test("handler skips preview and retired tokens without sending", async () => {
  for (
    const h of [
      harness(["device-a"], "https://old-preview.invalid"),
      harness(["device-a"], "test", "2026-09-29"),
    ]
  ) {
    assertEquals((await h.run()).status, 200);
    assertEquals(h.sends, []);
    assertEquals(h.finishes[0].p_status, "no_devices");
  }
});
