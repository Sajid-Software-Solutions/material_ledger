part of 'yorks_v1_project_create_flow_screen.dart';

class _DesktopStageHeading extends StatelessWidget {
  const _DesktopStageHeading({
    required this.stage,
    required this.language,
    required this.description,
  });
  final YorksV1ProjectCreationStage stage;
  final AppLanguage language;
  final TranslatableString description;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _stageCopy(stage).active(language),
            style: YorksProjectSetupDesktopTheme.title,
          ),
          const SizedBox(width: 20),
          Text(
            YorksV1ProjectStrings.stepOf
                .active(language)
                .replaceFirst('{current}', '${stage.index + 1}')
                .replaceFirst('{total}', '5'),
            style: YorksProjectSetupDesktopTheme.body.copyWith(
              fontSize: 15,
              color: YorksProjectSetupDesktopTheme.muted,
            ),
          ),
        ],
      ),
      SizedBox(
        height: stage == YorksV1ProjectCreationStage.projectDetails ? 5 : 2,
      ),
      Text(
        description.active(language),
        style: YorksProjectSetupDesktopTheme.body.copyWith(
          color: YorksProjectSetupDesktopTheme.muted,
        ),
      ),
    ],
  );
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.minHeight = 0,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: minHeight),
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: YorksProjectSetupDesktopTheme.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}

class _DesktopField extends StatelessWidget {
  const _DesktopField({
    super.key,
    required this.label,
    required this.language,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.required = false,
    this.optional = false,
    this.hint,
    this.helper,
    this.validator,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.dense = false,
  });
  final TranslatableString label;
  final AppLanguage language;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool required;
  final bool optional;
  final TranslatableString? hint;
  final TranslatableString? helper;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final input = Semantics(
      label: label.active(language),
      child: TextFormField(
        readOnly: _ProjectSetupReadOnlyScope.of(context),
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        keyboardType: keyboardType,
        validator: validator,
        maxLines: maxLines,
        style: YorksProjectSetupDesktopTheme.body,
        decoration:
            YorksProjectSetupDesktopTheme.inputDecoration(
              hint: hint?.active(language),
              prefix: prefix,
              suffix: suffix,
            ).copyWith(
              constraints: maxLines == 1
                  ? BoxConstraints(minHeight: dense ? 33 : 38)
                  : null,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: maxLines > 1
                    ? 13
                    : dense
                    ? 7
                    : 10,
              ),
              prefixIconConstraints: dense
                  ? const BoxConstraints(minWidth: 38, minHeight: 33)
                  : null,
            ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label.active(language)),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppColors.error),
                ),
              if (optional &&
                  !label
                      .active(language)
                      .toLowerCase()
                      .trim()
                      .endsWith(
                        '(${YorksV1ProjectStrings.optional.active(language).toLowerCase()})',
                      ))
                TextSpan(
                  text:
                      ' (${YorksV1ProjectStrings.optional.active(language).toLowerCase()})',
                  style: const TextStyle(
                    color: YorksProjectSetupDesktopTheme.muted,
                  ),
                ),
            ],
          ),
          style: YorksProjectSetupDesktopTheme.label,
        ),
        SizedBox(height: dense ? 5 : 6),
        input,
        if (helper != null) ...[
          SizedBox(height: maxLines > 1 ? 9 : 5),
          Text(
            helper!.active(language),
            style: YorksProjectSetupDesktopTheme.small,
          ),
        ],
      ],
    );
  }
}

class _DesktopDetailsStage extends StatelessWidget {
  const _DesktopDetailsStage(this.config);
  final _DetailsStage config;
  @override
  Widget build(BuildContext context) {
    final c = config;
    final language = c.language;
    String? required(String? value) => value == null || value.trim().isEmpty
        ? YorksV1ProjectStrings.requiredField.active(language)
        : null;
    Widget pair(Widget first, Widget second) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 30),
        Expanded(child: second),
      ],
    );
    Widget date(bool start) => _DesktopDateField(
      copy: start
          ? YorksV1ProjectStrings.startDate
          : YorksV1ProjectStrings.endDate,
      language: language,
      controller: start ? c.startDateController : c.endDateController,
      focusNode: c.focusNodes[start ? 'startDate' : 'endDate'],
      onPick: start ? c.onSelectStartDate : c.onSelectEndDate,
      onToday: start ? c.onTodayStart : c.onTodayEnd,
      error:
          !start &&
              c.validationErrors.contains(
                YorksV1ProjectValidationCode.invalidDateRange,
              )
          ? YorksV1ProjectStrings.endDateAfterStart.active(language)
          : null,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _DesktopPanel(
            padding: const EdgeInsets.fromLTRB(23, 27, 23, 24),
            minHeight: 724,
            child: Form(
              key: c.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopStageHeading(
                    stage: YorksV1ProjectCreationStage.projectDetails,
                    language: language,
                    description: YorksV1ProjectSetupDesktopStrings.detailsHelp,
                  ),
                  const SizedBox(height: 26),
                  pair(
                    _DesktopField(
                      key: const ValueKey('yorks-v1-project-reference'),
                      label: YorksV1ProjectStrings.yorksReference,
                      language: language,
                      controller: c.referenceController,
                      focusNode: c.focusNodes['reference'],
                      required: true,
                      hint: YorksV1ProjectStrings.yorksReferenceHint,
                      helper:
                          c.referenceHint ??
                          YorksV1ProjectStrings.yorksReferenceHelp,
                      validator: required,
                      onChanged: c.onReferenceChanged,
                    ),
                    _DesktopField(
                      key: const ValueKey('yorks-v1-project-name'),
                      label: YorksV1ProjectStrings.projectName,
                      language: language,
                      controller: c.nameController,
                      focusNode: c.focusNodes['name'],
                      required: true,
                      hint: YorksV1ProjectStrings.projectNameHint,
                      validator: required,
                      onChanged: c.onNameChanged,
                    ),
                  ),
                  const SizedBox(height: 28),
                  pair(
                    _DesktopField(
                      key: const ValueKey('yorks-v1-project-client'),
                      label: YorksV1ProjectStrings.client,
                      language: language,
                      controller: c.clientController,
                      focusNode: c.focusNodes['client'],
                      optional: true,
                      hint: YorksV1ProjectStrings.clientHint,
                      onChanged: c.onClientChanged,
                    ),
                    _DesktopField(
                      key: const ValueKey('yorks-v1-project-job-contract'),
                      label: YorksV1ProjectStrings.jobOrContractReference,
                      language: language,
                      controller: c.jobOrContractController,
                      focusNode: c.focusNodes['contract'],
                      optional: true,
                      hint: YorksV1ProjectStrings.jobOrContractReferenceHint,
                      onChanged: c.onJobOrContractChanged,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        textStyle: YorksProjectSetupDesktopTheme.small,
                        minimumSize: const Size(44, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () =>
                          c.onContactsExpanded(!c.contactsExpanded),
                      child: Text(
                        YorksV1ProjectStrings.optionalContacts.active(language),
                      ),
                    ),
                  ),
                  if (c.contactsExpanded) ...[
                    pair(
                      _DesktopField(
                        label: YorksV1ProjectStrings.contactName,
                        language: language,
                        controller: c.contactNameController,
                        focusNode: c.focusNodes['contactName'],
                        onChanged: c.onContactChanged,
                      ),
                      _DesktopField(
                        label: YorksV1ProjectStrings.contactPhone,
                        language: language,
                        controller: c.contactPhoneController,
                        focusNode: c.focusNodes['contactPhone'],
                        onChanged: c.onContactChanged,
                      ),
                    ),
                    const SizedBox(height: 16),
                    pair(
                      _DesktopField(
                        label: YorksV1ProjectStrings.contactEmail,
                        language: language,
                        controller: c.contactEmailController,
                        focusNode: c.focusNodes['contactEmail'],
                        onChanged: c.onContactChanged,
                      ),
                      _DesktopField(
                        label: YorksV1ProjectStrings.contactAddress,
                        language: language,
                        controller: c.contactAddressController,
                        focusNode: c.focusNodes['contactAddress'],
                        onChanged: c.onContactChanged,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 5),
                  _DesktopField(
                    key: const ValueKey('yorks-v1-project-site'),
                    label: YorksV1ProjectStrings.siteLocation,
                    language: language,
                    controller: c.siteController,
                    focusNode: c.focusNodes['site'],
                    optional: true,
                    hint: YorksV1ProjectStrings.siteLocationHint,
                    helper: YorksV1ProjectSetupDesktopStrings.siteHelp,
                    onChanged: c.onSiteChanged,
                  ),
                  const SizedBox(height: 33),
                  pair(date(true), date(false)),
                  const SizedBox(height: 6),
                  _DesktopField(
                    key: const ValueKey('yorks-v1-project-notes'),
                    label: YorksV1ProjectStrings.notes,
                    language: language,
                    controller: c.notesController,
                    focusNode: c.focusNodes['notes'],
                    optional: true,
                    hint: YorksV1ProjectStrings.notesHint,
                    maxLines: 3,
                    helper: YorksV1ProjectSetupDesktopStrings.notesHelp,
                    onChanged: c.onNotesChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopDateField extends StatelessWidget {
  const _DesktopDateField({
    required this.copy,
    required this.language,
    required this.controller,
    required this.focusNode,
    required this.onPick,
    required this.onToday,
    this.error,
  });
  final TranslatableString copy;
  final AppLanguage language;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onPick;
  final VoidCallback onToday;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DesktopField(
        key: ValueKey('yorks-v1-project-date-${copy.en}'),
        label: copy,
        language: language,
        controller: controller,
        focusNode: focusNode,
        optional: true,
        hint: YorksV1ProjectStrings.dateInputHint,
        keyboardType: TextInputType.datetime,
        prefix: IconButton(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _ProjectSetupReadOnlyScope.of(context) ? null : onPick,
          tooltip: YorksV1ProjectStrings.selectDate.active(language),
          icon: const Icon(Icons.calendar_month_outlined, size: 19),
        ),
        suffix: IconButton(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _ProjectSetupReadOnlyScope.of(context)
              ? null
              : controller.clear,
          tooltip: YorksV1ProjectSetupDesktopStrings.clearDate.active(language),
          icon: const Icon(Icons.close, size: 18),
        ),
        validator: (value) =>
            value == null ||
                value.trim().isEmpty ||
                _parseTypedDate(value) != null
            ? null
            : YorksV1ProjectStrings.invalidTypedDate.active(language),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Text(
              error ??
                  YorksV1ProjectStrings.typedDateFormatHelp.active(language),
              style: YorksProjectSetupDesktopTheme.small.copyWith(
                color: error == null
                    ? YorksProjectSetupDesktopTheme.muted
                    : AppColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: _ProjectSetupReadOnlyScope.of(context) ? null : onToday,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: YorksProjectSetupDesktopTheme.small,
            ),
            child: Text(YorksV1ProjectStrings.today.active(language)),
          ),
        ],
      ),
    ],
  );
}

class _DesktopPartiesStage extends StatelessWidget {
  const _DesktopPartiesStage(this.config);
  final _PartiesAndAccessStage config;
  @override
  Widget build(BuildContext context) {
    final c = config;
    final language = c.language;
    Widget namedParties(
      YorksV1ProjectPartyKind kind,
      TranslatableString copy,
      TextEditingController controller,
      String focusKey,
      VoidCallback add,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _DesktopField(
                key: ValueKey(
                  kind == YorksV1ProjectPartyKind.subcontractor
                      ? 'yorks-v1-project-subcontractors'
                      : 'yorks-v1-project-other-contractors',
                ),
                label: copy,
                language: language,
                dense: true,
                controller: controller,
                focusNode: c.focusNodes[focusKey],
                optional: true,
                hint: copy,
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: add,
              style: YorksProjectSetupDesktopTheme.outlineButton.copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(64, 34)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const WidgetStatePropertyAll(
                  YorksProjectSetupDesktopTheme.blue,
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: YorksProjectSetupDesktopTheme.blue),
                ),
              ),
              child: Text(YorksV1ProjectStrings.add.active(language)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (var index = 0; index < c.draft.parties.length; index++)
              if (c.draft.parties[index].kind == kind)
                InputChip(
                  key: ValueKey(
                    'yorks-v1-party-${c.draft.parties[index].retainedFields['local_row_id'] ?? '${kind.name}-$index'}',
                  ),
                  label: Text(
                    c.draft.parties[index].name,
                    style: YorksProjectSetupDesktopTheme.small.copyWith(
                      color: YorksProjectSetupDesktopTheme.navy,
                    ),
                  ),
                  onDeleted: () => c.onRemoveParty(index),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  padding: EdgeInsets.zero,
                  backgroundColor: YorksProjectSetupDesktopTheme.tableHeader,
                  side: const BorderSide(
                    color: YorksProjectSetupDesktopTheme.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
          ],
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopStageHeading(
          stage: YorksV1ProjectCreationStage.partiesAndAccess,
          language: language,
          description: YorksV1ProjectSetupDesktopStrings.partiesHelp,
        ),
        const SizedBox(height: 16),
        _DesktopPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          minHeight: 254,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    YorksV1ProjectSetupDesktopStrings.projectParties.active(
                      language,
                    ),
                    style: YorksProjectSetupDesktopTheme.section,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    YorksV1ProjectStrings.optional.active(language),
                    style: YorksProjectSetupDesktopTheme.small,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                YorksV1ProjectSetupDesktopStrings.partiesOptionalHelp.active(
                  language,
                ),
                style: YorksProjectSetupDesktopTheme.small,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DesktopField(
                      key: const ValueKey('yorks-v1-project-consultant'),
                      label: YorksV1ProjectStrings.consultant,
                      language: language,
                      dense: true,
                      controller: c.consultantController,
                      focusNode: c.focusNodes['consultant'],
                      optional: true,
                      hint: YorksV1ProjectStrings.consultant,
                      prefix: const Icon(Icons.search, size: 19),
                      onChanged: c.onConsultantChanged,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: _DesktopField(
                      key: const ValueKey('yorks-v1-project-main-contractor'),
                      label: YorksV1ProjectStrings.mainContractor,
                      language: language,
                      dense: true,
                      controller: c.mainContractorController,
                      focusNode: c.focusNodes['mainContractor'],
                      optional: true,
                      hint: YorksV1ProjectStrings.mainContractor,
                      prefix: const Icon(Icons.search, size: 19),
                      onChanged: c.onMainContractorChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: namedParties(
                      YorksV1ProjectPartyKind.subcontractor,
                      YorksV1ProjectStrings.subcontractors,
                      c.subcontractorController,
                      'subcontractor',
                      c.onAddSubcontractor,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: namedParties(
                      YorksV1ProjectPartyKind.otherContractor,
                      YorksV1ProjectStrings.otherContractors,
                      c.otherContractorController,
                      'otherContractor',
                      c.onAddOtherContractor,
                    ),
                  ),
                ],
              ),
              if (c.onUndoPartyRemoval != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: c.onUndoPartyRemoval,
                    icon: const Icon(Icons.undo, size: 16),
                    label: Text(
                      YorksV1ProjectStrings.undoPartyRemoval.active(language),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        _DesktopPanel(
          padding: const EdgeInsets.fromLTRB(13, 8, 15, 14),
          minHeight: 415,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                YorksV1ProjectSetupDesktopStrings.projectTeamAccess.active(
                  language,
                ),
                style: YorksProjectSetupDesktopTheme.section,
              ),
              const SizedBox(height: 3),
              Text(
                YorksV1ProjectSetupDesktopStrings.teamAccessHelp.active(
                  language,
                ),
                style: YorksProjectSetupDesktopTheme.small,
              ),
              const SizedBox(height: 6),
              if (!c.showTeam && c.editItem != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final member in c.editItem!.activeMembers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${member.displayName ?? YorksV1ProjectStrings.profileId.active(language)} · ${YorksV1ProjectStrings.roleLabel(member.projectRole.wireValue).active(language)}',
                          style: YorksProjectSetupDesktopTheme.body,
                        ),
                      ),
                    Text(
                      YorksV1ProjectStrings.accessAppliedSeparately.active(
                        language,
                      ),
                      style: YorksProjectSetupDesktopTheme.small,
                    ),
                    TextButton.icon(
                      onPressed: c.onManageAccess,
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: Text(
                        YorksV1ProjectStrings.manageAccess.active(language),
                      ),
                    ),
                  ],
                )
              else
                _DesktopTeamDirectory(config: c),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopTeamDirectory extends StatefulWidget {
  const _DesktopTeamDirectory({required this.config});
  final _PartiesAndAccessStage config;
  @override
  State<_DesktopTeamDirectory> createState() => _DesktopTeamDirectoryState();
}

class _DesktopTeamDirectoryState extends State<_DesktopTeamDirectory> {
  String _query = '';
  YorksV1Role? _role;
  @override
  void didUpdateWidget(covariant _DesktopTeamDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.draft.draftId != widget.config.draft.draftId ||
        oldWidget.config.draft.backendIdentity !=
            widget.config.draft.backendIdentity) {
      _query = '';
      _role = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final language = c.language;
    final directory =
        c.teamDirectory.asData?.value ??
        const <YorksV1ProjectTeamDirectoryMember>[];
    final byId = {for (final member in directory) member.authUserId: member};
    final selectedIds = c.draft.initialMembers
        .map((member) => member.authUserId)
        .toSet();
    final siteCreator = c.creatorRole == YorksV1Role.siteEngineer;
    final hasProjectEngineer = c.draft.initialMembers.any(
      (member) =>
          member.projectRole == YorksV1ProjectMembershipRole.projectEngineer,
    );
    final choices = directory
        .where(
          (member) =>
              member.authUserId != c.creatorAuthUserId &&
              !selectedIds.contains(member.authUserId) &&
              (!siteCreator ||
                  member.eligibleRole == YorksV1Role.projectEngineer) &&
              (_role == null || member.eligibleRole == _role) &&
              _safeMemberDisplayName(
                member,
              ).toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    final creatorProjectRole = _creatorProjectRole(c.creatorRole);
    final selectedCount =
        c.draft.initialMembers
            .where(
              (member) =>
                  member.authUserId != c.creatorAuthUserId ||
                  member.projectRole != creatorProjectRole,
            )
            .length +
        (creatorProjectRole == null ? 0 : 1);
    Widget avatar(String name) {
      final initials = name
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part.characters.first)
          .join()
          .toUpperCase();
      return CircleAvatar(
        radius: 15,
        backgroundColor: const Color(0xFFE0E8F8),
        child: Text(
          initials,
          style: YorksProjectSetupDesktopTheme.small.copyWith(
            color: YorksProjectSetupDesktopTheme.navy,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget selectedRow(
      String name,
      YorksV1ProjectMembershipRole role, {
      VoidCallback? remove,
      bool automatic = false,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: YorksProjectSetupDesktopTheme.border),
        ),
      ),
      child: Row(
        children: [
          avatar(name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: YorksProjectSetupDesktopTheme.body.copyWith(
                    fontSize: 13,
                  ),
                ),
                if (automatic)
                  Text(
                    YorksV1ProjectStrings.automaticCreatorMembership.active(
                      language,
                    ),
                    style: YorksProjectSetupDesktopTheme.small.copyWith(
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            YorksV1ProjectStrings.roleLabel(role.wireValue).active(language),
            style: YorksProjectSetupDesktopTheme.small.copyWith(fontSize: 11.5),
          ),
          if (remove != null)
            IconButton(
              onPressed: remove,
              tooltip: YorksV1ProjectStrings.remove.active(language),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
            ),
        ],
      ),
    );
    return Row(
      key: ValueKey(
        'desktop-team-directory-${c.draft.backendIdentity}-${c.draft.draftId}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 479,
          child: _DesktopPanel(
            padding: const EdgeInsets.all(11),
            minHeight: 333,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        readOnly: _ProjectSetupReadOnlyScope.of(context),
                        key: const ValueKey('yorks-v1-project-team-search'),
                        style: YorksProjectSetupDesktopTheme.body,
                        decoration:
                            YorksProjectSetupDesktopTheme.inputDecoration(
                              hint: YorksV1ProjectStrings.searchTeam.active(
                                language,
                              ),
                              prefix: const Icon(Icons.search, size: 19),
                            ).copyWith(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 38,
                                minHeight: 33,
                              ),
                              labelText: YorksV1ProjectStrings.searchTeam
                                  .active(language),
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.never,
                            ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 118,
                      child: DropdownButtonFormField<YorksV1Role?>(
                        key: const ValueKey(
                          'yorks-v1-desktop-directory-role-filter',
                        ),
                        initialValue: _role,
                        isExpanded: true,
                        style: YorksProjectSetupDesktopTheme.small.copyWith(
                          color: YorksProjectSetupDesktopTheme.navy,
                        ),
                        decoration:
                            YorksProjectSetupDesktopTheme.inputDecoration()
                                .copyWith(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              YorksV1ProjectSetupDesktopStrings.allRoles.active(
                                language,
                              ),
                            ),
                          ),
                          for (final role in [
                            YorksV1Role.projectEngineer,
                            YorksV1Role.siteEngineer,
                          ])
                            DropdownMenuItem(
                              value: role,
                              child: Text(
                                YorksV1ProjectStrings.roleLabel(
                                  role.claimValue,
                                ).active(language),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _ProjectSetupReadOnlyScope.of(context)
                            ? null
                            : (value) => setState(() => _role = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _DesktopTableHeader(
                  cells: [
                    YorksV1ProjectSetupDesktopStrings.name.active(language),
                    YorksV1ProjectSetupDesktopStrings.role.active(language),
                    '',
                  ],
                  flex: const [53, 32, 15],
                  height: 32,
                ),
                SizedBox(
                  height: 248,
                  child: c.teamDirectory.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : c.teamDirectory.hasError
                      ? _TeamDirectoryUnavailable(
                          draft: c.draft,
                          language: language,
                          onRemoveMember: c.onRemoveInitialMember,
                        )
                      : choices.isEmpty
                      ? Center(
                          child: Text(
                            YorksV1ProjectStrings.noTeamSearchResults.active(
                              language,
                            ),
                            style: YorksProjectSetupDesktopTheme.small,
                          ),
                        )
                      : ListView.builder(
                          itemCount: choices.length,
                          itemBuilder: (context, index) {
                            final member = choices[index];
                            final role =
                                member.eligibleRole ==
                                    YorksV1Role.projectEngineer
                                ? YorksV1ProjectMembershipRole.projectEngineer
                                : YorksV1ProjectMembershipRole.siteEngineer;
                            final enabled = !siteCreator || !hasProjectEngineer;
                            return Container(
                              key: ValueKey(
                                'yorks-v1-desktop-directory-${member.authUserId}',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              constraints: const BoxConstraints(minHeight: 44),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: YorksProjectSetupDesktopTheme.border,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 53,
                                    child: Row(
                                      children: [
                                        avatar(_safeMemberDisplayName(member)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _safeMemberDisplayName(member),
                                            style: YorksProjectSetupDesktopTheme
                                                .body
                                                .copyWith(fontSize: 12.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 32,
                                    child: Text(
                                      YorksV1ProjectStrings.roleLabel(
                                        role.wireValue,
                                      ).active(language),
                                      style: YorksProjectSetupDesktopTheme.small
                                          .copyWith(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 15,
                                    child: TextButton(
                                      key: ValueKey(
                                        'yorks-v1-desktop-directory-add-${member.authUserId}',
                                      ),
                                      onPressed: enabled
                                          ? () => c.onAddInitialMember(
                                              member,
                                              role,
                                            )
                                          : null,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(44, 44),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        YorksV1ProjectStrings.add.active(
                                          language,
                                        ),
                                        style: YorksProjectSetupDesktopTheme
                                            .body
                                            .copyWith(
                                              color: enabled
                                                  ? YorksProjectSetupDesktopTheme
                                                        .blue
                                                  : AppColors.muted,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 521,
          child: _DesktopPanel(
            padding: const EdgeInsets.all(12),
            minHeight: 333,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${YorksV1ProjectStrings.selectedTeam.active(language)} ($selectedCount)',
                  style: YorksProjectSetupDesktopTheme.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                for (final role in [
                  YorksV1ProjectMembershipRole.projectEngineer,
                  YorksV1ProjectMembershipRole.siteEngineer,
                ]) ...[
                  Builder(
                    builder: (context) {
                      final selected = [
                        for (
                          var index = 0;
                          index < c.draft.initialMembers.length;
                          index++
                        )
                          if (c.draft.initialMembers[index].projectRole ==
                                  role &&
                              (c.draft.initialMembers[index].authUserId !=
                                      c.creatorAuthUserId ||
                                  role != creatorProjectRole))
                            index,
                      ];
                      final auto = creatorProjectRole == role;
                      if (selected.isEmpty && !auto) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            color: YorksProjectSetupDesktopTheme.tableHeader,
                            padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${(role == YorksV1ProjectMembershipRole.projectEngineer ? YorksV1ProjectStrings.projectEngineers : YorksV1ProjectStrings.siteEngineers).active(language)} (${selected.length + (auto ? 1 : 0)})',
                                  style: YorksProjectSetupDesktopTheme.label
                                      .copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  (role ==
                                              YorksV1ProjectMembershipRole
                                                  .projectEngineer
                                          ? YorksV1ProjectSetupDesktopStrings
                                                .projectEngineerAccessHelp
                                          : YorksV1ProjectSetupDesktopStrings
                                                .siteEngineerAccessHelp)
                                      .active(language),
                                  style: YorksProjectSetupDesktopTheme.small
                                      .copyWith(fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          if (auto)
                            selectedRow(
                              YorksV1ProjectStrings.you.active(language),
                              role,
                              automatic: true,
                            ),
                          for (final index in selected)
                            selectedRow(
                              _safeMemberDisplayName(
                                byId[c.draft.initialMembers[index].authUserId],
                              ),
                              role,
                              remove: () => c.onRemoveInitialMember(index),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (selectedCount == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Text(
                      YorksV1ProjectStrings.noActiveAssignments.active(
                        language,
                      ),
                      style: YorksProjectSetupDesktopTheme.small,
                    ),
                  ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: YorksProjectSetupDesktopTheme.help,
                    border: Border.all(color: AppColors.blueContainerStrong),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info,
                        color: YorksProjectSetupDesktopTheme.blue,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              YorksV1ProjectSetupDesktopStrings
                                  .aboutAccessLevels
                                  .active(language),
                              style: YorksProjectSetupDesktopTheme.small
                                  .copyWith(
                                    color: YorksProjectSetupDesktopTheme.navy,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            Text(
                              (siteCreator
                                      ? YorksV1ProjectStrings
                                            .initialProjectEngineerHint
                                      : YorksV1ProjectStrings
                                            .projectTeamPermissionDescription)
                                  .active(language),
                              style: YorksProjectSetupDesktopTheme.small
                                  .copyWith(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopTableHeader extends StatelessWidget {
  const _DesktopTableHeader({
    required this.cells,
    required this.flex,
    this.height = 43,
  });
  final List<String> cells;
  final List<int> flex;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: height),
    color: YorksProjectSetupDesktopTheme.tableHeader,
    child: IntrinsicHeight(
      child: Row(
        children: [
          for (var index = 0; index < cells.length; index++)
            Expanded(
              flex: flex[index],
              child: Container(
                alignment: AlignmentDirectional.centerStart,
                padding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: height <= 32 ? 5 : 9,
                ),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    end: BorderSide(
                      color: index < cells.length - 1
                          ? YorksProjectSetupDesktopTheme.border
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  cells[index],
                  style: YorksProjectSetupDesktopTheme.small.copyWith(
                    color: YorksProjectSetupDesktopTheme.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _DesktopBuildingsStage extends StatefulWidget {
  const _DesktopBuildingsStage(this.config);
  final _BuildingsStage config;
  @override
  State<_DesktopBuildingsStage> createState() => _DesktopBuildingsStageState();
}

class _DesktopBuildingsStageState extends State<_DesktopBuildingsStage> {
  String _query = '';
  @override
  void didUpdateWidget(covariant _DesktopBuildingsStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.draft.draftId != widget.config.draft.draftId ||
        oldWidget.config.draft.backendIdentity !=
            widget.config.draft.backendIdentity) {
      _query = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final language = c.language;
    final editorPending =
        c.editingBuildingIndex != null ||
        [
          c.codeController,
          c.nameController,
          c.floorsController,
          c.deliveryAddressController,
        ].any((controller) => controller.text.trim().isNotEmpty) ||
        c.hasFrpRoom;
    final rows = [
      for (var index = 0; index < c.draft.buildings.length; index++)
        if ('${c.draft.buildings[index].code} ${c.draft.buildings[index].name}'
            .toLowerCase()
            .contains(_query.trim().toLowerCase()))
          index,
    ];
    final current = c.editingBuildingIndex == null
        ? null
        : c.draft.buildings[c.editingBuildingIndex!];
    Widget field({
      required TranslatableString copy,
      required TextEditingController controller,
      required String focus,
      required String key,
      bool required = false,
      int lines = 1,
      TranslatableString? helper,
    }) => _DesktopField(
      key: ValueKey(key),
      label: copy,
      language: language,
      controller: controller,
      focusNode: c.focusNodes[focus],
      required: required,
      optional: !required,
      helper: helper,
      maxLines: lines,
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? YorksV1ProjectStrings.requiredField.active(language)
                : null
          : null,
    );
    return Row(
      key: ValueKey(
        'desktop-building-editor-${c.draft.backendIdentity}-${c.draft.draftId}',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 644,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopStageHeading(
                stage: YorksV1ProjectCreationStage.buildings,
                language: language,
                description: YorksV1ProjectSetupDesktopStrings.buildingsHelp,
              ),
              const SizedBox(height: 24),
              _DesktopPanel(
                padding: EdgeInsets.zero,
                minHeight: 637,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              YorksV1ProjectSetupDesktopStrings
                                  .physicalBuildings
                                  .active(language)
                                  .replaceFirst(
                                    '{count}',
                                    '${c.draft.buildings.length}',
                                  ),
                              style: YorksProjectSetupDesktopTheme.label
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(
                            width: 210,
                            child: TextField(
                              readOnly: _ProjectSetupReadOnlyScope.of(context),
                              key: const ValueKey(
                                'yorks-v1-desktop-building-search',
                              ),
                              style: YorksProjectSetupDesktopTheme.body,
                              decoration:
                                  YorksProjectSetupDesktopTheme.inputDecoration(
                                    hint: YorksV1ProjectSetupDesktopStrings
                                        .findBuilding
                                        .active(language),
                                    prefix: const Icon(Icons.search, size: 19),
                                  ).copyWith(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    labelText: YorksV1ProjectSetupDesktopStrings
                                        .findBuilding
                                        .active(language),
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.never,
                                  ),
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'yorks-v1-desktop-add-building',
                            ),
                            onPressed: editorPending
                                ? null
                                : () {
                                    c.onCancelEditing();
                                    c.focusNodes['buildingName']
                                        ?.requestFocus();
                                  },
                            style: YorksProjectSetupDesktopTheme.outlineButton
                                .copyWith(
                                  minimumSize: const WidgetStatePropertyAll(
                                    Size(149, 38),
                                  ),
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(
                              YorksV1ProjectStrings.addBuilding.active(
                                language,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _DesktopTableHeader(
                      cells: [
                        YorksV1ProjectSetupDesktopStrings.code.active(language),
                        YorksV1ProjectStrings.buildingName.active(language),
                        YorksV1ProjectSetupDesktopStrings.levels.active(
                          language,
                        ),
                        YorksV1ProjectSetupDesktopStrings.frp.active(language),
                        '',
                      ],
                      flex: const [15, 36, 25, 12, 12],
                    ),
                    for (final index in rows)
                      Builder(
                        builder: (context) {
                          final building = c.draft.buildings[index];
                          final identity =
                              building.localRowId ??
                              building.sourceScopeId ??
                              '$index';
                          final selected = c.editingBuildingIndex == index;
                          final canSelect = !editorPending || selected;
                          final cells = [
                            building.code.trim().isEmpty ? '—' : building.code,
                            building.name,
                            building.floorsOrLevels.isEmpty
                                ? '—'
                                : building.floorsOrLevels.join(', '),
                            (building.hasFrpRoom
                                    ? YorksV1ProjectSetupDesktopStrings.yes
                                    : YorksV1ProjectSetupDesktopStrings.no)
                                .active(language),
                          ];
                          return Material(
                            key: ValueKey(
                              'yorks-v1-desktop-building-$identity',
                            ),
                            color: selected
                                ? YorksProjectSetupDesktopTheme.selected
                                : Colors.white,
                            child: InkWell(
                              onTap: canSelect && !selected
                                  ? () => c.onEditBuilding(index)
                                  : null,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 50,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: const BorderSide(
                                      color:
                                          YorksProjectSetupDesktopTheme.border,
                                    ),
                                    left: BorderSide(
                                      color: selected
                                          ? YorksProjectSetupDesktopTheme.blue
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    children: [
                                      for (
                                        var column = 0;
                                        column < cells.length;
                                        column++
                                      )
                                        Expanded(
                                          flex: const [15, 36, 25, 12][column],
                                          child: Container(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 17,
                                              vertical: 11,
                                            ),
                                            decoration: const BoxDecoration(
                                              border: BorderDirectional(
                                                end: BorderSide(
                                                  color:
                                                      YorksProjectSetupDesktopTheme
                                                          .border,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              cells[column],
                                              style: YorksProjectSetupDesktopTheme
                                                  .body
                                                  .copyWith(
                                                    color:
                                                        selected && column == 0
                                                        ? YorksProjectSetupDesktopTheme
                                                              .blue
                                                        : YorksProjectSetupDesktopTheme
                                                              .navy,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        flex: 12,
                                        child: PopupMenuButton<String>(
                                          key: ValueKey(
                                            'yorks-v1-desktop-building-menu-$identity',
                                          ),
                                          tooltip: YorksV1ProjectStrings.manage
                                              .active(language),
                                          icon: const Icon(
                                            Icons.more_vert,
                                            size: 20,
                                          ),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              enabled:
                                                  !editorPending || selected,
                                              child: Text(
                                                YorksV1ProjectStrings
                                                    .editBuilding
                                                    .active(language),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'duplicate',
                                              enabled: !editorPending,
                                              child: Text(
                                                YorksV1ProjectStrings
                                                    .addAnotherLikeThis
                                                    .active(language),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'up',
                                              enabled:
                                                  !editorPending && index > 0,
                                              child: Text(
                                                YorksV1ProjectStrings
                                                    .moveBuildingUp
                                                    .active(language),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'down',
                                              enabled:
                                                  !editorPending &&
                                                  index <
                                                      c.draft.buildings.length -
                                                          1,
                                              child: Text(
                                                YorksV1ProjectStrings
                                                    .moveBuildingDown
                                                    .active(language),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'remove',
                                              enabled:
                                                  !editorPending &&
                                                  building.sourceScopeId ==
                                                      null,
                                              child: Text(
                                                (building.sourceScopeId == null
                                                        ? YorksV1ProjectStrings
                                                              .remove
                                                        : YorksV1ProjectStrings
                                                              .existingBuildingRetirementBlocked)
                                                    .active(language),
                                              ),
                                            ),
                                          ],
                                          onSelected: (action) {
                                            switch (action) {
                                              case 'edit':
                                                if (!selected) {
                                                  c.onEditBuilding(index);
                                                }
                                              case 'duplicate':
                                                c.onDuplicateBuilding(index);
                                              case 'up':
                                                c.onMoveBuilding(index, -1);
                                              case 'down':
                                                c.onMoveBuilding(index, 1);
                                              case 'remove':
                                                c.onRemoveBuilding(index);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 35),
                        child: Text(
                          YorksV1ProjectStrings.noBuildingsAdded.active(
                            language,
                          ),
                          textAlign: TextAlign.center,
                          style: YorksProjectSetupDesktopTheme.small,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
                      child: Column(
                        children: [
                          const Divider(
                            height: 1,
                            color: YorksProjectSetupDesktopTheme.border,
                          ),
                          const SizedBox(height: 17),
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 24,
                                color: YorksProjectSetupDesktopTheme.muted,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      YorksV1ProjectStrings.commonScope.active(
                                        language,
                                      ),
                                      style: YorksProjectSetupDesktopTheme.label
                                          .copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      YorksV1ProjectSetupDesktopStrings
                                          .commonAddedAutomatically
                                          .active(language),
                                      style:
                                          YorksProjectSetupDesktopTheme.small,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                YorksV1ProjectSetupDesktopStrings.notEditable
                                    .active(language),
                                style: YorksProjectSetupDesktopTheme.small,
                              ),
                            ],
                          ),
                          if (c.onUndoRemove != null)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: c.onUndoRemove,
                                icon: const Icon(Icons.undo, size: 17),
                                label: Text(
                                  YorksV1ProjectStrings.undoBuildingChange
                                      .active(language),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 19),
        Expanded(
          flex: 356,
          child: Container(
            padding: const EdgeInsetsDirectional.only(start: 26),
            constraints: const BoxConstraints(minHeight: 730),
            decoration: const BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: YorksProjectSetupDesktopTheme.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  (current == null
                          ? YorksV1ProjectStrings.addBuilding
                          : YorksV1ProjectStrings.editBuilding)
                      .active(language),
                  style: YorksProjectSetupDesktopTheme.section.copyWith(
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  current?.code ?? '',
                  style: YorksProjectSetupDesktopTheme.body.copyWith(
                    fontSize: 16,
                    color: YorksProjectSetupDesktopTheme.muted,
                  ),
                ),
                const SizedBox(height: 21),
                field(
                  copy: YorksV1ProjectStrings.buildingName,
                  controller: c.nameController,
                  focus: 'buildingName',
                  key: 'yorks-v1-building-name',
                  required: true,
                ),
                const SizedBox(height: 25),
                field(
                  copy: YorksV1ProjectStrings.buildingCode,
                  controller: c.codeController,
                  focus: 'buildingCode',
                  key: 'yorks-v1-building-code',
                  helper:
                      YorksV1ProjectSetupDesktopStrings.leaveBuildingCodeBlank,
                ),
                const SizedBox(height: 27),
                field(
                  copy: YorksV1ProjectStrings.floorsOrLevels,
                  controller: c.floorsController,
                  focus: 'buildingFloors',
                  key: 'yorks-v1-building-floors',
                  helper: YorksV1ProjectStrings.levelsLabelsHint,
                ),
                const SizedBox(height: 25),
                field(
                  copy: YorksV1ProjectStrings.deliveryAddress,
                  controller: c.deliveryAddressController,
                  focus: 'buildingAddress',
                  key: 'yorks-v1-building-delivery-address',
                  lines: 3,
                ),
                const SizedBox(height: 13),
                CheckboxListTile(
                  key: const ValueKey('yorks-v1-desktop-building-frp'),
                  value: c.hasFrpRoom,
                  onChanged: _ProjectSetupReadOnlyScope.of(context)
                      ? null
                      : (value) => c.onHasFrpRoomChanged(value ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: YorksProjectSetupDesktopTheme.blue,
                  title: Text(
                    YorksV1ProjectStrings.hasFrpRoom.active(language),
                    style: YorksProjectSetupDesktopTheme.body,
                  ),
                ),
                const SizedBox(height: 27),
                const Divider(
                  height: 1,
                  color: YorksProjectSetupDesktopTheme.border,
                ),
                const SizedBox(height: 50),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('yorks-v1-desktop-cancel-building'),
                      onPressed: c.onCancelEditing,
                      style: YorksProjectSetupDesktopTheme.outlineButton
                          .copyWith(
                            minimumSize: const WidgetStatePropertyAll(
                              Size(154, 44),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      child: Text(
                        YorksV1ProjectSetupDesktopStrings.cancelEdit.active(
                          language,
                        ),
                      ),
                    ),
                    FilledButton(
                      key: const ValueKey('yorks-v1-desktop-apply-building'),
                      onPressed: c.nameController.text.trim().isEmpty
                          ? null
                          : c.onAddBuilding,
                      style: YorksProjectSetupDesktopTheme.navyButton.copyWith(
                        minimumSize: const WidgetStatePropertyAll(
                          Size(172, 44),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        (c.editingBuildingIndex == null
                                ? YorksV1ProjectStrings.addBuilding
                                : YorksV1ProjectSetupDesktopStrings
                                      .saveBuilding)
                            .active(language),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopAttachmentsStage extends StatefulWidget {
  const _DesktopAttachmentsStage(this.config);
  final _AttachmentsStage config;
  @override
  State<_DesktopAttachmentsStage> createState() =>
      _DesktopAttachmentsStageState();
}

class _DesktopAttachmentsStageState extends State<_DesktopAttachmentsStage> {
  String _query = '';
  String _category = 'all';
  @override
  void didUpdateWidget(covariant _DesktopAttachmentsStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.draft.draftId != widget.config.draft.draftId ||
        oldWidget.config.draft.backendIdentity !=
            widget.config.draft.backendIdentity) {
      _query = '';
      _category = 'all';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final language = c.language;
    final rows = [
      for (var index = 0; index < c.draft.attachments.length; index++)
        if (c.draft.attachments[index].fileName.toLowerCase().contains(
              _query.trim().toLowerCase(),
            ) &&
            (_category == 'all' ||
                c.draft.attachments[index].effectiveCategoryKey == _category))
          index,
    ];
    return Column(
      key: ValueKey(
        'desktop-attachment-register-${c.draft.backendIdentity}-${c.draft.draftId}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopStageHeading(
          stage: YorksV1ProjectCreationStage.attachments,
          language: language,
          description: YorksV1ProjectSetupDesktopStrings.attachmentsHelp,
        ),
        const SizedBox(height: 24),
        _DesktopPanel(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 11),
          minHeight: 642,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProjectAttachmentDropzone(
                language: language,
                onPick: c.onAddAttachment,
                onDropped: c.onDroppedAttachments,
                onDropError: c.onDropError,
              ),
              const SizedBox(height: 19),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.draft.attachments.length} ${YorksV1ProjectStrings.files.active(language).toLowerCase()}',
                      style: YorksProjectSetupDesktopTheme.section.copyWith(
                        fontSize: 18,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 243,
                    child: TextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      key: const ValueKey('yorks-v1-desktop-file-search'),
                      style: YorksProjectSetupDesktopTheme.body,
                      decoration:
                          YorksProjectSetupDesktopTheme.inputDecoration(
                            hint: YorksV1ProjectSetupDesktopStrings.searchFiles
                                .active(language),
                            prefix: const Icon(Icons.search, size: 19),
                          ).copyWith(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            labelText: YorksV1ProjectSetupDesktopStrings
                                .searchFiles
                                .active(language),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                          ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey(
                        'yorks-v1-desktop-file-category-filter',
                      ),
                      initialValue: _category,
                      isExpanded: true,
                      style: YorksProjectSetupDesktopTheme.small.copyWith(
                        color: YorksProjectSetupDesktopTheme.navy,
                      ),
                      decoration:
                          YorksProjectSetupDesktopTheme.inputDecoration()
                              .copyWith(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                              ),
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            YorksV1ProjectSetupDesktopStrings.allCategories
                                .active(language),
                          ),
                        ),
                        for (final category
                            in YorksV1ProjectAttachmentCategory.values)
                          DropdownMenuItem(
                            value: category.wireValue,
                            child: Text(
                              _attachmentCategoryLabel(
                                category,
                              ).active(language),
                            ),
                          ),
                      ],
                      onChanged: _ProjectSetupReadOnlyScope.of(context)
                          ? null
                          : (value) =>
                                setState(() => _category = value ?? 'all'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                YorksV1ProjectSetupDesktopStrings.categoryHelp.active(language),
                style: YorksProjectSetupDesktopTheme.small,
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: YorksProjectSetupDesktopTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Column(
                    children: [
                      _DesktopTableHeader(
                        cells: [
                          YorksV1ProjectStrings.attachmentFileName.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.category.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.preview.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.status.active(
                            language,
                          ),
                          '',
                        ],
                        flex: const [34, 20, 17, 22, 7],
                        height: 42,
                      ),
                      for (final index in rows)
                        Builder(
                          builder: (context) {
                            final file = c.draft.attachments[index];
                            final identity = file.localId ?? '$index';
                            final manifest = c.setupState?.operation?.files
                                .where(
                                  (item) =>
                                      item.localId == file.localId ||
                                      (file.localId == null &&
                                          item.fileName == file.fileName &&
                                          item.contentHash == file.contentHash),
                                )
                                .firstOrNull;
                            final pendingBytes = c._pendingFileFor(
                              file,
                              c.pendingFiles,
                            );
                            final fileStatus = manifest?.status;
                            final ready =
                                fileStatus ==
                                YorksV1ProjectSetupFileStatus.ready;
                            final removed =
                                fileStatus ==
                                YorksV1ProjectSetupFileStatus.removed;
                            final failed =
                                fileStatus ==
                                    YorksV1ProjectSetupFileStatus.failed ||
                                fileStatus ==
                                    YorksV1ProjectSetupFileStatus
                                        .outcomeUncertain;
                            final needsReselect =
                                pendingBytes == null && !ready && !removed;
                            final status = switch (fileStatus) {
                              YorksV1ProjectSetupFileStatus.ready =>
                                YorksV1ProjectStrings.fileReady,
                              YorksV1ProjectSetupFileStatus.removed =>
                                YorksV1ProjectStrings.fileRemoved,
                              YorksV1ProjectSetupFileStatus.uploading =>
                                YorksV1ProjectStrings.fileUploading,
                              YorksV1ProjectSetupFileStatus.failed =>
                                YorksV1ProjectStrings.fileFailed,
                              YorksV1ProjectSetupFileStatus.outcomeUncertain =>
                                YorksV1ProjectStrings.fileChecking,
                              _ =>
                                needsReselect
                                    ? YorksV1ProjectStrings.fileReselect
                                    : YorksV1ProjectSetupDesktopStrings
                                          .selectedLocally,
                            };
                            final canRemove = manifest == null
                                ? c.setupState?.outcomeUncertain != true
                                : c.setupState?.operation?.coreSucceeded ==
                                          true &&
                                      (fileStatus ==
                                              YorksV1ProjectSetupFileStatus
                                                  .selected ||
                                          fileStatus ==
                                              YorksV1ProjectSetupFileStatus
                                                  .needsReselect);
                            final cells = <Widget>[
                              Row(
                                children: [
                                  _DesktopFileIcon(fileName: file.fileName),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.fileName,
                                          style: YorksProjectSetupDesktopTheme
                                              .body
                                              .copyWith(fontSize: 13),
                                        ),
                                        if (file.sizeBytes != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            _formatAttachmentSize(
                                              file.sizeBytes!,
                                            ),
                                            style: YorksProjectSetupDesktopTheme
                                                .small,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              _AttachmentCategoryPicker(
                                key: ValueKey(
                                  'yorks-v1-desktop-file-category-$identity',
                                ),
                                attachment: file,
                                language: language,
                                onChanged:
                                    manifest == null &&
                                        c.setupState?.outcomeUncertain != true
                                    ? (category) =>
                                          c.onChangeCategory(index, category)
                                    : null,
                              ),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: OutlinedButton.icon(
                                  key: ValueKey(
                                    'yorks-v1-desktop-file-preview-$identity',
                                  ),
                                  onPressed: pendingBytes == null
                                      ? c.onAddAttachment
                                      : () => c.onPreviewAttachment(file),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(44, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                  icon: Icon(
                                    pendingBytes == null
                                        ? Icons.attach_file
                                        : Icons.visibility_outlined,
                                    size: 17,
                                  ),
                                  label: Text(
                                    (pendingBytes == null
                                            ? YorksV1ProjectStrings.fileReselect
                                            : YorksV1ProjectSetupDesktopStrings
                                                  .preview)
                                        .active(language),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Icon(
                                    ready
                                        ? Icons.check_circle
                                        : failed || needsReselect
                                        ? Icons.info_outline
                                        : Icons.schedule,
                                    size: 18,
                                    color: ready
                                        ? YorksProjectSetupDesktopTheme.success
                                        : failed || needsReselect
                                        ? AppColors.warning
                                        : YorksProjectSetupDesktopTheme.blue,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      status.active(language),
                                      style: YorksProjectSetupDesktopTheme.body
                                          .copyWith(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ];
                            return Container(
                              key: ValueKey('yorks-v1-desktop-file-$identity'),
                              constraints: const BoxConstraints(minHeight: 57),
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: YorksProjectSetupDesktopTheme.border,
                                  ),
                                ),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    for (
                                      var column = 0;
                                      column < cells.length;
                                      column++
                                    )
                                      Expanded(
                                        flex: const [34, 20, 17, 22][column],
                                        child: Container(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: column == 1 ? 4 : 18,
                                            vertical: 9,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: BorderDirectional(
                                              end: BorderSide(
                                                color:
                                                    YorksProjectSetupDesktopTheme
                                                        .border,
                                              ),
                                            ),
                                          ),
                                          child: cells[column],
                                        ),
                                      ),
                                    Expanded(
                                      flex: 7,
                                      child: PopupMenuButton<String>(
                                        key: ValueKey(
                                          'yorks-v1-desktop-file-menu-$identity',
                                        ),
                                        tooltip: YorksV1ProjectStrings.manage
                                            .active(language),
                                        icon: const Icon(
                                          Icons.more_vert,
                                          size: 20,
                                        ),
                                        itemBuilder: (_) => [
                                          if (needsReselect)
                                            PopupMenuItem(
                                              value: 'reselect',
                                              child: Text(
                                                YorksV1ProjectStrings
                                                    .fileReselect
                                                    .active(language),
                                              ),
                                            ),
                                          if (failed &&
                                              c.onRetryFile != null &&
                                              manifest != null)
                                            PopupMenuItem(
                                              value: 'retry',
                                              child: Text(
                                                YorksV1ProjectStrings.retryFile
                                                    .active(language),
                                              ),
                                            ),
                                          if (pendingBytes != null)
                                            PopupMenuItem(
                                              value: 'preview',
                                              child: Text(
                                                YorksV1ProjectSetupDesktopStrings
                                                    .preview
                                                    .active(language),
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'remove',
                                            enabled: canRemove,
                                            child: Text(
                                              YorksV1ProjectStrings.remove
                                                  .active(language),
                                            ),
                                          ),
                                        ],
                                        onSelected: (action) {
                                          switch (action) {
                                            case 'reselect':
                                              c.onAddAttachment();
                                            case 'retry':
                                              if (manifest != null) {
                                                c.onRetryFile?.call(manifest);
                                              }
                                            case 'preview':
                                              c.onPreviewAttachment(file);
                                            case 'remove':
                                              c.onRemoveAttachment(index);
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 34),
                          child: Text(
                            YorksV1ProjectStrings.noAttachmentsAdded.active(
                              language,
                            ),
                            style: YorksProjectSetupDesktopTheme.small,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                YorksV1ProjectStrings.operationalFilesOnly.active(language),
                style: YorksProjectSetupDesktopTheme.small,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopFileIcon extends StatelessWidget {
  const _DesktopFileIcon({required this.fileName});
  final String fileName;
  @override
  Widget build(BuildContext context) {
    final extension = fileName.split('.').last.toUpperCase();
    final color = switch (extension) {
      'PDF' => const Color(0xFFE5252B),
      'XLSX' => const Color(0xFF008A45),
      'DOCX' => YorksProjectSetupDesktopTheme.blue,
      _ => const Color(0xFF8295AE),
    };
    return Container(
      width: 23,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.center,
      child: Text(
        extension.length <= 4 ? extension : '',
        style: YorksProjectSetupDesktopTheme.small.copyWith(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DesktopDropzoneContents extends StatelessWidget {
  const _DesktopDropzoneContents({
    required this.language,
    required this.onPick,
    required this.dragging,
  });
  final AppLanguage language;
  final VoidCallback onPick;
  final bool dragging;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 233,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.description_outlined,
          size: 42,
          color: YorksProjectSetupDesktopTheme.muted,
        ),
        const SizedBox(height: 12),
        Text(
          (dragging
                  ? YorksV1ProjectStrings.attachmentsDropzoneActive
                  : YorksV1ProjectSetupDesktopStrings.dropFilesHere)
              .active(language),
          style: YorksProjectSetupDesktopTheme.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          YorksV1ProjectSetupDesktopStrings.browseDevice.active(language),
          style: YorksProjectSetupDesktopTheme.body.copyWith(
            color: YorksProjectSetupDesktopTheme.muted,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _ProjectSetupReadOnlyScope.of(context) ? null : onPick,
          style: YorksProjectSetupDesktopTheme.blueButton,
          child: Text(YorksV1ProjectStrings.addAttachment.active(language)),
        ),
        const SizedBox(height: 10),
        Text(
          YorksV1ProjectSetupDesktopStrings.desktopFileTypes.active(language),
          style: YorksProjectSetupDesktopTheme.small,
        ),
      ],
    ),
  );
}

class _DesktopReviewStage extends StatelessWidget {
  const _DesktopReviewStage(this.config);
  final _ReviewStage config;

  @override
  Widget build(BuildContext context) {
    final c = config;
    final draft = c.draft;
    final language = c.language;
    String text(String? value) => _emptyToNull(value) ?? '—';
    String date(DateTime? value) => value == null ? '—' : _typedDateText(value);
    final errors = draft.toCreationInput().validate();
    final byId = {
      for (final member
          in c.teamDirectory.asData?.value ??
              <YorksV1ProjectTeamDirectoryMember>[])
        member.authUserId: member,
    };
    final autoRole = _creatorProjectRole(c.creatorRole);
    final willBeActive =
        draft.initialMembers.any(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        ) ||
        autoRole == YorksV1ProjectMembershipRole.projectEngineer;
    final automatic = _automaticCreatorMembershipText(c.creatorRole, language);
    final team = c.editItem != null
        ? YorksV1ProjectStrings.accessAppliedSeparately.active(language)
        : [
            for (final role in [
              YorksV1ProjectMembershipRole.projectEngineer,
              YorksV1ProjectMembershipRole.siteEngineer,
            ])
              if (autoRole == role ||
                  draft.initialMembers.any(
                    (member) => member.projectRole == role,
                  ))
                '${(role == YorksV1ProjectMembershipRole.projectEngineer ? YorksV1ProjectStrings.projectEngineers : YorksV1ProjectStrings.siteEngineers).active(language)}: ${[if (autoRole == role) YorksV1ProjectStrings.you.active(language), for (final member in draft.initialMembers)
                  if (member.projectRole == role && (member.authUserId != c.creatorAuthUserId || role != autoRole)) _safeMemberDisplayName(byId[member.authUserId])].join(', ')}',
          ].join(' · ');
    bool fileBytesAvailable(YorksV1ProjectAttachmentInput attachment) =>
        attachment.contentHash != null &&
        c.pendingFiles.any(
          (file) =>
              file.fileName == attachment.fileName &&
              file.mimeType == attachment.mimeType &&
              file.bytes.length == attachment.sizeBytes &&
              sha256.convert(file.bytes).toString() == attachment.contentHash,
        );
    final invalidRawDate = ['dateStartText', 'dateEndText'].any((key) {
      final value = (draft.rawEditorState[key] as String? ?? '').trim();
      return value.isNotEmpty && _parseTypedDate(value) == null;
    });
    final unappliedEditor =
        [
          'buildingName',
          'buildingCode',
          'buildingFloors',
          'buildingAddress',
          'subcontractorText',
          'otherContractorText',
        ].any(
          (key) =>
              (draft.rawEditorState[key] as String? ?? '').trim().isNotEmpty,
        ) ||
        draft.rawEditorState['buildingFrp'] == true;
    final teamVerified =
        c.editItem != null ||
        draft.initialMembers.isEmpty ||
        (c.teamDirectory.asData != null &&
            !_hasUnavailableInitialMember(
              draft,
              c.teamDirectory.asData!.value,
            ));
    final ready =
        teamVerified &&
        errors.isEmpty &&
        c.validationErrors.isEmpty &&
        !invalidRawDate &&
        !unappliedEditor;

    Widget sheet(
      YorksV1ProjectCreationStage stage,
      Widget child,
    ) => _DesktopPanel(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
      minHeight: switch (stage) {
        YorksV1ProjectCreationStage.projectDetails => 181,
        YorksV1ProjectCreationStage.partiesAndAccess => 164,
        YorksV1ProjectCreationStage.buildings => 162,
        YorksV1ProjectCreationStage.attachments => 142,
        YorksV1ProjectCreationStage.reviewAndCreate => 0,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _stageCopy(stage).active(language),
                  style: YorksProjectSetupDesktopTheme.section.copyWith(
                    fontSize: 18,
                  ),
                ),
              ),
              Semantics(
                label: switch (stage) {
                  YorksV1ProjectCreationStage.projectDetails =>
                    YorksV1ProjectStrings.editProjectDetails.active(language),
                  YorksV1ProjectCreationStage.partiesAndAccess =>
                    YorksV1ProjectStrings.editPartiesAccess.active(language),
                  YorksV1ProjectCreationStage.buildings =>
                    YorksV1ProjectStrings.editBuildings.active(language),
                  YorksV1ProjectCreationStage.attachments =>
                    YorksV1ProjectStrings.editAttachments.active(language),
                  YorksV1ProjectCreationStage.reviewAndCreate =>
                    YorksV1ProjectStrings.edit.active(language),
                },
                button: true,
                onTap: () => c.onEdit(stage),
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: () => c.onEdit(stage),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  style: TextButton.styleFrom(
                    foregroundColor: YorksProjectSetupDesktopTheme.blue,
                    textStyle: YorksProjectSetupDesktopTheme.label,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(62, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  label: Text(YorksV1ProjectStrings.edit.active(language)),
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
    Widget summary(List<(TranslatableString, String)> rows) => Column(
      children: [
        for (final row in rows)
          Container(
            constraints: const BoxConstraints(minHeight: 22),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: YorksProjectSetupDesktopTheme.border),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 208,
                  child: Text(
                    row.$1.active(language),
                    style: YorksProjectSetupDesktopTheme.small,
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: YorksProjectSetupDesktopTheme.body.copyWith(
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    Widget table(
      List<String> headers,
      List<List<Widget>> rows,
      List<int> flex,
    ) => Container(
      decoration: BoxDecoration(
        border: Border.all(color: YorksProjectSetupDesktopTheme.border),
      ),
      child: Column(
        children: [
          _DesktopTableHeader(cells: headers, flex: flex, height: 28),
          for (final row in rows)
            IntrinsicHeight(
              child: Row(
                children: [
                  for (var index = 0; index < row.length; index++)
                    Expanded(
                      flex: flex[index],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(minHeight: 22),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: YorksProjectSetupDesktopTheme.border,
                            ),
                            right: BorderSide(
                              color: YorksProjectSetupDesktopTheme.border,
                            ),
                          ),
                        ),
                        child: row[index],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    Widget cell(String value) => Text(
      value,
      style: YorksProjectSetupDesktopTheme.body.copyWith(fontSize: 12),
    );
    final stageComplete = <YorksV1ProjectCreationStage, bool>{
      YorksV1ProjectCreationStage.projectDetails:
          !invalidRawDate &&
          !errors.any(
            (error) => {
              YorksV1ProjectValidationCode.missingProjectReference,
              YorksV1ProjectValidationCode.missingProjectName,
              YorksV1ProjectValidationCode.invalidDateRange,
            }.contains(error),
          ),
      YorksV1ProjectCreationStage.partiesAndAccess:
          teamVerified &&
          !errors.any(
            (error) => {
              YorksV1ProjectValidationCode.invalidProjectParty,
              YorksV1ProjectValidationCode.duplicateProjectParty,
              YorksV1ProjectValidationCode.missingMemberAuthUserId,
              YorksV1ProjectValidationCode.duplicateMember,
            }.contains(error),
          ),
      YorksV1ProjectCreationStage.buildings:
          draft.buildings.isNotEmpty &&
          !errors.any(
            (error) => {
              YorksV1ProjectValidationCode.missingBuilding,
              YorksV1ProjectValidationCode.invalidBuilding,
              YorksV1ProjectValidationCode.duplicateBuildingCode,
            }.contains(error),
          ),
      YorksV1ProjectCreationStage.attachments: !errors.contains(
        YorksV1ProjectValidationCode.invalidAttachment,
      ),
    };
    final allComplete = stageComplete.values.every((value) => value) && ready;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 744,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                constraints: const BoxConstraints(minHeight: 65),
                decoration: BoxDecoration(
                  color: ready
                      ? const Color(0xFFE6F4EF)
                      : YorksProjectSetupDesktopTheme.help,
                  border: Border.all(
                    color: ready
                        ? const Color(0xFFD0EAE1)
                        : YorksProjectSetupDesktopTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Icon(
                      ready ? Icons.check_circle : Icons.info_outline,
                      size: 29,
                      color: ready
                          ? YorksProjectSetupDesktopTheme.success
                          : YorksProjectSetupDesktopTheme.blue,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (ready
                                    ? YorksV1ProjectStrings
                                          .readyToCreateWorkspace
                                    : YorksV1ProjectStrings.stageNeedsAttention)
                                .active(language),
                            style: YorksProjectSetupDesktopTheme.label.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            YorksV1ProjectStrings.materialsNotRequiredAtCreation
                                .active(language),
                            style: YorksProjectSetupDesktopTheme.small,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              sheet(
                YorksV1ProjectCreationStage.projectDetails,
                summary([
                  (YorksV1ProjectStrings.yorksReference, draft.reference),
                  (YorksV1ProjectStrings.projectName, draft.name),
                  (
                    YorksV1ProjectStrings.jobOrContractReference,
                    text(draft.jobOrContractReference),
                  ),
                  (
                    YorksV1ProjectStrings.siteLocation,
                    text(draft.siteLocation),
                  ),
                  (
                    YorksV1ProjectSetupDesktopStrings.projectDates,
                    '${YorksV1ProjectStrings.startDate.active(language)}: ${date(draft.startDate)} · ${YorksV1ProjectStrings.endDate.active(language)}: ${date(draft.endDate)}',
                  ),
                  (YorksV1ProjectStrings.notes, text(draft.notes)),
                  if (_emptyToNull(draft.clientContactName) != null)
                    (
                      YorksV1ProjectStrings.contactName,
                      draft.clientContactName!,
                    ),
                  if (_emptyToNull(draft.clientContactPhone) != null)
                    (
                      YorksV1ProjectStrings.contactPhone,
                      draft.clientContactPhone!,
                    ),
                  if (_emptyToNull(draft.clientContactEmail) != null)
                    (
                      YorksV1ProjectStrings.contactEmail,
                      draft.clientContactEmail!,
                    ),
                  if (_emptyToNull(draft.clientAddress) != null)
                    (
                      YorksV1ProjectStrings.contactAddress,
                      draft.clientAddress!,
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              sheet(
                YorksV1ProjectCreationStage.partiesAndAccess,
                summary([
                  (YorksV1ProjectStrings.client, text(draft.clientName)),
                  for (final kind in [
                    YorksV1ProjectPartyKind.mainContractor,
                    YorksV1ProjectPartyKind.consultant,
                    YorksV1ProjectPartyKind.subcontractor,
                    YorksV1ProjectPartyKind.otherContractor,
                  ])
                    if (draft.parties.any((party) => party.kind == kind))
                      (
                        _partyKindCopy(kind),
                        text(
                          draft.parties
                              .where((party) => party.kind == kind)
                              .map((party) => party.name)
                              .join(', '),
                        ),
                      ),
                  (
                    YorksV1ProjectStrings.projectTeam,
                    team.isEmpty
                        ? YorksV1ProjectStrings.notProvided.active(language)
                        : team,
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              sheet(
                YorksV1ProjectCreationStage.buildings,
                table(
                  [
                    YorksV1ProjectSetupDesktopStrings.code.active(language),
                    YorksV1ProjectStrings.buildingName.active(language),
                    YorksV1ProjectSetupDesktopStrings.levels.active(language),
                    YorksV1ProjectSetupDesktopStrings.frp.active(language),
                  ],
                  [
                    for (final building in draft.buildings)
                      [
                        cell(text(building.code)),
                        cell(building.name),
                        cell(
                          building.floorsOrLevels.isEmpty
                              ? '—'
                              : building.floorsOrLevels.join(', '),
                        ),
                        cell(
                          (building.hasFrpRoom
                                  ? YorksV1ProjectSetupDesktopStrings.yes
                                  : YorksV1ProjectSetupDesktopStrings.no)
                              .active(language),
                        ),
                      ],
                  ],
                  const [19, 30, 31, 20],
                ),
              ),
              const SizedBox(height: 12),
              sheet(
                YorksV1ProjectCreationStage.attachments,
                draft.attachments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          YorksV1ProjectSetupDesktopStrings.optionalSkipped
                              .active(language),
                          style: YorksProjectSetupDesktopTheme.small,
                        ),
                      )
                    : table(
                        [
                          YorksV1ProjectSetupDesktopStrings.name.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.fileType.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.fileSize.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.category.active(
                            language,
                          ),
                          YorksV1ProjectSetupDesktopStrings.status.active(
                            language,
                          ),
                        ],
                        [
                          for (final file in draft.attachments)
                            [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.description_outlined,
                                    size: 16,
                                    color: YorksProjectSetupDesktopTheme.blue,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: cell(file.fileName)),
                                ],
                              ),
                              cell(file.fileName.split('.').last.toUpperCase()),
                              cell(
                                file.sizeBytes == null
                                    ? '—'
                                    : _formatAttachmentSize(file.sizeBytes!),
                              ),
                              cell(
                                _attachmentCategoryLabel(
                                  file.category,
                                ).active(language),
                              ),
                              cell(
                                (fileBytesAvailable(file)
                                        ? YorksV1ProjectSetupDesktopStrings
                                              .selectedLocally
                                        : YorksV1ProjectStrings.fileReselect)
                                    .active(language),
                              ),
                            ],
                        ],
                        const [35, 12, 13, 22, 18],
                      ),
              ),
              if (c.editItem != null) ...[
                const SizedBox(height: 12),
                _EditProposalComparison(draft: draft, language: language),
              ],
              if (c.teamDirectory.hasError &&
                  draft.initialMembers.isNotEmpty &&
                  c.editItem == null) ...[
                const SizedBox(height: 12),
                Text(
                  YorksV1ProjectStrings.teamDirectoryUnavailable.active(
                    language,
                  ),
                  style: YorksProjectSetupDesktopTheme.small.copyWith(
                    color: AppColors.error,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: c.onRetryDirectory,
                    child: Text(YorksV1ProjectStrings.retry.active(language)),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          flex: 256,
          child: Container(
            constraints: const BoxConstraints(minHeight: 740),
            padding: const EdgeInsetsDirectional.only(start: 25, top: 8),
            decoration: const BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: YorksProjectSetupDesktopTheme.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (allComplete
                          ? YorksV1ProjectSetupDesktopStrings
                                .allSelectionsComplete
                          : YorksV1ProjectStrings.stageNeedsAttention)
                      .active(language),
                  style: YorksProjectSetupDesktopTheme.section.copyWith(
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  YorksV1ProjectSetupDesktopStrings.reviewContinueHelp.active(
                    language,
                  ),
                  style: YorksProjectSetupDesktopTheme.body.copyWith(
                    color: YorksProjectSetupDesktopTheme.muted,
                  ),
                ),
                const SizedBox(height: 20),
                for (final stage in stageComplete.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          stageComplete[stage]!
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: stageComplete[stage]!
                              ? YorksProjectSetupDesktopTheme.success
                              : AppColors.warning,
                          size: 27,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _stageCopy(stage).active(language),
                                style: YorksProjectSetupDesktopTheme.body
                                    .copyWith(fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (stage ==
                                                YorksV1ProjectCreationStage
                                                    .attachments &&
                                            draft.attachments.isEmpty
                                        ? YorksV1ProjectSetupDesktopStrings
                                              .optionalSkipped
                                        : stageComplete[stage]!
                                        ? YorksV1ProjectSetupDesktopStrings
                                              .complete
                                        : YorksV1ProjectStrings
                                              .stageNeedsAttention)
                                    .active(language),
                                style: YorksProjectSetupDesktopTheme.small,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (c.editItem == null)
                  Text(
                    (willBeActive
                            ? YorksV1ProjectStrings.expectedActiveProject
                            : YorksV1ProjectStrings.expectedDraftProject)
                        .active(language),
                    style: YorksProjectSetupDesktopTheme.small,
                  ),
                if (c.editItem == null && automatic != null) ...[
                  const SizedBox(height: 8),
                  Text(automatic, style: YorksProjectSetupDesktopTheme.small),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
