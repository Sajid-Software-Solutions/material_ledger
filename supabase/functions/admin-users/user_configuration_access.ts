const USER_CONFIGURATION_ROLES = new Set([
  "admin",
  "senior_mechanical_engineer",
  "pr",
]);

/// Exact server-controlled roles allowed to operate the protected user
/// configuration gateway. Active-user validation remains a separate required
/// check against the live Auth record.
export function canConfigureUsers(role: unknown): boolean {
  return typeof role === "string" && USER_CONFIGURATION_ROLES.has(role);
}

/// The quarantined pre-V1 shell is opt-in at the server and remains an exact
/// Admin-only recovery path. Missing, mixed-case and whitespace values all
/// fail closed so production is off unless explicitly configured.
export function canUseLegacyUserAdministration(
  exactRole: unknown,
  featureFlag: unknown,
): boolean {
  return exactRole === "admin" && featureFlag === "true";
}
