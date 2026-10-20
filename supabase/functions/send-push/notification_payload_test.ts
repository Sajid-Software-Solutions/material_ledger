import { assertEquals } from "jsr:@std/assert@1";
import {
  isTeamChatEvent,
  normalizedPushLanguage,
  normalizedUnreadCount,
  type PushClaim,
  routeFor,
  safePushCopy,
  webLinkFor,
} from "./notification_payload.ts";

const claim = (requestId?: string | null): PushClaim => ({
  claimId: "00000000-0000-4000-8000-000000000001",
  notificationId: "11000000-0000-4000-8000-000000000001",
  recipientAuthUserId: "12000000-0000-4000-8000-000000000001",
  eventCode: "material_request_submitted",
  entityType: "material_request",
  entityId: "13000000-0000-4000-8000-000000000001",
  requestId,
  attemptCount: 1,
});

Deno.test("badge counts are finite server-owned integers", () => {
  assertEquals(normalizedUnreadCount(12.8), 12);
  assertEquals(normalizedUnreadCount(1200), 999);
  assertEquals(normalizedUnreadCount(-4), 0);
  assertEquals(normalizedUnreadCount("17"), 0);
  assertEquals(normalizedUnreadCount(undefined), 0);
});

Deno.test("trusted event copy is server-owned and non-commercial", () => {
  const copy = safePushCopy("material_request_submitted");
  assertEquals(copy.title, "New material request");
  assertEquals(copy.type, "request");
  assertEquals(copy.body.includes("cost"), false);
  assertEquals(copy.body.includes("quantity"), false);
});

Deno.test("unknown events use a safe generic envelope", () => {
  assertEquals(safePushCopy("future_event"), {
    title: "Yorks workflow update",
    body: "A record assigned to you has changed.",
    type: "info",
  });
});

Deno.test("deep link accepts only a resolved UUID request id", () => {
  const requestId = "14000000-0000-4000-8000-000000000001";
  assertEquals(
    routeFor(claim(requestId)),
    `/yorks/material-requests/${requestId}`,
  );
  assertEquals(routeFor(claim("//attacker.example")), "/notifications");
  assertEquals(routeFor(claim(null)), "/notifications");
});

Deno.test("project membership alerts use the protected project route", () => {
  assertEquals(
    routeFor({
      ...claim(null),
      entityType: "project_member",
      projectId: "15000000-0000-4000-8000-000000000001",
    }),
    "/yorks/projects/15000000-0000-4000-8000-000000000001",
  );
});

Deno.test("Team Chat alerts use trusted copy and the exact conversation route", () => {
  const conversationId = "16000000-0000-4000-8000-000000000001";
  assertEquals(safePushCopy("team_chat_message"), {
    title: "New Team Chat message",
    body: "A conversation you participate in has a new message.",
    type: "info",
  });
  assertEquals(
    safePushCopy("team_chat_mention").title,
    "You were mentioned in Team Chat",
  );
  assertEquals(isTeamChatEvent("team_chat_message"), true);
  assertEquals(isTeamChatEvent("team_chat_mention"), true);
  // Preserved pre-Team-Chat Material Request mentions keep their workflow
  // event; all new contextual Chat mentions use Team Chat's own code.
  assertEquals(isTeamChatEvent("material_request_mentioned"), false);
  assertEquals(isTeamChatEvent("material_request_submitted"), false);
  assertEquals(
    routeFor({
      ...claim(null),
      entityType: "chat_conversation",
      chatConversationId: conversationId,
    }),
    `/yorks/team-chat/${conversationId}`,
  );
  assertEquals(
    routeFor({
      ...claim(null),
      chatConversationId: "//attacker.example",
    }),
    "/notifications",
  );
});

Deno.test("Material Request mentions override the transport conversation route", () => {
  const requestId = "14000000-0000-4000-8000-000000000001";
  const commentId = "17000000-0000-4000-8000-000000000001";
  assertEquals(
    routeFor({
      ...claim(requestId),
      eventCode: "material_request_mentioned",
      entityType: "chat_message",
      entityId: commentId,
      chatConversationId: "16000000-0000-4000-8000-000000000001",
    }),
    `/yorks/material-requests/${requestId}?comment=${commentId}`,
  );
});

Deno.test("approval-first and return events have specific safe copy", () => {
  assertEquals(
    safePushCopy("material_request_approval_required").title,
    "Material request approval required",
  );
  assertEquals(
    safePushCopy("material_return_confirmed").title,
    "Material return confirmed",
  );
  for (
    const eventCode of [
      "material_return_approval_required",
      "material_return_approved",
      "material_return_returned_for_changes",
      "material_return_rejected",
      "material_return_receipt_required",
      "material_return_confirmed",
      "material_return_cancelled",
    ]
  ) {
    assertEquals(
      safePushCopy(eventCode).title === "Yorks workflow update",
      false,
    );
  }
});

Deno.test("material returns deep-link to their standalone record", () => {
  const returnId = "17000000-0000-4000-8000-000000000001";
  assertEquals(
    routeFor({
      ...claim("14000000-0000-4000-8000-000000000001"),
      entityType: "material_return",
      entityId: returnId,
    }),
    `/yorks/returns/${returnId}`,
  );
});

Deno.test("coordination assignment has specific non-commercial copy", () => {
  const copy = safePushCopy("material_request_work_assigned");
  assertEquals(copy.title, "Material request assigned to you");
  assertEquals(copy.type, "request");
  assertEquals(copy.body.includes("cost"), false);
  assertEquals(copy.body.includes("quantity"), false);
});

Deno.test("Engineering preparation completion is informational in every language", () => {
  for (const language of ["en", "ar", "ur", "hi"]) {
    const copy = safePushCopy("arrangement_preparation_completed", language);
    assertEquals(copy.type, "info");
    assertEquals(
      copy.title === safePushCopy("unknown_event", language).title,
      false,
    );
    assertEquals(copy.body.trim().length > 0, true);
  }
  assertEquals(
    safePushCopy("arrangement_preparation_completed").title,
    "Materials prepared",
  );
  assertEquals(
    routeFor({
      ...claim("14000000-0000-4000-8000-000000000001"),
      eventCode: "arrangement_preparation_completed",
      entityType: "procurement_arrangement",
    }),
    "/yorks/material-requests/14000000-0000-4000-8000-000000000001",
  );
});

Deno.test("all-unavailable alert preserves the editable or cancellable state", () => {
  const copy = safePushCopy("arrangement_completed_unavailable");
  assertEquals(copy.title, "All items currently unavailable");
  assertEquals(copy.body.includes("Procurement can revise"), true);
  assertEquals(copy.body.includes("cancel the request"), true);
  assertEquals(copy.body.toLowerCase().includes("completed"), false);
});

Deno.test("web link is absolute HTTPS and rejects unsafe configuration", () => {
  assertEquals(
    webLinkFor(
      "/yorks/material-requests/14000000-0000-4000-8000-000000000001",
      "https://yorks-r35.vercel.app",
      "11000000-0000-4000-8000-000000000001",
    ),
    "https://yorks-r35.vercel.app/#/yorks/material-requests/14000000-0000-4000-8000-000000000001?notificationId=11000000-0000-4000-8000-000000000001",
  );
  assertEquals(
    webLinkFor("//attacker.example", "https://yorks-r35.vercel.app"),
    null,
  );
  assertEquals(webLinkFor("/notifications", "http://localhost:8080"), null);
  assertEquals(webLinkFor("/notifications", "not-an-origin"), null);
});

Deno.test("Company Request alerts have meaningful copy and exact protected routes", () => {
  const fixture = {
    ...claim(),
    entityType: "company_material_request",
    eventCode: "company_material_request_approval_requested",
  };
  assertEquals(
    safePushCopy(fixture.eventCode).title,
    "Company request approval required",
  );
  assertEquals(
    routeFor(fixture),
    `/yorks/material-requests/company/${fixture.entityId}`,
  );
  for (
    const code of [
      "approved",
      "returned",
      "rejected",
      "supply_planned",
      "dispatched",
      "received",
      "handed_over",
      "return_confirmed",
      "return_submitted",
      "return_rejected",
      "remainder_withdrawn",
      "cancelled",
      "closed",
    ]
  ) {
    assertEquals(
      safePushCopy(`company_material_request_${code}`).type,
      "request",
    );
  }
});

Deno.test("expiry is absolute and malformed/missing expiry fails closed", async () => {
  const { remainingLifetime } = await import("./notification_payload.ts");
  const now = Date.parse("2026-09-30T12:00:00Z");
  assertEquals(remainingLifetime("2026-09-30T12:00:30Z", now), 30);
  assertEquals(remainingLifetime("2026-09-30T11:59:00Z", now), 0);
  assertEquals(remainingLifetime(undefined, now), 0);
  assertEquals(remainingLifetime("invalid", now), 0);
});

Deno.test("module catalogue covers safe copy and guarded routes", async () => {
  const { moduleEvents } = await import("./module_catalogue.ts");
  for (const code of Object.keys(moduleEvents)) {
    assertEquals(safePushCopy(code).title === "Yorks workflow update", false);
    assertEquals(
      routeFor({
        ...claim(),
        eventCode: code,
        entityType: code.startsWith("rental_")
          ? (code === "rental_completeness_review"
            ? "rental_portfolio"
            : "rental_property")
          : claim().entityType,
      }).startsWith(code.startsWith("rental_") ? "/rentals" : "/yorks/"),
      true,
    );
  }
});

Deno.test("module destination retains parent record and rejects external URLs", () => {
  const target =
    "/yorks/projects/ab100000-0000-4000-8000-000000000001/accounts/client-invoices?invoice_id=ab200000-0000-4000-8000-000000000001";
  assertEquals(
    routeFor({
      ...claim(),
      eventCode: "accounts_claim_returned",
      moduleRoute: target,
    }),
    target,
  );
  assertEquals(
    routeFor({
      ...claim(),
      eventCode: "accounts_claim_returned",
      moduleRoute: "https://evil.test",
    }),
    "/yorks/accounts",
  );
});

Deno.test("workflow and module copy uses all supported installation languages", async () => {
  const { moduleEvents, workflowEvents } = await import(
    "./module_catalogue.ts"
  );
  for (
    const [code, event] of Object.entries({
      ...moduleEvents,
      ...workflowEvents,
    })
  ) {
    for (const language of ["en", "ar", "ur", "hi"]) {
      assertEquals(safePushCopy(code, language).title, event.title[language]);
      assertEquals(safePushCopy(code, language).body, event.body[language]);
    }
  }
  assertEquals(safePushCopy("future_event", "ar").title, "تحديث سير عمل يوركس");
  assertEquals(
    safePushCopy("future_event", "hi").body,
    "आपको सौंपा गया रिकॉर्ड बदल गया है।",
  );
  assertEquals(normalizedPushLanguage("UR-pk"), "ur");
  assertEquals(normalizedPushLanguage("ar_AE"), "ar");
  assertEquals(normalizedPushLanguage("unsupported"), "en");
  assertEquals(normalizedPushLanguage(null), "en");
  assertEquals(
    safePushCopy("material_request_submitted", "unsupported"),
    safePushCopy("material_request_submitted"),
  );
});

Deno.test("Accounts and Workforce copy names the relevant record and action", async () => {
  const { moduleEvents } = await import("./module_catalogue.ts");
  for (const code of Object.keys(moduleEvents)) {
    const copy = safePushCopy(code);
    assertEquals(copy.body.includes("Open the workspace"), false);
    assertEquals(copy.title === "Yorks workflow update", false);
  }
  assertEquals(
    safePushCopy("accounts_supplier_bill_ready").body,
    "Review the matched supplier bill before approving payment.",
  );
  assertEquals(
    safePushCopy("workforce_period_returned").body,
    "Review the return reason and correct the monthly timesheet.",
  );
});

Deno.test("daily digest opens only its trusted exact team and calendar date", () => {
  const teamId = "ab500000-0000-4000-8000-000000000001";
  const route = `/yorks/workforce/attendance?team_id=${teamId}&date=2026-08-30`;
  const daily = {
    ...claim(),
    eventCode: "workforce_daily_attendance_missing",
    entityType: "workforce_daily_roster",
    entityId: teamId,
    moduleRoute: route,
  };
  assertEquals(routeFor(daily), route);
  assertEquals(
    routeFor({
      ...daily,
      moduleRoute: route.replace("2026-08-30", "2028-02-29"),
    }),
    route.replace("2026-08-30", "2028-02-29"),
  );
  for (
    const malformed of [
      route.replace("2026-08-30", "2026-02-30"),
      route.replace("2026-08-30", "0000-01-01"),
      route.replace(teamId, "not-a-team"),
      route.replace(teamId, "ab500000-0000-4000-8000-000000000002"),
      `${route}&redirect=https://attacker.example`,
      `https://attacker.example${route}`,
    ]
  ) {
    assertEquals(
      routeFor({ ...daily, moduleRoute: malformed }),
      "/yorks/workforce/attendance",
    );
  }
  assertEquals(
    routeFor({ ...daily, entityType: "workforce_monthly_period" }),
    "/yorks/workforce/attendance",
  );
  assertEquals(
    routeFor({ ...daily, eventCode: "workforce_period_submitted" }),
    "/yorks/workforce/timesheets",
  );
});

Deno.test("requested delivery check is explicit and opens the existing protected request", () => {
  const requestId = "14000000-0000-4000-8000-000000000001";
  const fixture = {
    ...claim(requestId),
    eventCode: "notification_delivery_check",
  };
  const copy = safePushCopy(fixture.eventCode);
  assertEquals(copy.title, "Yorks device alert check");
  assertEquals(
    copy.body,
    "This is the notification delivery check you requested. Open to view the linked Yorks record.",
  );
  assertEquals(copy.type, "info");
  for (const language of ["en", "ar", "ur", "hi"]) {
    assertEquals(
      safePushCopy(fixture.eventCode, language).title ===
        safePushCopy("future_event", language).title,
      false,
    );
    assertEquals(
      safePushCopy(fixture.eventCode, language).body.length > 0,
      true,
    );
  }
  assertEquals(routeFor(fixture), `/yorks/material-requests/${requestId}`);
});

Deno.test("rental events use exact property routes and reject unrelated payload destinations", () => {
  const property = "83000000-0000-4000-8000-000000000010";
  for (
    const code of [
      "rental_lease_notice_due",
      "rental_lease_expired",
      "rental_cheque_due",
      "rental_cheque_returned",
      "rental_rent_due",
      "rental_rent_overdue",
    ]
  ) {
    const rental = {
      ...claim(),
      eventCode: code,
      entityType: "rental_property",
      entityId: property,
      moduleRoute:
        "/yorks/projects/83000000-0000-4000-8000-000000000011/accounts/receipts-pdc?invoice_id=83000000-0000-4000-8000-000000000012",
    };
    assertEquals(routeFor(rental), `/rentals/${property}`);
    assertEquals(
      routeFor({ ...rental, entityType: "material_request" }),
      "/notifications",
    );
    assertEquals(
      routeFor({ ...rental, entityId: "//attacker.example" }),
      "/notifications",
    );
    for (const language of ["en", "ar", "ur", "hi"]) {
      assertEquals(safePushCopy(code, language).title.length > 0, true);
      assertEquals(safePushCopy(code, language).body.includes("AED"), false);
    }
  }
  assertEquals(
    routeFor({
      ...claim(),
      eventCode: "rental_completeness_review",
      entityType: "rental_portfolio",
    }),
    "/rentals",
  );
});
