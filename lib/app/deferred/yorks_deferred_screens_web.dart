import 'package:flutter/widgets.dart';

import '../../core/widgets/yorks_deferred_screen.dart';
import '../../features/admin/presentation/screens/user_management_screen.dart'
    deferred as user_management;
import '../../features/configuration/presentation/configuration_screen.dart'
    deferred as configuration;
import '../../features/admin/presentation/screens/yorks_v1_user_access_screen.dart'
    deferred as user_access;
import '../../features/materials/presentation/screens/yorks_v1_inventory_import_screen.dart'
    deferred as inventory_import;
import '../../features/materials/presentation/screens/yorks_v1_inventory_screen.dart'
    deferred as inventory;
import '../../features/materials/presentation/screens/yorks_v1_inventory_supplier_screens.dart'
    deferred as suppliers;
import '../../features/workforce/presentation/screens/yorks_workforce_administration_screen.dart'
    deferred as workforce_administration;
import '../../features/workforce/presentation/screens/yorks_workforce_daily_attendance_screen.dart'
    deferred as workforce_attendance;
import '../../features/workforce/presentation/screens/yorks_workforce_timesheets_screen.dart'
    deferred as workforce_timesheets;

Widget yorksInventoryScreen({String? initialTab}) => YorksDeferredScreen(
  load: inventory.loadLibrary,
  builder: () => inventory.YorksV1InventoryScreen(initialTab: initialTab),
);

Widget yorksSupplierDirectoryScreen() => YorksDeferredScreen(
  load: suppliers.loadLibrary,
  builder: () => suppliers.YorksV1InventorySupplierDirectoryScreen(),
);

Widget yorksSupplierFolderScreen({required String supplierId}) =>
    YorksDeferredScreen(
      load: suppliers.loadLibrary,
      builder: () => suppliers.YorksV1InventorySupplierFolderScreen(
        supplierId: supplierId,
      ),
    );

Widget yorksInventoryImportScreen({
  String? preselectedSupplierId,
  VoidCallback? onCancel,
  VoidCallback? onReturnToSuppliers,
  ValueChanged<String>? onOpenSupplier,
}) => YorksDeferredScreen(
  load: inventory_import.loadLibrary,
  builder: () => inventory_import.YorksV1InventoryImportScreen(
    preselectedSupplierId: preselectedSupplierId,
    onCancel: onCancel,
    onReturnToSuppliers: onReturnToSuppliers,
    onOpenSupplier: onOpenSupplier,
  ),
);

Widget yorksConfigurationScreen({String? section}) => YorksDeferredScreen(
  load: configuration.loadLibrary,
  builder: () => configuration.ConfigurationScreen(initialSection: section),
);

Widget yorksWorkforceAdministrationScreen() => YorksDeferredScreen(
  load: workforce_administration.loadLibrary,
  builder: () => workforce_administration.YorksWorkforceAdministrationScreen(),
);

Widget yorksWorkforceAttendanceScreen({
  String? initialTeamId,
  String? initialWorkDate,
}) => YorksDeferredScreen(
  load: workforce_attendance.loadLibrary,
  builder: () => workforce_attendance.YorksWorkforceDailyAttendanceScreen(
    initialTeamId: initialTeamId,
    initialWorkDate: initialWorkDate,
  ),
);

Widget yorksWorkforceTimesheetsScreen({String? initialPeriodId}) =>
    YorksDeferredScreen(
      load: workforce_timesheets.loadLibrary,
      builder: () => workforce_timesheets.YorksWorkforceTimesheetsScreen(
        initialPeriodId: initialPeriodId,
      ),
    );

Widget yorksUserManagementScreen() => YorksDeferredScreen(
  load: user_management.loadLibrary,
  builder: () => user_management.UserManagementScreen(),
);

Widget yorksUserAccessScreen({required String targetAppUserId}) =>
    YorksDeferredScreen(
      load: user_access.loadLibrary,
      builder: () =>
          user_access.YorksV1UserAccessScreen(targetAppUserId: targetAppUserId),
    );
