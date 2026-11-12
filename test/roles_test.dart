import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/user_role.dart';

void main() {
  group('UserRole compatibility capability matrix', () {
    test('Accountant is explicit and is never merged into another role', () {
      expect(UserRole.values, [
        UserRole.engineer,
        UserRole.procurement,
        UserRole.accountant,
        UserRole.pr,
        UserRole.admin,
      ]);
    });

    test('PR runs people and rentals, never materials or commercials', () {
      expect(UserRole.pr.canAccessMaterials, false);
      expect(UserRole.pr.canSeeCost, false);
      expect(UserRole.pr.canViewFinance, false);
      expect(UserRole.pr.canAccessPeople, true);
      expect(UserRole.pr.canWritePeople, true);
      expect(UserRole.pr.canAccessRentals, true);
      expect(UserRole.pr.canWriteRentals, true);
      expect(UserRole.pr.canApproveLeave, true);
      expect(UserRole.pr.canReceiveGoods, false);
      expect(UserRole.pr.isAdmin, false);
    });

    test('cost visibility — Admin/Procurement only (FR-092)', () {
      expect(UserRole.admin.canSeeCost, true);
      expect(UserRole.procurement.canSeeCost, true);
      expect(UserRole.engineer.canSeeCost, false);
      expect(UserRole.accountant.canSeeCost, false);
    });

    test('salary visibility — Admin only (FR-128)', () {
      expect(UserRole.admin.canSeeSalary, true);
      expect(UserRole.procurement.canSeeSalary, false);
      expect(UserRole.engineer.canSeeSalary, false);
      expect(UserRole.accountant.canSeeSalary, false);
    });

    test('rentals access + write — Procurement/Admin', () {
      expect(UserRole.procurement.canAccessRentals, true);
      expect(UserRole.admin.canAccessRentals, true);
      expect(UserRole.engineer.canAccessRentals, false);
      expect(UserRole.accountant.canAccessRentals, false);

      expect(UserRole.procurement.canWriteRentals, true);
      expect(UserRole.admin.canWriteRentals, true);
      expect(UserRole.engineer.canWriteRentals, false);
      expect(UserRole.accountant.canWriteRentals, false);
    });

    test(
      'people/HR access + write — Procurement/Admin (HR moved to procurement)',
      () {
        expect(UserRole.procurement.canAccessPeople, true);
        expect(UserRole.admin.canAccessPeople, true);
        expect(UserRole.engineer.canAccessPeople, false);
        expect(UserRole.accountant.canAccessPeople, false);

        expect(UserRole.procurement.canWritePeople, true);
        expect(UserRole.admin.canWritePeople, true);
        expect(UserRole.engineer.canWritePeople, false);
        expect(UserRole.accountant.canWritePeople, false);
      },
    );

    test('goods receipt — Procurement/Admin; finance — Admin only', () {
      expect(UserRole.procurement.canReceiveGoods, true);
      expect(UserRole.admin.canReceiveGoods, true);
      expect(UserRole.engineer.canReceiveGoods, false);
      expect(UserRole.accountant.canReceiveGoods, false);

      expect(UserRole.admin.canViewFinance, true);
      expect(UserRole.procurement.canViewFinance, false);
      expect(UserRole.engineer.canViewFinance, false);
      expect(UserRole.accountant.canViewFinance, false);
    });

    test('engineer is the only mobile (non-admin-panel) role', () {
      expect(UserRole.engineer.usesAdminPanel, false);
      expect(UserRole.procurement.usesAdminPanel, true);
      expect(UserRole.admin.usesAdminPanel, true);
      expect(UserRole.accountant.usesAdminPanel, true);
    });

    test('Accountant inherits no retained technical module access', () {
      expect(UserRole.accountant.canAccessMaterials, false);
      expect(UserRole.accountant.canAccessRentals, false);
      expect(UserRole.accountant.canAccessPeople, false);
      expect(UserRole.accountant.canReceiveGoods, false);
      expect(UserRole.accountant.canApproveLeave, false);
      expect(UserRole.accountant.canViewCommercials, false);
      expect(UserRole.accountant.canViewFinance, false);
    });

    test('fromName round-trips exact compatibility roles', () {
      for (final r in UserRole.values) {
        expect(UserRole.fromName(r.name), r);
      }
      expect(UserRole.fromName('accountant'), UserRole.accountant);
      expect(UserRole.fromName('nonsense'), UserRole.engineer);
    });
  });
}
