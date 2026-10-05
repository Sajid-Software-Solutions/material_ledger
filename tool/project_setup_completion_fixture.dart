/// Synthetic, offline-only presentation data. Nothing in this file sends a
/// command, accesses a backend, or represents an existing customer project.
library;

import 'package:flutter/material.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_completion.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';

const projectSetupCompletionFixtureBuildingCodes = [
  'DF3W',
  'DF4W',
  'DF6W',
  'DF7W',
];

YorksV1ProjectSetupOperation projectSetupCompletionFixtureOperation({
  bool activationPending = false,
  bool filesPending = false,
  bool emptyFiles = false,
}) {
  const projectId = 'visual-fixture-project';
  const createdAt = '2026-10-04T09:00:00Z';
  Map<String, dynamic> project(String state, int version) => {
    'id': projectId,
    'project_ref': 'YRA-322',
    'name': 'NEXUS — Four substations',
    'project_site': 'Al Dhafra, Abu Dhabi',
    'state': state,
    'record_version': version,
    'created_at': createdAt,
    'updated_at': createdAt,
  };
  final scopeRows = <Map<String, dynamic>>[
    {
      'id': 'visual-fixture-common',
      'project_id': projectId,
      'scope_kind': 'common',
      'code': 'COMMON',
      'name': 'Common / All Buildings',
      'is_active': true,
    },
    for (final code in projectSetupCompletionFixtureBuildingCodes)
      {
        'id': 'visual-fixture-$code',
        'project_id': projectId,
        'scope_kind': 'building',
        'code': code,
        'name': '132/33kV BUILDING',
        'is_active': true,
        'floors_levels': ['1', '2'],
        'flags': {'has_frp_room': true},
        'delivery_address': 'Al Dhafra, Abu Dhabi',
      },
  ];
  final members = <Map<String, dynamic>>[
    for (var index = 1; index <= 2; index++)
      {
        'id': 'visual-fixture-member-$index',
        'project_id': projectId,
        'member_auth_user_id': 'visual-fixture-user-$index',
        'project_role': 'project_engineer',
        'effective_from': createdAt,
        'created_at': createdAt,
      },
  ];
  return YorksV1ProjectSetupOperation(
    backendIdentity: 'offline-visual-fixture',
    ownerAuthUserId: 'visual-fixture-owner',
    draftId: 'visual-fixture-draft',
    mode: YorksV1ProjectSetupMode.create,
    core: YorksV1ProjectSetupCommand(
      kind: YorksV1ProjectSetupCommandKind.create,
      idempotencyKey: 'visual-fixture-create',
      payload: {
        'project_ref': 'YRA-322',
        'name': 'NEXUS — Four substations',
        'project_site': 'Al Dhafra, Abu Dhabi',
        'attachments': <Object?>[],
        'buildings': [
          for (final row in scopeRows.where(
            (row) => row['scope_kind'] == 'building',
          ))
            {
              'code': row['code'],
              'name': row['name'],
              'floors_levels': row['floors_levels'],
              'delivery_address': row['delivery_address'],
              'flags': row['flags'],
            },
        ],
      },
      status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
      attempts: 1,
      result: {
        'project': project('draft', 1),
        'scopes': scopeRows,
        'members': members,
        'parties': <Object?>[],
        'attachments': <Object?>[],
        'common_scope_id': 'visual-fixture-common',
      },
    ),
    activation: YorksV1ProjectSetupCommand(
      kind: YorksV1ProjectSetupCommandKind.activate,
      idempotencyKey: 'visual-fixture-activation',
      payload: {
        'project_id': projectId,
        'state': 'active',
        'expected_version': 1,
        'reason': null,
      },
      status: activationPending
          ? YorksV1ProjectSetupCommandStatus.outcomeUncertain
          : YorksV1ProjectSetupCommandStatus.confirmedSuccess,
      attempts: 1,
      result: activationPending ? null : {'project': project('active', 2)},
    ),
    files: emptyFiles
        ? const []
        : [
            for (var index = 1; index <= 3; index++)
              YorksV1ProjectSetupFile(
                localId: 'visual-fixture-file-$index',
                idempotencyKey: 'visual-fixture-upload-$index',
                fileName: 'Project document $index.pdf',
                mimeType: 'application/pdf',
                sizeBytes: 3,
                classification: YorksV1DocumentClassification.operational,
                contentHash:
                    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
                status: filesPending && index == 1
                    ? YorksV1ProjectSetupFileStatus.needsReselect
                    : YorksV1ProjectSetupFileStatus.ready,
              ),
          ],
  );
}

/// Place this body in YorksV1ProjectSetupDesktopShell(completed: true).
Widget buildProjectSetupCompletionFixture({
  AppLanguage language = AppLanguage.english,
  bool compact = false,
  bool activationPending = false,
  bool filesPending = false,
  bool emptyFiles = false,
  Widget? recoveryPanel,
  VoidCallback? onDismissBanner,
}) {
  void noOp() {}
  final operation = projectSetupCompletionFixtureOperation(
    activationPending: activationPending,
    filesPending: filesPending,
    emptyFiles: emptyFiles,
  );
  return YorksV1ProjectSetupCompletion(
    compact: compact,
    operation: operation,
    copy: YorksV1ProjectSetupCompletionCopy.localized(language),
    permissions: const YorksV1ProjectSetupCompletionPermissions(
      canOpenProject: true,
      canEditProject: true,
      canAddBoq: true,
      canInviteTeam: true,
      canUploadDocuments: true,
      canCreateMaterialRequests: true,
      canReturnToProjects: true,
    ),
    summaryRows: [
      YorksV1ProjectSetupSummaryRow(
        label: YorksV1ProjectStrings.siteLocation.active(language),
        value: operation.project!.siteLocation!,
      ),
      YorksV1ProjectSetupSummaryRow(
        label: YorksV1ProjectStrings.projectEngineers.active(language),
        value: '2',
      ),
      YorksV1ProjectSetupSummaryRow(
        label: YorksV1ProjectStrings.siteEngineers.active(language),
        value: '0',
      ),
      YorksV1ProjectSetupSummaryRow(
        label: YorksV1ProjectStrings.buildings.active(language),
        value: '4 (${projectSetupCompletionFixtureBuildingCodes.join(', ')})',
      ),
      YorksV1ProjectSetupSummaryRow(
        label: YorksV1ProjectStrings.attachments.active(language),
        value: '${operation.files.length}',
      ),
    ],
    recoveryPanel: recoveryPanel,
    onDismissBanner: onDismissBanner,
    onOpenProject: noOp,
    onEditProject: noOp,
    onAddBoq: noOp,
    onInviteTeam: noOp,
    onUploadDocuments: noOp,
    onReturnToProjects: noOp,
  );
}
