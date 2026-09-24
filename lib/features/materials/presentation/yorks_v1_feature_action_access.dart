import 'package:flutter/material.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_permission_management.dart';
import '../../../shared/models/yorks_v1_permission_strings.dart';
import '../../../shared/providers/yorks_v1_permission_provider.dart';

bool yorksV1CanReadProjectRecord(
  YorksV1CurrentPermissionSnapshotState state,
  String capabilityKey, {
  required bool legacyAllowed,
  required String projectId,
}) => state.hybridAllows(
  capabilityKey,
  legacyAllowed: legacyAllowed,
  projectId: projectId,
);

class YorksV1ProjectReadBoundary extends StatelessWidget {
  const YorksV1ProjectReadBoundary({
    super.key,
    required this.allowed,
    required this.language,
    required this.child,
  });

  final bool allowed;
  final AppLanguage language;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (allowed) return child;
    return Center(
      key: const Key('yorks-v1-project-read-denied'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 44,
                color: AppColors.muted,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                YorksV1PermissionStrings.text(language, 'forbidden_title'),
                textAlign: TextAlign.center,
                style: AppTypography.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                YorksV1PermissionStrings.text(language, 'forbidden_body'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Presentation decision for an already server-protected Yorks action.
///
/// This helper deliberately keeps the rollout hybrid. Shadow capabilities use
/// the exact-role/membership decision supplied by the existing feature. Once a
/// capability is enforced, only the current server-confirmed person-specific
/// decision for the concrete project is accepted. The server RPC/RLS remains
/// the final authority in both modes.
class YorksV1FeatureActionAccess {
  const YorksV1FeatureActionAccess({
    required this.isVisible,
    required this.canWrite,
    required this.authorizationMode,
    required this.availability,
  });

  const YorksV1FeatureActionAccess.denied()
    : isVisible = false,
      canWrite = false,
      authorizationMode = null,
      availability = YorksV1ActionAvailability.denied;

  final bool isVisible;
  final bool canWrite;
  final YorksV1PermissionCapabilityAuthorizationMode? authorizationMode;
  final YorksV1ActionAvailability availability;

  /// A confirmed allow remains usable during a routine background refresh.
  /// Writes pause when an actual authority change has made the retained
  /// snapshot stale. Realtime transport loss alone leaves server-checked
  /// commands available.
  bool get isWritePaused => isVisible && !canWrite;
}

/// Keeps the access check visible beside a disabled action, without implying
/// that a transport failure was an authoritative denial.
class YorksV1ActionAvailabilityNotice extends StatelessWidget {
  const YorksV1ActionAvailabilityNotice({
    super.key,
    required this.access,
    required this.language,
    required this.onRetry,
  });

  final YorksV1FeatureActionAccess access;
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!access.isWritePaused) return const SizedBox.shrink();
    final checking = access.availability == YorksV1ActionAvailability.checking;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            checking ? Icons.hourglass_top_rounded : Icons.cloud_off_outlined,
            color: AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              YorksV1PermissionStrings.text(
                language,
                checking ? 'action_checking' : 'action_unavailable',
              ),
              style: AppTypography.bodySmall,
            ),
          ),
          if (!checking)
            TextButton(
              onPressed: onRetry,
              child: Text(
                YorksV1PermissionStrings.text(language, 'action_retry'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Presentation state only. A command still rechecks authority on the server.
enum YorksV1ActionAvailability {
  checking,
  allowed,
  denied,
  temporarilyUnavailable,
}

YorksV1FeatureActionAccess yorksV1FeatureActionAccess(
  YorksV1CurrentPermissionSnapshotState state,
  String capabilityKey, {
  required bool legacyAllowed,
  String? projectId,
  bool anyProject = false,
}) {
  final snapshot = state.snapshot;
  final access = snapshot?.capability(capabilityKey);
  if (snapshot == null) {
    final explicitDenial =
        state.domainErrorCode == YorksV1DomainErrorCode.unauthorized ||
        state.domainErrorCode == YorksV1DomainErrorCode.unauthenticated ||
        state.domainErrorCode == YorksV1DomainErrorCode.featureDisabled;
    if (explicitDenial || !legacyAllowed) {
      return const YorksV1FeatureActionAccess.denied();
    }
    return YorksV1FeatureActionAccess(
      isVisible: true,
      canWrite: false,
      authorizationMode: null,
      availability: state.error == null
          ? YorksV1ActionAvailability.checking
          : YorksV1ActionAvailability.temporarilyUnavailable,
    );
  }
  if (!snapshot.user.isActive ||
      access == null ||
      !access.catalog.isOperational) {
    return const YorksV1FeatureActionAccess.denied();
  }

  // Person-specific grants refine the feature's existing structural, state,
  // ownership and separation-of-duty eligibility; they never manufacture an
  // action that the protected workflow projection says is ineligible.
  final allowed = switch (access.authorizationMode) {
    // Candidate permission values are parity evidence only while shadowed.
    YorksV1PermissionCapabilityAuthorizationMode.shadow => legacyAllowed,
    YorksV1PermissionCapabilityAuthorizationMode.enforced =>
      legacyAllowed &&
          _enforcedAllow(
            snapshot,
            access,
            capabilityKey,
            projectId: projectId,
            anyProject: anyProject,
          ),
  };
  return YorksV1FeatureActionAccess(
    isVisible: allowed,
    // Shadow preserves the legacy structural decision. AP-16 keeps a trusted
    // decision usable during routine polling or a dropped invalidation
    // channel. An actual revision event pauses mutation until it is resolved.
    canWrite: allowed && state.isTrustedForWrites,
    authorizationMode: access.authorizationMode,
    availability: !allowed
        ? YorksV1ActionAvailability.denied
        : state.isTrustedForWrites
        ? YorksV1ActionAvailability.allowed
        : state.error == null && state.isRefreshing
        ? YorksV1ActionAvailability.checking
        : YorksV1ActionAvailability.temporarilyUnavailable,
  );
}

bool _enforcedAllow(
  YorksV1CurrentPermissionSnapshot snapshot,
  YorksV1PermissionCapabilityAccess access,
  String capabilityKey, {
  String? projectId,
  required bool anyProject,
}) {
  final normalizedProjectId = projectId?.trim();
  if (normalizedProjectId != null && normalizedProjectId.isNotEmpty) {
    return snapshot.allows(capabilityKey, projectId: normalizedProjectId);
  }
  if (access.catalog.requiresProjectAccess) {
    if (!anyProject) return false;
    return snapshot.projectAccess.any(
      (project) =>
          project.hasAccess &&
          snapshot.allows(capabilityKey, projectId: project.projectId),
    );
  }
  return access.authoritativeEffective == true;
}
