export type PushClaim = {
  claimId: string;
  notificationId: string;
  recipientAuthUserId: string;
  eventCode: string;
  entityType: string;
  entityId: string;
  requestId?: string | null;
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

export function safePushCopy(eventCode: string): PushCopy {
  switch (eventCode) {
    case "company_material_request_approval_requested":
      return {
        title: "Company request approval required",
        body: "A company material request is waiting for your decision.",
        type: "request",
      };
    case "company_material_request_approved":
      return {
        title: "Company request approved",
        body: "Your company material request was approved.",
        type: "request",
      };
    case "company_material_request_returned":
      return {
        title: "Company request changes required",
        body: "Your company material request was returned with a reason.",
        type: "request",
      };
    case "company_material_request_rejected":
      return {
        title: "Company request rejected",
        body: "Your company material request was rejected with a reason.",
        type: "request",
      };
    case "company_material_request_supply_planned":
      return {
        title: "Company request supply planned",
        body: "Procurement updated the supply plan for your company request.",
        type: "request",
      };
    case "company_material_request_dispatched":
      return {
        title: "Company materials dispatched",
        body: "Company materials are waiting for your receipt review.",
        type: "request",
      };
    case "company_material_request_received":
      return {
        title: "Company materials received",
        body: "Good received quantities are ready for beneficiary handover.",
        type: "request",
      };
    case "company_material_request_handed_over":
      return {
        title: "Beneficiary handover confirmed",
        body: "The company material beneficiary handover was recorded.",
        type: "request",
      };
    case "company_material_request_return_confirmed":
      return {
        title: "Company material return confirmed",
        body:
          "Procurement confirmed physical receipt of the returned material.",
        type: "request",
      };
    case "company_material_request_return_submitted":
      return {
        title: "Company material return awaiting confirmation",
        body: "Review the returned items and confirm physical receipt.",
        type: "request",
      };
    case "company_material_request_return_rejected":
      return {
        title: "Company material return rejected",
        body: "Open the request to review the reason.",
        type: "request",
      };
    case "company_material_request_remainder_withdrawn":
      return {
        title: "Company remaining need withdrawn",
        body: "Open the request to review the remaining quantities.",
        type: "request",
      };
    case "company_material_request_cancelled":
      return {
        title: "Company request cancelled",
        body: "Open the request to review the cancellation reason.",
        type: "request",
      };
    case "company_material_request_closed":
      return {
        title: "Company request closed",
        body: "The completed company material request was closed.",
        type: "request",
      };
    case "material_request_approval_required":
    case "material_request_updated_for_approval":
      return {
        title: "Material request approval required",
        body: "A material request is ready for Engineering approval.",
        type: "request",
      };
    case "material_request_approved_for_arrangement":
      return {
        title: "Material request approved",
        body: "Engineering approved the request for Procurement arrangement.",
        type: "request",
      };
    case "material_request_changes_requested":
      return {
        title: "Material request changes required",
        body: "Engineering returned the request with a reason.",
        type: "request",
      };
    case "material_request_mentioned":
      return {
        title: "You were mentioned",
        body: "A teammate mentioned you in a material request comment.",
        type: "info",
      };
    case "material_request_work_assigned":
      return {
        title: "Material request assigned to you",
        body: "A teammate assigned you responsibility for a material request.",
        type: "request",
      };
    case "team_chat_message":
      return {
        title: "New Team Chat message",
        body: "A conversation you participate in has a new message.",
        type: "info",
      };
    case "team_chat_mention":
      return {
        title: "You were mentioned in Team Chat",
        body: "A teammate mentioned you in a conversation.",
        type: "info",
      };
    case "material_request_submitted":
      return {
        title: "New material request",
        body: "A material request is ready for Procurement arrangement.",
        type: "request",
      };
    case "arrangement_review_required":
      return {
        title: "Arrangement ready for review",
        body: "Procurement submitted an arrangement for Engineering approval.",
        type: "request",
      };
    case "arrangement_approved":
      return {
        title: "Arrangement approved",
        body: "The material request is ready for controlled dispatch.",
        type: "request",
      };
    case "arrangement_returned":
      return {
        title: "Arrangement returned",
        body: "Engineering returned the arrangement to Procurement.",
        type: "request",
      };
    case "arrangement_ready_for_dispatch":
      return {
        title: "Materials ready for dispatch",
        body: "Procurement completed the approved arrangement.",
        type: "request",
      };
    case "arrangement_completed_unavailable":
      return {
        title: "All items currently unavailable",
        body:
          "Procurement can revise the arrangement, or an authorised reviewer can cancel the request.",
        type: "request",
      };
    case "receipt_review_required":
      return {
        title: "Delivery ready for receipt review",
        body: "Dispatched materials are awaiting the project team review.",
        type: "request",
      };
    case "receipt_review_confirmed":
      return {
        title: "Receipt review confirmed",
        body: "The project team recorded the delivered material condition.",
        type: "request",
      };
    case "material_return_submitted":
      return {
        title: "Material return submitted",
        body: "A project material return is awaiting Procurement confirmation.",
        type: "request",
      };
    case "material_return_approval_required":
      return {
        title: "Material return approval required",
        body: "A project material return is ready for Engineering review.",
        type: "request",
      };
    case "material_return_approved":
      return {
        title: "Material return approved",
        body: "Engineering approved the material return for site dispatch.",
        type: "request",
      };
    case "material_return_returned_for_changes":
      return {
        title: "Material return changes required",
        body: "Engineering returned the material return with a reason.",
        type: "request",
      };
    case "material_return_receipt_required":
      return {
        title: "Returned materials awaiting receipt",
        body: "Dispatched return materials are ready for Procurement receipt.",
        type: "request",
      };
    case "material_return_confirmed":
      return {
        title: "Material return confirmed",
        body:
          "Procurement confirmed physical receipt of the returned material.",
        type: "request",
      };
    case "material_return_rejected":
      return {
        title: "Material return rejected",
        body: "Procurement returned the material return with a reason.",
        type: "request",
      };
    case "material_return_cancelled":
      return {
        title: "Material return cancelled",
        body: "The material return was cancelled before warehouse receipt.",
        type: "request",
      };
    case "material_request_cancelled":
      return {
        title: "Material request cancelled",
        body: "The material request was cancelled and open work was released.",
        type: "request",
      };
    case "material_request_closed":
      return {
        title: "Material request completed",
        body: "The received material request was closed.",
        type: "request",
      };
    case "project_member_assigned":
      return {
        title: "Project access assigned",
        body: "You were assigned to a Yorks project.",
        type: "project",
      };
    case "project_member_revoked":
      return {
        title: "Project access changed",
        body: "Your active assignment to a Yorks project ended.",
        type: "project",
      };
    default:
      return {
        title: "Yorks workflow update",
        body: "A record assigned to you has changed.",
        type: "info",
      };
  }
}

export function routeFor(claim: PushClaim): string {
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
