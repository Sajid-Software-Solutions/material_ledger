export const DEFAULT_CAPS: Readonly<Record<string, readonly string[]>> = {
  admin: [
    "viewCommercials",
    "salary",
    "finance",
    "rentals",
    "writeRentals",
    "people",
    "writePeople",
    "goods",
    "approveLeave",
  ],
  procurement: [
    "viewCommercials",
    "rentals",
    "writeRentals",
    "people",
    "writePeople",
    "goods",
    "approveLeave",
  ],
  // Accounts commands are resolved by protected Postgres capabilities. Keep
  // legacy shell claims empty so provisioning cannot manufacture technical,
  // inventory or general finance access for Accountant.
  accountant: [],
  // PR's people, Workforce, Rentals and read-only access resolves through
  // protected Postgres capabilities, never through legacy shell claims.
  pr: [],
  project_engineer: [],
  site_engineer: [],
  senior_mechanical_engineer: [],
  project_manager: [],
  workshop_in_charge: [],
  document_controller: [],
};

const PROVISIONABLE_ROLES = new Set(Object.keys(DEFAULT_CAPS));

export function provisionableRole(value: unknown): string | null {
  if (typeof value !== "string" || !PROVISIONABLE_ROLES.has(value)) {
    return null;
  }
  return value;
}

export function provisionableRoles(
  value: unknown,
  primary: string,
): string[] | null {
  if (value == null) return [primary];
  if (!Array.isArray(value) || value.length !== 1 || value[0] !== primary) {
    return null;
  }
  return [primary];
}

/// V1 roles and compatibility claims are server-owned. Exact-role commands
/// reject every caller-supplied capability or legacy-shell switch instead of
/// silently filtering it into a different request.
export function hasForbiddenV1ClaimInput(
  body: Readonly<Record<string, unknown>>,
): boolean {
  return Object.prototype.hasOwnProperty.call(body, "caps") ||
    Object.prototype.hasOwnProperty.call(body, "legacyShell");
}

export function defaultCapsForRoles(roles: readonly string[]): string[] {
  return [...new Set(roles.flatMap((role) => DEFAULT_CAPS[role] ?? []))];
}
