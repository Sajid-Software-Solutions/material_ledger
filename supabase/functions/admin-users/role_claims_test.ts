import { assertEquals } from "jsr:@std/assert@1";

import {
  defaultCapsForRoles,
  hasForbiddenV1ClaimInput,
  provisionableRole,
  provisionableRoles,
} from "./role_claims.ts";

Deno.test("all ten exact V1 roles are accepted as primary claims", () => {
  for (
    const role of [
      "admin",
      "procurement",
      "accountant",
      "pr",
      "project_engineer",
      "site_engineer",
      "senior_mechanical_engineer",
      "project_manager",
      "workshop_in_charge",
      "document_controller",
    ]
  ) {
    assertEquals(provisionableRole(role), role);
  }
  assertEquals(provisionableRole("engineer"), null);
});

Deno.test("V1 accepts only one exact server-owned role", () => {
  assertEquals(
    provisionableRoles(
      ["senior_mechanical_engineer"],
      "senior_mechanical_engineer",
    ),
    ["senior_mechanical_engineer"],
  );
  assertEquals(provisionableRoles(undefined, "project_manager"), [
    "project_manager",
  ]);
  assertEquals(
    provisionableRoles(["project_manager", "invalid"], "project_manager"),
    null,
  );
  assertEquals(
    provisionableRoles(
      ["workshop_in_charge", "document_controller"],
      "workshop_in_charge",
    ),
    null,
  );
});

Deno.test("V1 exact-role commands reject legacy and capability input", () => {
  assertEquals(hasForbiddenV1ClaimInput({ role: "admin" }), false);
  assertEquals(hasForbiddenV1ClaimInput({ caps: [] }), true);
  assertEquals(hasForbiddenV1ClaimInput({ legacyShell: false }), true);
});

Deno.test("role capability defaults are server-derived", () => {
  assertEquals(defaultCapsForRoles(["accountant"]), []);
  assertEquals(defaultCapsForRoles(["senior_mechanical_engineer"]), []);
  assertEquals(
    defaultCapsForRoles(["procurement"]),
    [
      "viewCommercials",
      "rentals",
      "writeRentals",
      "people",
      "writePeople",
      "goods",
      "approveLeave",
    ],
  );
});
