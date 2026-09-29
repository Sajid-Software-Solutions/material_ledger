// Yorks V1 trusted FCM transport.
//
// Postgres is authoritative: a workflow RPC inserts v1_notifications, which
// creates a durable outbox row; the bounded dispatcher invokes this function.
// The caller cannot choose recipients or message copy. This function claims
// the outbox command atomically, derives safe non-commercial copy, reads only
// the recipient's protected device tokens, and records a retryable result.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendFcmRequest } from "./fcm_failure.mjs";
import {
  isTeamChatEvent,
  normalizedUnreadCount,
  type PushClaim,
  routeFor,
  safePushCopy,
  webLinkFor,
} from "./notification_payload.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-yorks-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200, extraHeaders = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, ...extraHeaders, "Content-Type": "application/json" },
  });

function base64UrlEncode(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function importPrivateKey(pem: string): Promise<CryptoKey> {
  const contents = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(
    atob(contents),
    (character) => character.charCodeAt(0),
  );
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getFcmAccessToken(
  serviceAccount: { client_email: string; private_key: string },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })),
  );
  const unsigned = `${header}.${claims}`;
  let key: CryptoKey;
  try {
    key = await importPrivateKey(serviceAccount.private_key);
  } catch {
    throw new Error("FCM_SERVICE_ACCOUNT_INVALID");
  }
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    signal: AbortSignal.timeout(10000),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenData = await response.json();
  if (!response.ok || typeof tokenData.access_token !== "string") {
    throw new Error(`FCM_OAUTH_${response.status}`);
  }
  return tokenData.access_token;
}

export const defaultDependencies = {
  env: (name: string) => Deno.env.get(name),
  createClient,
  fetch,
  getFcmAccessToken,
};

export async function handlePush(
  request: Request,
  dependencies = defaultDependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const suppliedSecret = request.headers.get("x-yorks-push-secret") ?? "";
  const url = dependencies.env("SUPABASE_URL") ?? "";
  const serviceKey = dependencies.env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const serviceAccountJson = dependencies.env("FCM_SERVICE_ACCOUNT_JSON") ?? "";
  if (!url || !serviceKey) return json({ error: "backend unavailable" }, 503);
  const admin = dependencies.createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: secretIsValid, error: secretError } = await admin.rpc(
    "v1_validate_push_webhook_secret",
    { p_secret: suppliedSecret },
  );
  if (secretError || secretIsValid !== true) {
    return json({ error: "unauthorized" }, 401);
  }

  let notificationId = "";
  let deliveredCount = 0;
  let externalSendStarted = false;
  try {
    const body = await request.json();
    notificationId = typeof body.notificationId === "string"
      ? body.notificationId
      : "";
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      notificationId,
    )
  ) {
    return json({ error: "notificationId required" }, 400);
  }

  let claimId = "";
  const finish = async (
    status: "sent" | "no_devices" | "retryable" | "terminal",
    sentDeviceCount = 0,
    errorCode?: string,
    retryAfterSeconds?: number | null,
  ) => {
    const { data, error } = await admin.rpc("v1_finish_notification_push", {
      p_notification_id: notificationId,
      p_claim_id: claimId,
      p_status: status,
      p_sent_device_count: sentDeviceCount,
      p_error_code: errorCode ?? null,
      p_retry_after_seconds: retryAfterSeconds ?? null,
    });
    return !error && data === true;
  };

  const { data: claimData, error: claimError } = await admin.rpc(
    "v1_claim_notification_push",
    { p_notification_id: notificationId },
  );
  if (claimError) return json({ error: "claim failed" }, 500);
  if (!claimData) return json({ ok: true, skipped: true });
  const claim = claimData as PushClaim;
  claimId = claim.claimId;
  if (!/^[0-9a-f-]{36}$/i.test(claimId ?? "")) {
    return json({ error: "invalid claim" }, 500);
  }

  const { data: registeredRows, error: tokenError } = await admin
    .from("v1_push_device_tokens")
    .select("token, platform, web_origin, installation_id, retired_at")
    .eq("auth_user_id", claim.recipientAuthUserId);
  if (tokenError) {
    await finish("retryable", 0, "TOKEN_LOOKUP_FAILED");
    return json({ error: "token lookup failed" }, 503, { "Retry-After": "30" });
  }
  const webOrigin = dependencies.env("YORKS_WEB_ORIGIN") ||
    "https://yorks-r35.vercel.app";
  const tokenRows = (registeredRows ?? []).filter((row) =>
    !row.retired_at &&
    (row.platform !== "web" ||
      (row.installation_id && row.web_origin === webOrigin))
  );
  if (tokenRows.length === 0) {
    if (!await finish("no_devices")) {
      return json({ error: "finish failed" }, 503);
    }
    return json({ ok: true, sent: 0, note: "no registered devices" });
  }

  if (!serviceAccountJson) {
    await finish("terminal", 0, "FCM_NOT_CONFIGURED");
    return json({ error: "push not configured" }, 503);
  }

  try {
    let serviceAccount: {
      project_id: string;
      client_email: string;
      private_key: string;
    };
    try {
      serviceAccount = JSON.parse(serviceAccountJson);
    } catch {
      throw new Error("FCM_SERVICE_ACCOUNT_INVALID");
    }
    if (
      !serviceAccount || typeof serviceAccount !== "object" ||
      typeof serviceAccount.project_id !== "string" ||
      !serviceAccount.project_id ||
      typeof serviceAccount.client_email !== "string" ||
      !serviceAccount.client_email ||
      typeof serviceAccount.private_key !== "string" ||
      !serviceAccount.private_key
    ) {
      throw new Error("FCM_SERVICE_ACCOUNT_INVALID");
    }
    const accessToken = await dependencies.getFcmAccessToken(serviceAccount);
    const sendUrl =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const copy = safePushCopy(claim.eventCode);
    const surface = isTeamChatEvent(claim.eventCode) ? "team_chat" : "workflow";
    const route = routeFor(claim);
    const unreadCount = normalizedUnreadCount(claim.unreadCount);
    const webLink = webLinkFor(
      route,
      webOrigin,
      claim.notificationId,
    );
    let retryableFailure: {
      category: string;
      retryable: boolean;
      global?: boolean;
      retryAfterSeconds?: number | null;
    } | null = null;
    let terminalFailure: {
      category: string;
      retryable: boolean;
      global?: boolean;
      retryAfterSeconds?: number | null;
    } | null = null;
    let staleRemoved = 0;
    let retryDelay = 0;
    for (const row of tokenRows) {
      const token = row.token as string;
      const tokenHash = Array.from(
        new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            new TextEncoder().encode(token),
          ),
        ),
      ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
      const deviceArgs = {
        p_notification_id: notificationId,
        p_claim_id: claimId,
        p_token_hash: tokenHash,
      };
      const { data: gate, error: gateError } = await admin.rpc(
        "v1_begin_push_device",
        deviceArgs,
      );
      if (gateError || gate === "blocked") {
        return json({ error: "device claim unavailable" }, 503);
      }
      if (gate === "sent") {
        deliveredCount += 1;
        continue;
      }
      if (gate === "not_owned") continue;
      if (gate === "dead_letter" || gate === "sending") {
        terminalFailure = {
          category: "DELIVERY_OUTCOME_UNKNOWN",
          retryable: false,
        };
        continue;
      }
      if (gate !== "ready") return json({ error: "invalid device claim" }, 503);
      externalSendStarted = true;
      const isWeb = row.platform === "web";
      const data = {
        notificationId: claim.notificationId,
        eventCode: claim.eventCode,
        surface,
        type: copy.type,
        title: copy.title,
        body: copy.body,
        refId: claim.requestId ?? claim.entityId,
        route,
        unreadCount: String(unreadCount),
      };
      const result = await sendFcmRequest(() =>
        dependencies.fetch(sendUrl, {
          signal: AbortSignal.timeout(10000),
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              data,
              ...(isWeb
                ? {
                  webpush: {
                    headers: { Urgency: "high", TTL: "86400" },
                    notification: {
                      title: copy.title,
                      body: copy.body,
                      icon: "/icons/Icon-192.png",
                      badge: "/icons/Icon-192.png",
                      tag: claim.notificationId,
                      // A retry of the same durable outbox item replaces the
                      // existing OS notification without sounding a second time.
                      renotify: false,
                      requireInteraction: false,
                      silent: false,
                      vibrate: [120, 60, 120],
                    },
                    ...(webLink ? { fcm_options: { link: webLink } } : {}),
                  },
                }
                : {
                  notification: { title: copy.title, body: copy.body },
                  android: {
                    priority: "high",
                    notification: {
                      channel_id: "yorks_push",
                      tag: claim.notificationId,
                      sound: "default",
                      default_vibrate_timings: true,
                      notification_priority: "PRIORITY_HIGH",
                      notification_count: unreadCount,
                    },
                  },
                  apns: {
                    headers: {
                      "apns-collapse-id": claim.notificationId,
                      "apns-priority": "10",
                      "apns-push-type": "alert",
                    },
                    payload: {
                      aps: {
                        alert: { title: copy.title, body: copy.body },
                        badge: unreadCount,
                        sound: "default",
                        "thread-id": surface,
                      },
                    },
                  },
                }),
            },
          }),
        })
      );
      const failure = result.accepted ? null : result.failure!;
      const { data: recorded, error: recordError } = await admin.rpc(
        "v1_finish_push_device",
        { ...deviceArgs, p_error_code: failure?.category ?? null },
      );
      if (recordError || recorded !== true) {
        // A lost acknowledgement cannot justify another external send.
        return json({ error: "device finish failed" }, 503);
      }
      if (result.accepted) {
        deliveredCount += 1;
        continue;
      }
      if (failure!.staleToken) staleRemoved += 1;
      if (failure!.retryable) {
        retryDelay = Math.max(retryDelay, failure!.retryAfterSeconds ?? 0);
        retryableFailure = { ...failure!, retryAfterSeconds: retryDelay };
      } else {
        terminalFailure = failure;
      }
      if (failure!.global) break;
    }
    // Confirmed temporary rejections retry only their individual device;
    // accepted devices are retained in the database and skipped next time.
    const failure = terminalFailure?.global
      ? terminalFailure
      : retryableFailure ?? terminalFailure;
    if (failure) {
      const status = failure.retryable ? "retryable" : "terminal";
      if (
        !await finish(
          status,
          deliveredCount,
          failure.category,
          failure.retryAfterSeconds,
        )
      ) return json({ error: "finish failed" }, 503);
      return json(
        { error: failure.category, sent: deliveredCount },
        failure.retryable || failure.global ? 503 : 422,
      );
    }
    const outcome = deliveredCount > 0 ? "sent" : "no_devices";
    if (!await finish(outcome, deliveredCount)) {
      return json({ error: "finish failed" }, 503);
    }
    return json({ ok: true, sent: deliveredCount, staleRemoved });
  } catch (error) {
    if (externalSendStarted) {
      await finish("terminal", deliveredCount, "DELIVERY_OUTCOME_UNKNOWN");
      return json({ error: "delivery outcome uncertain" }, 503);
    }
    const message = String(error);
    const category = message.includes("FCM_SERVICE_ACCOUNT_INVALID")
      ? "FCM_SERVICE_ACCOUNT_INVALID"
      : message.includes("FCM_OAUTH_400") ||
          message.includes("FCM_OAUTH_401") ||
          message.includes("FCM_OAUTH_403")
      ? "AUTH_CONFIGURATION"
      : "NETWORK_ERROR";
    const status = category === "NETWORK_ERROR" ? "retryable" : "terminal";
    await finish(status, 0, category);
    return json({ error: category }, 503);
  }
}
