/// Crew Requests — the register, laid out like Company Material Requests:
/// title with refresh and new, search, view chips and one card per request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../application/attendance_providers.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart' show AS, attendanceLanguage;
import 'crew_request_common.dart';
import 'crew_request_kit.dart';

enum CrewRequestView { myWork, open, all, finished }

/// The requests a view shows, with the search applied.
List<CrewRequest> crewRequestsFor(
  CrewRequestRegister register,
  CrewRequestView view,
  String query,
  AppLanguage language,
) {
  final q = query.trim().toLowerCase();
  return [
    for (final request in register.requests)
      if (switch (view) {
            CrewRequestView.myWork => request.access.mine,
            CrewRequestView.open => request.state.isOpen,
            CrewRequestView.all => true,
            CrewRequestView.finished => !request.state.isOpen,
          } &&
          (q.isEmpty ||
              [
                request.number,
                crewRequestWhere(request, language),
                crewRequestPeople(request),
                request.workLabel ?? '',
                request.requestedBy.name,
              ].join(' ').toLowerCase().contains(q)))
        request,
  ];
}

class CrewRequestRegisterScreen extends ConsumerStatefulWidget {
  const CrewRequestRegisterScreen({super.key});

  @override
  ConsumerState<CrewRequestRegisterScreen> createState() =>
      _CrewRequestRegisterScreenState();
}

class _CrewRequestRegisterScreenState
    extends ConsumerState<CrewRequestRegisterScreen> {
  CrewRequestView? _view;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final language = attendanceLanguage(ref);
    final register = ref.watch(yorksCrewRequestsProvider);
    final data = register.valueOrNull;
    // Start on My work when something waits for this person, else Open.
    final view =
        _view ??
        ((data?.mine.isNotEmpty ?? false)
            ? CrewRequestView.myWork
            : CrewRequestView.open);
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    CRS.t(CRS.registerTitle, language),
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('crew-register-refresh'),
                  tooltip: AS.t(AS.retry, language),
                  onPressed: () => ref.invalidate(yorksCrewRequestsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (data?.canRequest ?? false)
                  phone
                      ? IconButton.filled(
                          key: const ValueKey('crew-register-new'),
                          tooltip: CRS.t(CRS.requestCrew, language),
                          onPressed: () => context.go(crewRequestNewPath),
                          icon: const Icon(Icons.add_rounded),
                        )
                      : FilledButton.icon(
                          key: const ValueKey('crew-register-new'),
                          onPressed: () => context.go(crewRequestNewPath),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(CRS.t(CRS.requestCrew, language)),
                        ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('crew-register-search'),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: CRS.t(CRS.searchHint, language),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                for (final (option, label) in [
                  (CrewRequestView.myWork, CRS.filterMyWork),
                  (CrewRequestView.open, CRS.filterOpen),
                  (CrewRequestView.all, CRS.filterAll),
                  (CrewRequestView.finished, CRS.filterFinished),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      key: ValueKey('crew-register-${option.name}'),
                      selected: view == option,
                      onSelected: (_) => setState(() => _view = option),
                      label: Text(
                        option == CrewRequestView.myWork &&
                                (data?.mine.isNotEmpty ?? false)
                            ? '${CRS.t(label, language)} · ${data!.mine.length}'
                            : CRS.t(label, language),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: register.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => CrMessage(
                icon: Icons.cloud_off_outlined,
                message: crewRequestErrorText(error, language),
                action: AS.t(AS.retry, language),
                onPressed: () => ref.invalidate(yorksCrewRequestsProvider),
              ),
              data: (data) {
                final items = crewRequestsFor(data, view, _query, language);
                if (items.isEmpty) {
                  return CrMessage(
                    icon: Icons.task_alt_rounded,
                    message: data.requests.isEmpty
                        ? CRS.t(CRS.requestsEmptyBody, language)
                        : CRS.t(CRS.noMatches, language),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(yorksCrewRequestsProvider),
                  child: ListView.separated(
                    key: const ValueKey('crew-register-list'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: CrewRequestCard(
                          request: items[index],
                          language: language,
                          onOpen: () =>
                              context.go(crewRequestPath(items[index].id)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
