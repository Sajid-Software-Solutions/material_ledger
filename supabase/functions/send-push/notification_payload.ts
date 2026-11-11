import { moduleEvents, workflowEvents } from "./module_catalogue.ts";
export type PushClaim = {
  claimId: string;
  expiresAt?: string;
  notificationId: string;
  recipientAuthUserId: string;
  eventCode: string;
  entityType: string;
  entityId: string;
  requestId?: string | null;
  moduleRoute?: string | null;
  projectId?: string | null;
  chatConversationId?: string | null;
  unreadCount?: number;
  attemptCount: number;
};

export type PushCopy = {
  title: string;
  body: string;
  type: "request" | "project" | "info";
};

export function isTeamChatEvent(eventCode: string): boolean {
  return eventCode === "team_chat_message" ||
    eventCode === "team_chat_mention";
}

/// Keeps every platform-specific badge within the same safe, compact range.
/// A rolling database deployment may briefly omit the value, so malformed or
/// absent claims fail to zero instead of leaking an arbitrary payload value.
export function normalizedUnreadCount(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(999, Math.trunc(value)));
}

export function normalizedPushLanguage(locale: unknown = "en"): string {
  if (typeof locale !== "string") return "en";
  const language = locale.toLowerCase().split(/[-_]/, 1)[0];
  return ["en", "ar", "ur", "hi"].includes(language) ? language : "en";
}

export function safePushCopy(
  eventCode: string,
  locale: unknown = "en",
): PushCopy {
  const language = normalizedPushLanguage(locale);
  const module = moduleEvents[eventCode];
  if (module) {
    return {
      title: module.title[language],
      body: module.body[language],
      type: "info",
    };
  }
  const workflow = workflowEvents[eventCode] ?? workflowEvents._fallback;
  return {
    title: workflow.title[language],
    body: workflow.body[language],
    type: workflow.type,
  };
}

function exactDailyRosterRoute(claim: PushClaim): string | null {
  if (
    claim.eventCode !== "workforce_daily_attendance_missing" ||
    claim.entityType !== "workforce_daily_roster" || !claim.moduleRoute ||
    typeof claim.entityId !== "string"
  ) return null;
  const match =
    /^\/yorks\/workforce\/attendance\?team_id=([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})&date=(\d{4}-\d{2}-\d{2})$/i
      .exec(claim.moduleRoute);
  if (
    !match || match[1].toLowerCase() !== claim.entityId.toLowerCase() ||
    match[2].startsWith("0000-")
  ) return null;
  const date = new Date(`${match[2]}T00:00:00.000Z`);
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== match[2]
  ) return null;
  return claim.moduleRoute;
}

export function routeFor(claim: PushClaim): string {
  if (moduleEvents[claim.eventCode] && claim.eventCode.startsWith("rental_")) {
    if (claim.eventCode === "rental_completeness_review") {
      return claim.entityType === "rental_portfolio"
        ? "/rentals"
        : "/notifications";
    }
    if (
      claim.entityType === "rental_property" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(claim.entityId)
    ) {
      return `/rentals/${claim.entityId}`;
    }
    return "/notifications";
  }
  const dailyRoster = exactDailyRosterRoute(claim);
  if (dailyRoster) return dailyRoster;
  // Server resolves parent invoice/period identifiers. Accept only our module
  // namespaces; never trust an arbitrary external or authentication URL.
  if (
    claim.moduleRoute &&
    /^\/yorks\/(?:projects\/[0-9a-f-]{36}\/accounts\/(?:client-invoices|receipts-pdc|supplier-bills)|workforce\/timesheets)\?[a-z_]+=[0-9a-f-]{36}(?:&[a-z_]+=[0-9a-f-]{36})?$/i
      .test(claim.moduleRoute)
  ) {
    return claim.moduleRoute;
  }
  const module = moduleEvents[claim.eventCode];

  if (module) {
    if (claim.eventCode.startsWith("accounts_")) {
      if (!claim.projectId || !/^[0-9a-f-]{36}$/i.test(claim.projectId)) {
        return "/yorks/accounts";
      }
      const section = module.destination === "invoices"
        ? "client-invoices"
        : module.destination;
      return `/yorks/projects/${claim.projectId}/accounts/${section}`;
    }
    return `/yorks/workforce/${module.destination}`;
  }
  const requestId = claim.requestId;
  if (
    claim.eventCode === "material_request_mentioned" &&
    typeof requestId === "string" &&
    /^[0-9a-f-]{36}$/i.test(requestId) &&
    claim.entityType === "chat_message" &&
    /^[0-9a-f-]{36}$/i.test(claim.entityId)
  ) {
    return `/yorks/material-requests/${requestId}?comment=${claim.entityId}`;
  }
  const chatId = claim.chatConversationId;
  if (typeof chatId === "string" && /^[0-9a-f-]{36}$/i.test(chatId)) {
    return `/yorks/team-chat/${chatId}`;
  }
  if (
    claim.entityType === "material_return" &&
    /^[0-9a-f-]{36}$/i.test(claim.entityId)
  ) {
    return `/yorks/returns/${claim.entityId}`;
  }
  if (
    claim.entityType === "company_material_request" &&
    /^[0-9a-f-]{36}$/i.test(claim.entityId)
  ) {
    return `/yorks/material-requests/company/${claim.entityId}`;
  }
  const id = requestId;
  if (typeof id === "string" && /^[0-9a-f-]{36}$/i.test(id)) {
    return `/yorks/material-requests/${id}`;
  }
  if (
    (claim.entityType === "project" || claim.entityType === "project_member") &&
    typeof claim.projectId === "string" &&
    /^[0-9a-f-]{36}$/i.test(claim.projectId)
  ) {
    return `/yorks/projects/${claim.projectId}`;
  }
  return "/notifications";
}

export function webLinkFor(
  route: string,
  origin: string,
  notificationId = "",
): string | null {
  try {
    const base = new URL(origin);
    if (base.protocol !== "https:") return null;
    if (!route.startsWith("/") || route.startsWith("//")) return null;
    const target = new URL(route, "https://yorks.invalid");
    if (/^[0-9a-f-]{36}$/i.test(notificationId)) {
      target.searchParams.set("notificationId", notificationId);
    }
    base.pathname = "/";
    base.search = "";
    base.hash = `#${target.pathname}${target.search}`;
    return base.toString();
  } catch {
    return null;
  }
}

// Expiry is anchored to the durable event, never extended by a retry.
export function remainingLifetime(
  expiresAt: string | undefined,
  now = Date.now(),
): number {
  const expiry = Date.parse(expiresAt ?? "");
  return Number.isFinite(expiry)
    ? Math.max(0, Math.min(86400, Math.floor((expiry - now) / 1000)))
    : 0;
}
