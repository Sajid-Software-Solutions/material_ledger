import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../app/yorks_navigation_history.dart';
import '../../../../app/yorks_v1_workspace_status_label.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_my_profile.dart';
import '../../../../shared/models/yorks_v1_my_profile_workspace.dart';
import '../../../../shared/models/yorks_v1_my_record_strings.dart';
import '../../../../shared/models/yorks_v1_profile_strings.dart';
import '../../../../shared/models/yorks_v1_workspace_status.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_my_profile_provider.dart';
import '../../../../shared/providers/yorks_v1_my_profile_workspace_provider.dart';
import '../../../../shared/providers/yorks_v1_people_provider.dart';
import '../../../../shared/providers/yorks_v1_workspace_status_provider.dart';
import '../../../../shared/services/app_config_service.dart';
import '../../../../shared/sync/connectivity_service.dart';
import '../../../../shared/sync/sync_engine.dart';
import '../../../../shared/widgets/yorks_sign_out_action.dart';
import '../../../people_records/presentation/people_kit.dart'
    show peopleErrorText;
import '../../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import '../widgets/yorks_my_profile_components.dart';
import '../widgets/yorks_my_record_cards.dart';

/// Canonical My Yorks destination.
///
/// P03 deliberately consumes only the protected P01 account projection. It
/// does not infer identity from the legacy employee cache or infer actions from
/// a client role. P04 adds protected summaries, scopes and actions; P05 adds
/// linked work identity and richer preference/session facts.
class EngineerProfileScreen extends ConsumerStatefulWidget {
  const EngineerProfileScreen({super.key});

  @override
  ConsumerState<EngineerProfileScreen> createState() =>
      _EngineerProfileScreenState();
}

class _EngineerProfileScreenState extends ConsumerState<EngineerProfileScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final profileState = ref.watch(yorksV1MyProfileProvider);
    final profileWorkspaceState = ref.watch(yorksV1MyProfileWorkspaceProvider);
    final featureFlags = ref.watch(yorksV1FeatureFlagsProvider);
    final workspaceStatus = ref.watch(yorksV1WorkspaceStatusProvider);
    final runtimeConfiguration = ref.watch(yorksV1RuntimeConfigurationProvider);
    final version = ref.watch(appVersionProvider).label;
    final direction = language.isRtl ? TextDirection.rtl : TextDirection.ltr;
    // The person's own People record (PRODUCT_DECISIONS section 54).
    final peopleOn = featureFlags.peopleRecords;
    final mineState = peopleOn ? ref.watch(yorksV1PeopleMineProvider) : null;
    final mine = mineState?.valueOrNull;
    final person = mine?.person;
    final profile = profileState.valueOrNull;

    return Directionality(
      textDirection: direction,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final layout = yorksMyProfileLayoutFor(constraints.maxWidth);
          final compact = layout == YorksMyProfileLayout.compact;
          final expanded = layout == YorksMyProfileLayout.expanded;
          final horizontalPadding = switch (layout) {
            YorksMyProfileLayout.compact => AppSpacing.mobileScreenHorizontal,
            YorksMyProfileLayout.medium => AppSpacing.xxl,
            YorksMyProfileLayout.expanded => AppSpacing.screenHorizontal,
          };
          final gap = compact ? AppSpacing.lg : AppSpacing.xl;
          final documents = person == null
              ? null
              : yorksMyDocumentsSummary(person, language);
          final accountSection = _AccountSection(
            language: language,
            profileState: profileState,
            compact:
                compact ||
                (layout == YorksMyProfileLayout.medium && size.height <= 500),
            onRetry: () => unawaited(_refreshProfile()),
            secondaryName: person?.arabicName,
            subtitle: person == null
                ? null
                : yorksMyPositionLine(person, language),
            detailLine: person == null ? null : yorksMyRecordLine(person),
            documentsLabel: documents?.label,
            documentsColor: documents?.color,
            // Once linked, the email moves to Settings > Your account.
            showEmail: person == null,
          );
          final accessSection = _AccessSection(
            language: language,
            profileState: profileState,
            workspaceState: profileWorkspaceState,
            onRetry: () => unawaited(_refreshProfile()),
          );
          final workIdentitySection = _WorkIdentitySection(
            language: language,
            profileState: profileState,
            workspaceState: profileWorkspaceState,
            onRetry: () => unawaited(_refreshProfile()),
          );
          final preferencesSection = _PreferencesSection(
            language: language,
            currencyLabel: '🇦🇪 AED',
            languageLabel: language.nativeName,
            onNotifications: () =>
                context.push(RoutePaths.notificationPreferences),
            onLanguage: () => _showLanguagePicker(language),
          );
          final helpAndSecuritySection = _HelpAndSecuritySection(
            language: language,
            workspaceStatus: workspaceStatus,
            version: version,
            onWorkspaceSync: () => _showSyncSheet(language),
            onRefreshAccess: () => unawaited(_refreshProfile()),
            onAbout: () => context.push(RoutePaths.about),
            supportNumber:
                runtimeConfiguration.valueOrNull?.supportWhatsApp ??
                '+923159353145',
            onSupport: (number) => unawaited(
              _contactSupport(language: language, supportNumber: number),
            ),
            onSignOut: () => showYorksSignOut(context, ref),
          );

          // One card: who the person is, then their own record from People.
          final profileCard = YorksMyProfileCard(
            header: accountSection,
            // With People records off, the card is the account alone.
            children: [
              if (mineState == null)
                ...const <Widget>[]
              else if (mineState.hasError && !mineState.isLoading)
                YorksMyRecordNotice.failed(
                  language: language,
                  onRetry: () => ref.invalidate(yorksV1PeopleMineProvider),
                )
              else if (mine == null)
                YorksMyRecordNotice.loading(language: language)
              else if (person == null)
                YorksMyRecordNotice.unlinked(language: language)
              else ...[
                YorksMyDocumentsSection(language: language, person: person),
                YorksMyFactsSection(language: language, person: person),
                YorksMyNotesSection(
                  language: language,
                  person: person,
                  onTell: () => unawaited(_tellHr(language)),
                ),
              ],
            ],
          );

          // Settings: the account, access, preferences, help and security.
          final email = profile?.email?.trim() ?? '';
          final accountCard = person != null && email.isNotEmpty
              ? YorksMyAccountCard(
                  language: language,
                  email: email,
                  role: profile!.exactRole,
                )
              : null;

          List<Widget> spaced(List<Widget> children) => [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(height: gap),
              children[index],
            ],
          ];

          final Widget body;
          if (expanded) {
            body = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 400, child: profileCard),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: spaced([
                      _PageHeading(language: language),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: preferencesSection),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(child: helpAndSecuritySection),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: accessSection),
                          if (accountCard != null) ...[
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(child: accountCard),
                          ],
                        ],
                      ),
                      if (mineState == null) workIdentitySection,
                    ]),
                  ),
                ),
              ],
            );
          } else {
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spaced([
                if (!compact) _PageHeading(language: language),
                profileCard,
                _SettingsHeading(language: language),
                ?accountCard,
                accessSection,
                if (mineState == null) workIdentitySection,
                preferencesSection,
                helpAndSecuritySection,
              ]),
            );
          }

          final content = FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: RefreshIndicator(
              onRefresh: () async {
                if (peopleOn) ref.invalidate(yorksV1PeopleMineProvider);
                await _refreshProfile();
              },
              child: CustomScrollView(
                key: const ValueKey('canonical-my-yorks-page'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      compact ? AppSpacing.lg : AppSpacing.screenVertical,
                      horizontalPadding,
                      compact ? 96 : AppSpacing.xxxl,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.pageMaxWidth,
                          ),
                          child: body,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: compact
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(
                      YorksMobileUi.appBarHeight,
                    ),
                    child: YorksMobileAppBar(
                      title: AppStrings.profile.active(language),
                      brand: !yorksCanNavigateBack(
                        context,
                        ref,
                        RoutePaths.engineerProfile,
                      ),
                      leading:
                          yorksCanNavigateBack(
                            context,
                            ref,
                            RoutePaths.engineerProfile,
                          )
                          ? YorksMobileIconButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).backButtonTooltip,
                              onPressed: () => yorksNavigateBack(
                                context,
                                ref,
                                RoutePaths.engineerProfile,
                                fallback: RoutePaths.engineerHome,
                              ),
                            )
                          : null,
                    ),
                  )
                : null,
            body: SafeArea(top: !compact, child: content),
          );
        },
      ),
    );
  }

  Future<void> _refreshProfile() async {
    await ref.read(yorksV1MyProfileProvider.notifier).refresh();
    if (!mounted || !ref.read(yorksV1MyProfileProvider).hasValue) return;
    await ref.read(yorksV1MyProfileWorkspaceProvider.notifier).refresh();
  }

  /// A note to HR/PRO about the person's own record. Nothing shows as sent
  /// until the server confirms it.
  Future<void> _tellHr(AppLanguage language) async {
    final repository = ref.read(yorksV1PeopleRepositoryProvider);
    final idempotencyKey = const Uuid().v4();
    final sent = await showAttendanceCommandDialog(
      context,
      language: language,
      title: MyRecordStrings.t(MyRecordStrings.tellHrTitle, language),
      body: MyRecordStrings.t(MyRecordStrings.tellHrBody, language),
      fieldLabel: MyRecordStrings.t(MyRecordStrings.tellHrTitle, language),
      confirmLabel: MyRecordStrings.t(MyRecordStrings.send, language),
      command: (text) async {
        try {
          await repository.sendNote(
            message: text,
            idempotencyKey: idempotencyKey,
          );
          return null;
        } on YorksV1DomainException catch (error) {
          if ((error.serverMessage ?? '').contains('V1_PEOPLE_NOTE_LIMIT')) {
            return MyRecordStrings.t(MyRecordStrings.noteLimit, language);
          }
          return peopleErrorText(error, language);
        } catch (error) {
          return peopleErrorText(error, language);
        }
      },
    );
    if (sent == null || !mounted) return;
    ref.invalidate(yorksV1PeopleMineProvider);
    YorksAppToast.show(
      context,
      title: MyRecordStrings.t(MyRecordStrings.sentToast, language),
      message: sent,
      icon: Icons.mark_email_read_outlined,
    );
  }

  void _showLanguagePicker(AppLanguage language) {
    LanguagePickerSheet.show(
      context,
      current: language,
      title: AppStrings.secondaryLanguage.active(language),
      description: YorksV1ProfileStrings.chooseLanguage.active(language),
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      onSelected: (next) =>
          ref.read(languageProvider.notifier).setLanguage(next),
    );
  }

  void _showSyncSheet(AppLanguage language) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 680),
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => Directionality(
        textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: _WorkspaceSyncSheet(language: language),
      ),
    );
  }

  Future<void> _contactSupport({
    required AppLanguage language,
    required String supportNumber,
  }) async {
    final digits = supportNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.https('wa.me', '/$digits', {
      'text': YorksV1ProfileStrings.supportMessage.active(language),
    });
    try {
      if (digits.isNotEmpty &&
          await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // The copy fallback below keeps the support route usable when a device
      // has no WhatsApp handler or blocks external navigation.
    }
    await Clipboard.setData(ClipboardData(text: supportNumber));
    if (!mounted) return;
    YorksAppToast.show(
      context,
      title: YorksV1ProfileStrings.supportCopied.active(language),
      message: supportNumber,
      icon: Icons.content_copy_rounded,
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1ProfileStrings.account.active(language).toUpperCase(),
          style: AppTypography.eyebrow,
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          header: true,
          child: Text(
            AppStrings.profile.active(language),
            style: AppTypography.headlineLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          YorksV1ProfileStrings.introduction.active(language),
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

/// Separates the settings from the profile card on phones and tablets.
class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(
        MyRecordStrings.t(MyRecordStrings.tabSettings, language),
        key: const ValueKey('my-yorks-settings-heading'),
        style: AppTypography.titleLarge,
      ),
    ),
  );
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.language,
    required this.profileState,
    required this.compact,
    required this.onRetry,
    this.secondaryName,
    this.subtitle,
    this.detailLine,
    this.documentsLabel,
    this.documentsColor,
    this.showEmail = true,
  });

  final AppLanguage language;
  final AsyncValue<YorksV1MyProfile> profileState;
  final bool compact;
  final VoidCallback onRetry;
  final String? secondaryName;
  final String? subtitle;
  final String? detailLine;
  final String? documentsLabel;
  final Color? documentsColor;
  final bool showEmail;

  @override
  Widget build(BuildContext context) {
    return switch (profileState) {
      AsyncData(:final value) => YorksIdentityHero(
        language: language,
        state: YorksAccountEvidenceState.verified,
        displayName: value.displayName,
        email: showEmail ? value.email : null,
        role: value.exactRole,
        compact: compact,
        attached: true,
        secondaryName: secondaryName,
        subtitle: subtitle,
        detailLine: detailLine,
        documentsLabel: documentsLabel,
        documentsColor: documentsColor,
      ),
      AsyncError() => YorksIdentityHero(
        language: language,
        state: YorksAccountEvidenceState.unavailable,
        compact: compact,
        attached: true,
        onRetry: onRetry,
      ),
      _ => YorksIdentityHero(
        language: language,
        state: YorksAccountEvidenceState.loading,
        compact: compact,
        attached: true,
      ),
    };
  }
}

class _AccessSection extends StatelessWidget {
  const _AccessSection({
    required this.language,
    required this.profileState,
    required this.workspaceState,
    required this.onRetry,
  });

  final AppLanguage language;
  final AsyncValue<YorksV1MyProfile> profileState;
  final AsyncValue<YorksV1MyProfileWorkspace> workspaceState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (profileState.hasError || workspaceState.hasError) {
      return _WorkspaceFactsStateCard(
        title: YorksV1ProfileStrings.accessAndScope.active(language),
        description: YorksV1ProfileStrings.accessAndScopeDescription.active(
          language,
        ),
        icon: Icons.shield_outlined,
        language: language,
        unavailable: true,
        onRetry: onRetry,
      );
    }
    final workspace = workspaceState.valueOrNull;
    if (profileState.valueOrNull == null || workspace == null) {
      return _WorkspaceFactsStateCard(
        title: YorksV1ProfileStrings.accessAndScope.active(language),
        description: YorksV1ProfileStrings.accessAndScopeDescription.active(
          language,
        ),
        icon: Icons.shield_outlined,
        language: language,
      );
    }
    return YorksAccessSummaryCard(
      key: const ValueKey('my-yorks-access-scope'),
      language: language,
      scope: workspace.accessScope,
      verifiedAt: workspace.generatedAt,
    );
  }
}

class _WorkIdentitySection extends StatelessWidget {
  const _WorkIdentitySection({
    required this.language,
    required this.profileState,
    required this.workspaceState,
    required this.onRetry,
  });

  final AppLanguage language;
  final AsyncValue<YorksV1MyProfile> profileState;
  final AsyncValue<YorksV1MyProfileWorkspace> workspaceState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (profileState.hasError || workspaceState.hasError) {
      return _WorkspaceFactsStateCard(
        title: YorksV1ProfileStrings.workIdentity.active(language),
        description: YorksV1ProfileStrings.workIdentityDescription.active(
          language,
        ),
        icon: Icons.badge_outlined,
        language: language,
        unavailable: true,
        onRetry: onRetry,
      );
    }
    final workspace = workspaceState.valueOrNull;
    if (profileState.valueOrNull == null || workspace == null) {
      return _WorkspaceFactsStateCard(
        title: YorksV1ProfileStrings.workIdentity.active(language),
        description: YorksV1ProfileStrings.workIdentityDescription.active(
          language,
        ),
        icon: Icons.badge_outlined,
        language: language,
      );
    }
    return YorksWorkIdentityCard(
      key: const ValueKey('my-yorks-work-identity'),
      language: language,
      worker: workspace.workIdentity.worker,
    );
  }
}

class _WorkspaceFactsStateCard extends StatelessWidget {
  const _WorkspaceFactsStateCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.language,
    this.unavailable = false,
    this.onRetry,
  });

  final String title;
  final String description;
  final IconData icon;
  final AppLanguage language;
  final bool unavailable;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return YorksProfileSectionCard(
      title: title,
      description: description,
      icon: icon,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceInlineNotice(
                icon: unavailable
                    ? Icons.error_outline_rounded
                    : Icons.sync_rounded,
                title: unavailable
                    ? YorksV1ProfileStrings.workspaceFactsUnavailable.active(
                        language,
                      )
                    : YorksV1ProfileStrings.workspaceFactsLoading.active(
                        language,
                      ),
                description: unavailable
                    ? YorksV1ProfileStrings.workspaceFactsUnavailableDescription
                          .active(language)
                    : YorksV1ProfileStrings.workspaceFactsLoadingDescription
                          .active(language),
              ),
              if (!unavailable) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (unavailable && onRetry != null) ...[
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      YorksV1ProfileStrings.tryAgain.active(language),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkspaceInlineNotice extends StatelessWidget {
  const _WorkspaceInlineNotice({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.inkSecondary, size: 21),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.language,
    required this.currencyLabel,
    required this.languageLabel,
    required this.onNotifications,
    required this.onLanguage,
  });

  final AppLanguage language;
  final String currencyLabel;
  final String languageLabel;
  final VoidCallback onNotifications;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    return YorksProfileSectionCard(
      title: YorksV1ProfileStrings.preferences.active(language),
      description: YorksV1ProfileStrings.preferencesDescription.active(
        language,
      ),
      icon: Icons.tune_rounded,
      children: [
        YorksPreferenceRow(
          icon: Icons.notifications_outlined,
          title: AppStrings.notifications.active(language),
          description: YorksV1ProfileStrings.notificationsDescription.active(
            language,
          ),
          onPressed: onNotifications,
        ),
        YorksPreferenceRow(
          icon: Icons.translate_rounded,
          title: AppStrings.secondaryLanguage.active(language),
          description: YorksV1ProfileStrings.chooseLanguage.active(language),
          value: languageLabel,
          onPressed: onLanguage,
        ),
        YorksPreferenceRow(
          icon: Icons.currency_exchange_rounded,
          title: AppStrings.currency.active(language),
          description: YorksV1ProfileStrings.chooseCurrency.active(language),
          value: currencyLabel,
        ),
      ],
    );
  }
}

class _HelpAndSecuritySection extends StatelessWidget {
  const _HelpAndSecuritySection({
    required this.language,
    required this.workspaceStatus,
    required this.version,
    required this.onWorkspaceSync,
    required this.onRefreshAccess,
    required this.onAbout,
    required this.supportNumber,
    required this.onSupport,
    required this.onSignOut,
  });

  final AppLanguage language;
  final YorksV1WorkspaceStatus workspaceStatus;
  final String version;
  final VoidCallback onWorkspaceSync;
  final VoidCallback onRefreshAccess;
  final VoidCallback onAbout;
  final String supportNumber;
  final ValueChanged<String> onSupport;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YorksProfileSectionCard(
          title: YorksV1ProfileStrings.helpAndSecurity.active(language),
          description: YorksV1ProfileStrings.helpAndSecurityDescription.active(
            language,
          ),
          icon: Icons.shield_outlined,
          children: [
            YorksPreferenceRow(
              icon: Icons.cloud_done_outlined,
              title: AppStrings.workspaceSync.active(language),
              description: YorksV1ProfileStrings.workspaceSyncDescription
                  .active(language),
              trailing: YorksV1WorkspaceStatusLabel(
                status: workspaceStatus,
                compact: true,
                language: language,
              ),
              onPressed: onWorkspaceSync,
            ),
            YorksPreferenceRow(
              icon: Icons.admin_panel_settings_outlined,
              title: YorksV1ProfileStrings.accountScopeRefresh.active(language),
              description: YorksV1ProfileStrings.accountScopeRefreshDescription
                  .active(language),
              onPressed: onRefreshAccess,
            ),
            YorksPreferenceRow(
              icon: Icons.info_outline_rounded,
              title: AppStrings.about.active(language),
              description: YorksV1ProfileStrings.aboutDescription.active(
                language,
              ),
              onPressed: onAbout,
            ),
            YorksPreferenceRow(
              key: const ValueKey('my-yorks-contact-support'),
              icon: Icons.support_agent_rounded,
              title: YorksV1ProfileStrings.contactSupport.active(language),
              description: YorksV1ProfileStrings.contactSupportDescription
                  .active(language),
              value: supportNumber,
              valueTextDirection: TextDirection.ltr,
              onPressed: () => onSupport(supportNumber),
            ),
            YorksPreferenceRow(
              icon: Icons.logout_rounded,
              title: AppStrings.signOut.active(language),
              description: YorksV1ProfileStrings.signOutDescription.active(
                language,
              ),
              destructive: true,
              onPressed: onSignOut,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${YorksV1ProfileStrings.organizationName.active(language)} '
              '$version',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Global sync intentionally states only what connectivity and the durable
/// outbox prove. Record-level competing-writer conflicts remain on the record,
/// where both authoritative and local values are available for review.
class _WorkspaceSyncSheet extends ConsumerWidget {
  const _WorkspaceSyncSheet({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(yorksV1WorkspaceStatusProvider);
    final failed = ref.watch(failedSyncProvider);
    final pending = ref.watch(pendingSyncCountProvider);
    final online = ref.watch(isOnlineProvider);
    final hasFailure = failed.isNotEmpty;
    final callout = switch (status.state) {
      YorksV1WorkspaceConnectionState.offline => YorksMobileCallout(
        icon: Icons.cloud_off_outlined,
        title: YorksV1ProfileStrings.offlineWorkspace.active(language),
        message: pending == 0
            ? YorksV1ProfileStrings.localDraftsOffline.active(language)
            : YorksV1ProfileStrings.queuedChanges(language, pending),
        warning: true,
      ),
      YorksV1WorkspaceConnectionState.syncing => YorksMobileCallout(
        icon: Icons.sync_rounded,
        title: YorksV1ProfileStrings.syncingChanges.active(language),
        message: YorksV1ProfileStrings.syncingCount(language, pending),
      ),
      YorksV1WorkspaceConnectionState.failed => YorksMobileCallout(
        icon: Icons.error_outline_rounded,
        title: YorksV1ProfileStrings.changesNeedAttention.active(language),
        message: YorksV1ProfileStrings.failedCount(language, failed.length),
        warning: true,
      ),
      _ => YorksMobileCallout(
        icon: Icons.cloud_done_outlined,
        title: online
            ? YorksV1ProfileStrings.workspaceConnected.active(language)
            : YorksV1ProfileStrings.workspaceStatusUnavailable.active(language),
        message: online
            ? YorksV1ProfileStrings.noQueuedChanges.active(language)
            : YorksV1ProfileStrings.connectionWillUpdate.active(language),
      ),
    };
    final maxHeight = MediaQuery.sizeOf(context).height * .92;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          YorksV1ProfileStrings.syncStatus.active(language),
                          style: AppTypography.titleLarge,
                        ),
                      ),
                    ),
                    YorksV1WorkspaceStatusLabel(
                      status: status,
                      compact: true,
                      language: language,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                callout,
                const SizedBox(height: 14),
                YorksMobileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          YorksV1ProfileStrings.conflictHandling.active(
                            language,
                          ),
                          style: AppTypography.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        YorksV1ProfileStrings.conflictHandlingDescription
                            .active(language),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasFailure) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: AppSpacing.minTapTarget,
                    child: FilledButton.icon(
                      onPressed: () => ref.read(syncEngineProvider).retryAll(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        YorksV1ProfileStrings.retrySync.active(language),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
