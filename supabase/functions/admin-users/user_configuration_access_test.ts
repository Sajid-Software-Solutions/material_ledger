import { assertEquals } from "jsr:@std/assert@1";

import {
  canConfigureUsers,
  canUseLegacyUserAdministration,
} from "./user_configuration_access.ts";

Deno.test("only Admin, Senior Mechanical Engineer and PR configure users", () => {
  assertEquals(canConfigureUsers("admin"), true);
  assertEquals(canConfigureUsers("senior_mechanical_engineer"), true);
  assertEquals(canConfigureUsers("pr"), true);
  assertEquals(canConfigureUsers("project_manager"), false);
  assertEquals(canConfigureUsers("project_engineer"), false);
  assertEquals(canConfigureUsers("procurement"), false);
  assertEquals(canConfigureUsers("accountant"), false);
  assertEquals(canConfigureUsers(null), false);
});

Deno.test("legacy administration is exact-Admin and explicitly enabled", () => {
  assertEquals(canUseLegacyUserAdministration("admin", "true"), true);
  assertEquals(
    canUseLegacyUserAdministration("senior_mechanical_engineer", "true"),
    false,
  );
  assertEquals(canUseLegacyUserAdministration("pr", "true"), false);
  assertEquals(canUseLegacyUserAdministration("admin", undefined), false);
  assertEquals(canUseLegacyUserAdministration("admin", "TRUE"), false);
});
