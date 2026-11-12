import 'package:flutter/widgets.dart';

import '../../features/admin/presentation/screens/user_management_screen.dart';
import '../../features/configuration/presentation/configuration_screen.dart';
import '../../features/admin/presentation/screens/yorks_v1_user_access_screen.dart';
import '../../features/materials/presentation/screens/yorks_v1_inventory_import_screen.dart';
import '../../features/materials/presentation/screens/yorks_v1_inventory_screen.dart';
import '../../features/materials/presentation/screens/yorks_v1_inventory_supplier_screens.dart';
import '../../features/workforce/presentation/screens/yorks_workforce_administration_screen.dart';
import '../../features/workforce/presentation/screens/yorks_workforce_daily_attendance_screen.dart';
import '../../features/workforce/presentation/screens/yorks_workforce_timesheets_screen.dart';

Widget yorksInventoryScreen({String? initialTab}) =>
    YorksV1InventoryScreen(initialTab: initialTab);

Widget yorksSupplierDirectoryScreen() =>
    const YorksV1InventorySupplierDirectoryScreen();

Widget yorksSupplierFolderScreen({required String supplierId}) =>
    YorksV1InventorySupplierFolderScreen(supplierId: supplierId);

Widget yorksInventoryImportScreen({
  String? preselectedSupplierId,
  VoidCallback? onCancel,
  VoidCallback? onReturnToSuppliers,
  ValueChanged<String>? onOpenSupplier,
}) => YorksV1InventoryImportScreen(
  preselectedSupplierId: preselectedSupplierId,
  onCancel: onCancel,
  onReturnToSuppliers: onReturnToSuppliers,
  onOpenSupplier: onOpenSupplier,
);

Widget yorksConfigurationScreen({String? section}) =>
    ConfigurationScreen(initialSection: section);

Widget yorksWorkforceAdministrationScreen() =>
    const YorksWorkforceAdministrationScreen();

Widget yorksWorkforceAttendanceScreen({
  String? initialTeamId,
  String? initialWorkDate,
}) => YorksWorkforceDailyAttendanceScreen(
  initialTeamId: initialTeamId,
  initialWorkDate: initialWorkDate,
);

Widget yorksWorkforceTimesheetsScreen({String? initialPeriodId}) =>
    YorksWorkforceTimesheetsScreen(initialPeriodId: initialPeriodId);

Widget yorksUserManagementScreen() => const UserManagementScreen();

Widget yorksUserAccessScreen({required String targetAppUserId}) =>
    YorksV1UserAccessScreen(targetAppUserId: targetAppUserId);
