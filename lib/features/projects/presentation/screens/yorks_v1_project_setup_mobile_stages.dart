part of 'yorks_v1_project_create_flow_screen.dart';

class _MobileSetupCard extends StatelessWidget {
  const _MobileSetupCard({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: YorksProjectSetupMobileTheme.border),
      borderRadius: BorderRadius.circular(7),
    ),
    child: child,
  );
}

class _MobileSetupHeading extends StatelessWidget {
  const _MobileSetupHeading({
    required this.title,
    required this.language,
    this.description,
    this.icon,
    this.action,
  });
  final TranslatableString title;
  final AppLanguage language;
  final TranslatableString? description;
  final IconData? icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: YorksProjectSetupMobileTheme.selected,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                icon,
                size: 22,
                color: YorksProjectSetupMobileTheme.blue,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title.active(language),
              style: YorksProjectSetupMobileTheme.title,
            ),
          ),
          if (action != null) ...[const SizedBox(width: 6), action!],
        ],
      ),
      if (description != null) ...[
        const SizedBox(height: 5),
        Text(
          description!.active(language),
          style: YorksProjectSetupMobileTheme.small.copyWith(fontSize: 13),
        ),
      ],
    ],
  );
}

class _MobileSetupField extends StatelessWidget {
  const _MobileSetupField({
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
    this.errorText,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.horizontalPadding = 10,
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
  final String? errorText;
  final int maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final double horizontalPadding;
  @override
  Widget build(BuildContext context) => Column(
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
                  color: YorksProjectSetupMobileTheme.muted,
                ),
              ),
          ],
        ),
        style: YorksProjectSetupMobileTheme.label.copyWith(fontSize: 12.5),
      ),
      const SizedBox(height: 6),
      Semantics(
        label: label.active(language),
        child: TextFormField(
          readOnly: _ProjectSetupReadOnlyScope.of(context),
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          style: YorksProjectSetupMobileTheme.body,
          decoration:
              YorksProjectSetupMobileTheme.inputDecoration(
                hint: hint?.active(language),
                prefix: prefix,
                suffix: suffix,
              ).copyWith(
                constraints: maxLines == 1
                    ? const BoxConstraints(minHeight: 44)
                    : null,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 10,
                ),
                errorText: errorText,
              ),
        ),
      ),
      if (helper != null) ...[
        const SizedBox(height: 5),
        Text(
          helper!.active(language),
          style: YorksProjectSetupMobileTheme.small,
        ),
      ],
    ],
  );
}

class _MobileFieldPair extends StatelessWidget {
  const _MobileFieldPair({
    required this.first,
    required this.second,
    this.minimumWidth = 340,
  });
  final Widget first;
  final Widget second;
  final double minimumWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (YorksProjectSetupMobileTheme.showColumns(
            context,
            constraints.maxWidth,
          ) &&
          constraints.maxWidth >= minimumWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 16), second],
      );
    },
  );
}

class _MobileDetailsStage extends StatelessWidget {
  const _MobileDetailsStage(this.config);
  final _DetailsStage config;
  @override
  Widget build(BuildContext context) {
    final c = config;
    final language = c.language;
    String? required(String? value) => value == null || value.trim().isEmpty
        ? YorksV1ProjectStrings.requiredField.active(language)
        : null;
    Widget date(bool start) => _MobileSetupDateField(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileSetupCard(
          child: Form(
            key: c.formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileSetupHeading(
                  title: YorksV1ProjectStrings.projectDetails,
                  language: language,
                  description: YorksV1ProjectSetupDesktopStrings.detailsHelp,
                ),
                const SizedBox(height: 16),
                _MobileSetupField(
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
                const SizedBox(height: 16),
                _MobileSetupField(
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
                const SizedBox(height: 16),
                _MobileFieldPair(
                  first: _MobileSetupField(
                    key: const ValueKey('yorks-v1-project-client'),
                    label: YorksV1ProjectStrings.client,
                    language: language,
                    controller: c.clientController,
                    focusNode: c.focusNodes['client'],
                    optional: true,
                    hint: YorksV1ProjectStrings.clientHint,
                    onChanged: c.onClientChanged,
                  ),
                  second: _MobileSetupField(
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
                    onPressed: () => c.onContactsExpanded(!c.contactsExpanded),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      YorksV1ProjectStrings.optionalContacts.active(language),
                      style: YorksProjectSetupMobileTheme.small.copyWith(
                        color: YorksProjectSetupMobileTheme.blue,
                      ),
                    ),
                  ),
                ),
                if (c.contactsExpanded) ...[
                  _MobileFieldPair(
                    first: _MobileSetupField(
                      label: YorksV1ProjectStrings.contactName,
                      language: language,
                      controller: c.contactNameController,
                      focusNode: c.focusNodes['contactName'],
                      onChanged: c.onContactChanged,
                    ),
                    second: _MobileSetupField(
                      label: YorksV1ProjectStrings.contactPhone,
                      language: language,
                      controller: c.contactPhoneController,
                      focusNode: c.focusNodes['contactPhone'],
                      keyboardType: TextInputType.phone,
                      onChanged: c.onContactChanged,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MobileFieldPair(
                    first: _MobileSetupField(
                      label: YorksV1ProjectStrings.contactEmail,
                      language: language,
                      controller: c.contactEmailController,
                      focusNode: c.focusNodes['contactEmail'],
                      keyboardType: TextInputType.emailAddress,
                      onChanged: c.onContactChanged,
                    ),
                    second: _MobileSetupField(
                      label: YorksV1ProjectStrings.contactAddress,
                      language: language,
                      controller: c.contactAddressController,
                      focusNode: c.focusNodes['contactAddress'],
                      onChanged: c.onContactChanged,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _MobileSetupField(
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
                const SizedBox(height: 16),
                _MobileFieldPair(
                  first: date(true),
                  second: date(false),
                  minimumWidth: 360,
                ),
                const SizedBox(height: 16),
                _MobileSetupField(
                  key: const ValueKey('yorks-v1-project-notes'),
                  label: YorksV1ProjectStrings.notes,
                  language: language,
                  controller: c.notesController,
                  focusNode: c.focusNodes['notes'],
                  optional: true,
                  hint: YorksV1ProjectStrings.notesHint,
                  helper: YorksV1ProjectSetupDesktopStrings.notesHelp,
                  maxLines: 3,
                  onChanged: c.onNotesChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileSetupDateField extends StatelessWidget {
  const _MobileSetupDateField({
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
      _MobileSetupField(
        key: ValueKey('yorks-v1-project-date-${copy.en}'),
        label: copy,
        language: language,
        controller: controller,
        focusNode: focusNode,
        optional: true,
        hint: YorksV1ProjectStrings.dateInputHint,
        horizontalPadding: 0,
        keyboardType: TextInputType.datetime,
        prefix: IconButton(
          onPressed: _ProjectSetupReadOnlyScope.of(context) ? null : onPick,
          tooltip: YorksV1ProjectStrings.selectDate.active(language),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.calendar_month_outlined, size: 19),
        ),
        suffix: IconButton(
          onPressed: _ProjectSetupReadOnlyScope.of(context)
              ? null
              : controller.clear,
          tooltip: YorksV1ProjectSetupDesktopStrings.clearDate.active(language),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, size: 18),
        ),
        validator: (value) =>
            value == null ||
                value.trim().isEmpty ||
                _parseTypedDate(value) != null
            ? null
            : YorksV1ProjectStrings.invalidTypedDate.active(language),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              error ??
                  YorksV1ProjectStrings.typedDateFormatHelp.active(language),
              style: YorksProjectSetupMobileTheme.small.copyWith(
                color: error == null
                    ? YorksProjectSetupMobileTheme.muted
                    : AppColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: _ProjectSetupReadOnlyScope.of(context) ? null : onToday,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            child: Text(
              YorksV1ProjectStrings.today.active(language),
              style: YorksProjectSetupMobileTheme.small.copyWith(
                color: YorksProjectSetupMobileTheme.blue,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _MobilePartiesStage extends StatelessWidget {
  const _MobilePartiesStage(this.config);
  final _PartiesAndAccessStage config;
  @override
  Widget build(BuildContext context) {
    final c = config;
    final language = c.language;
    Widget named(
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
              child: _MobileSetupField(
                key: ValueKey(
                  kind == YorksV1ProjectPartyKind.subcontractor
                      ? 'yorks-v1-project-subcontractors'
                      : 'yorks-v1-project-other-contractors',
                ),
                label: copy,
                language: language,
                controller: controller,
                focusNode: c.focusNodes[focusKey],
                optional: true,
                hint: copy,
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: add,
              style: YorksProjectSetupMobileTheme.outlineButton.copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                foregroundColor: const WidgetStatePropertyAll(
                  YorksProjectSetupMobileTheme.blue,
                ),
              ),
              child: Text(YorksV1ProjectStrings.add.active(language)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var index = 0; index < c.draft.parties.length; index++)
              if (c.draft.parties[index].kind == kind)
                Container(
                  key: ValueKey(
                    'yorks-v1-party-${c.draft.parties[index].retainedFields['local_row_id'] ?? '${kind.name}-$index'}',
                  ),
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  decoration: BoxDecoration(
                    color: YorksProjectSetupMobileTheme.help,
                    border: Border.all(
                      color: YorksProjectSetupMobileTheme.border,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          c.draft.parties[index].name,
                          style: YorksProjectSetupMobileTheme.small.copyWith(
                            color: YorksProjectSetupMobileTheme.navy,
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey(
                          'yorks-v1-mobile-party-remove-${c.draft.parties[index].retainedFields['local_row_id'] ?? '${kind.name}-$index'}',
                        ),
                        onPressed: () => c.onRemoveParty(index),
                        tooltip:
                            '${YorksV1ProjectStrings.remove.active(language)} ${c.draft.parties[index].name}',
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ],
    );
    return _MobileSetupCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileSetupHeading(
            title: YorksV1ProjectStrings.partiesAndAccess,
            language: language,
            description: YorksV1ProjectSetupDesktopStrings.partiesHelp,
          ),
          const SizedBox(height: 12),
          _MobileSetupCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileSetupHeading(
                  title: YorksV1ProjectSetupDesktopStrings.projectParties,
                  language: language,
                  description:
                      YorksV1ProjectSetupDesktopStrings.partiesOptionalHelp,
                ),
                const SizedBox(height: 12),
                _MobileFieldPair(
                  first: _MobileSetupField(
                    key: const ValueKey('yorks-v1-project-consultant'),
                    label: YorksV1ProjectStrings.consultant,
                    language: language,
                    controller: c.consultantController,
                    focusNode: c.focusNodes['consultant'],
                    optional: true,
                    hint: YorksV1ProjectStrings.consultant,
                    prefix: const Icon(Icons.search, size: 18),
                    onChanged: c.onConsultantChanged,
                  ),
                  second: _MobileSetupField(
                    key: const ValueKey('yorks-v1-project-main-contractor'),
                    label: YorksV1ProjectStrings.mainContractor,
                    language: language,
                    controller: c.mainContractorController,
                    focusNode: c.focusNodes['mainContractor'],
                    optional: true,
                    hint: YorksV1ProjectStrings.mainContractor,
                    prefix: const Icon(Icons.search, size: 18),
                    onChanged: c.onMainContractorChanged,
                  ),
                ),
                const SizedBox(height: 14),
                _MobileFieldPair(
                  first: named(
                    YorksV1ProjectPartyKind.subcontractor,
                    YorksV1ProjectStrings.subcontractors,
                    c.subcontractorController,
                    'subcontractor',
                    c.onAddSubcontractor,
                  ),
                  second: named(
                    YorksV1ProjectPartyKind.otherContractor,
                    YorksV1ProjectStrings.otherContractors,
                    c.otherContractorController,
                    'otherContractor',
                    c.onAddOtherContractor,
                  ),
                ),
                if (c.onUndoPartyRemoval != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: c.onUndoPartyRemoval,
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(
                        YorksV1ProjectStrings.undoPartyRemoval.active(language),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _MobileSetupCard(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileSetupHeading(
                  title: YorksV1ProjectSetupDesktopStrings.projectTeamAccess,
                  language: language,
                  description: YorksV1ProjectSetupDesktopStrings.teamAccessHelp,
                ),
                const SizedBox(height: 10),
                if (!c.showTeam && c.editItem != null) ...[
                  for (final member in c.editItem!.activeMembers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${member.displayName ?? YorksV1ProjectStrings.profileId.active(language)} · ${YorksV1ProjectStrings.roleLabel(member.projectRole.wireValue).active(language)}',
                        style: YorksProjectSetupMobileTheme.body,
                      ),
                    ),
                  Text(
                    YorksV1ProjectStrings.accessAppliedSeparately.active(
                      language,
                    ),
                    style: YorksProjectSetupMobileTheme.small,
                  ),
                  TextButton.icon(
                    onPressed: c.onManageAccess,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(
                      YorksV1ProjectStrings.manageAccess.active(language),
                    ),
                  ),
                ] else
                  _MobileSetupTeamDirectory(c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSetupTeamDirectory extends StatefulWidget {
  const _MobileSetupTeamDirectory(this.config);
  final _PartiesAndAccessStage config;
  @override
  State<_MobileSetupTeamDirectory> createState() =>
      _MobileSetupTeamDirectoryState();
}

class _MobileSetupTeamDirectoryState extends State<_MobileSetupTeamDirectory> {
  String _query = '';
  YorksV1Role? _role;
  @override
  void didUpdateWidget(covariant _MobileSetupTeamDirectory oldWidget) {
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
    final directory = c.teamDirectory.asData?.value;
    final byId = {
      for (final member in directory ?? <YorksV1ProjectTeamDirectoryMember>[])
        member.authUserId: member,
    };
    final selectedIds = c.draft.initialMembers
        .map((member) => member.authUserId)
        .toSet();
    final autoRole = _creatorProjectRole(c.creatorRole);
    final siteCreator = c.creatorRole == YorksV1Role.siteEngineer;
    final hasPe = c.draft.initialMembers.any(
      (member) =>
          member.projectRole == YorksV1ProjectMembershipRole.projectEngineer,
    );
    final choices = directory
        ?.where(
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
    final selectedCount =
        c.draft.initialMembers
            .where(
              (member) =>
                  member.authUserId != c.creatorAuthUserId ||
                  member.projectRole != autoRole,
            )
            .length +
        (autoRole == null ? 0 : 1);
    Widget avatar(String name) => CircleAvatar(
      radius: 13,
      backgroundColor: YorksProjectSetupMobileTheme.selected,
      child: Text(
        name
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part.characters.first)
            .join()
            .toUpperCase(),
        style: YorksProjectSetupMobileTheme.small.copyWith(
          color: YorksProjectSetupMobileTheme.navy,
        ),
      ),
    );
    Widget person(
      String name,
      YorksV1ProjectMembershipRole role, {
      Widget? action,
      bool automatic = false,
    }) => Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: YorksProjectSetupMobileTheme.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar(name),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: YorksProjectSetupMobileTheme.body.copyWith(
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  YorksV1ProjectStrings.roleLabel(
                    role.wireValue,
                  ).active(language),
                  style: YorksProjectSetupMobileTheme.small,
                ),
                if (automatic)
                  Text(
                    YorksV1ProjectStrings.automaticCreatorMembership.active(
                      language,
                    ),
                    style: YorksProjectSetupMobileTheme.small,
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
    final available = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1ProjectSetupMobileStrings.availablePeople.active(language),
          style: YorksProjectSetupMobileTheme.label.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 250,
          child: c.teamDirectory.isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : c.teamDirectory.hasError
              ? _TeamDirectoryUnavailable(
                  draft: c.draft,
                  language: language,
                  onRemoveMember: c.onRemoveInitialMember,
                )
              : choices == null || choices.isEmpty
              ? Center(
                  child: Text(
                    YorksV1ProjectStrings.noTeamSearchResults.active(language),
                    style: YorksProjectSetupMobileTheme.small,
                  ),
                )
              : ListView.builder(
                  itemCount: choices.length,
                  itemBuilder: (context, index) {
                    final member = choices[index];
                    final role =
                        member.eligibleRole == YorksV1Role.projectEngineer
                        ? YorksV1ProjectMembershipRole.projectEngineer
                        : YorksV1ProjectMembershipRole.siteEngineer;
                    final enabled = !siteCreator || !hasPe;
                    return KeyedSubtree(
                      key: ValueKey(
                        'yorks-v1-mobile-directory-${member.authUserId}',
                      ),
                      child: person(
                        _safeMemberDisplayName(member),
                        role,
                        action: TextButton(
                          key: ValueKey(
                            'yorks-v1-mobile-directory-add-${member.authUserId}',
                          ),
                          onPressed: enabled
                              ? () => c.onAddInitialMember(member, role)
                              : null,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            YorksV1ProjectStrings.add.active(language),
                            style: YorksProjectSetupMobileTheme.small.copyWith(
                              color: enabled
                                  ? YorksProjectSetupMobileTheme.blue
                                  : AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    final selected = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1ProjectSetupMobileStrings.selectedTeam
              .active(language)
              .replaceFirst('{count}', '$selectedCount'),
          style: YorksProjectSetupMobileTheme.label.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 5),
        for (final role in [
          YorksV1ProjectMembershipRole.projectEngineer,
          YorksV1ProjectMembershipRole.siteEngineer,
        ])
          if (autoRole == role ||
              c.draft.initialMembers.any(
                (member) => member.projectRole == role,
              )) ...[
            Container(
              padding: const EdgeInsets.all(6),
              color: YorksProjectSetupMobileTheme.help,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(role == YorksV1ProjectMembershipRole.projectEngineer ? YorksV1ProjectStrings.projectEngineers : YorksV1ProjectStrings.siteEngineers).active(language)} (${c.draft.initialMembers.where((member) => member.projectRole == role && (member.authUserId != c.creatorAuthUserId || role != autoRole)).length + (autoRole == role ? 1 : 0)})',
                    style: YorksProjectSetupMobileTheme.label.copyWith(
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    (role == YorksV1ProjectMembershipRole.projectEngineer
                            ? YorksV1ProjectSetupDesktopStrings
                                  .projectEngineerAccessHelp
                            : YorksV1ProjectSetupDesktopStrings
                                  .siteEngineerAccessHelp)
                        .active(language),
                    style: YorksProjectSetupMobileTheme.small,
                  ),
                ],
              ),
            ),
            if (autoRole == role)
              person(
                YorksV1ProjectStrings.you.active(language),
                role,
                automatic: true,
              ),
            for (var index = 0; index < c.draft.initialMembers.length; index++)
              if (c.draft.initialMembers[index].projectRole == role &&
                  (c.draft.initialMembers[index].authUserId !=
                          c.creatorAuthUserId ||
                      role != autoRole))
                person(
                  _safeMemberDisplayName(
                    byId[c.draft.initialMembers[index].authUserId],
                  ),
                  role,
                  action: IconButton(
                    onPressed: () => c.onRemoveInitialMember(index),
                    tooltip: YorksV1ProjectStrings.remove.active(language),
                    icon: const Icon(Icons.close, size: 18),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
          ],
        if (selectedCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              YorksV1ProjectStrings.noActiveAssignments.active(language),
              style: YorksProjectSetupMobileTheme.small,
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: YorksProjectSetupMobileTheme.help,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: YorksProjectSetupMobileTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1ProjectSetupDesktopStrings.aboutAccessLevels.active(
                  language,
                ),
                style: YorksProjectSetupMobileTheme.label.copyWith(
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                (siteCreator
                        ? YorksV1ProjectStrings.initialProjectEngineerHint
                        : YorksV1ProjectStrings
                              .projectTeamPermissionDescription)
                    .active(language),
                style: YorksProjectSetupMobileTheme.small,
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      key: ValueKey(
        'mobile-team-directory-${c.draft.backendIdentity}-${c.draft.draftId}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                readOnly: _ProjectSetupReadOnlyScope.of(context),
                key: const ValueKey('yorks-v1-project-team-search'),
                style: YorksProjectSetupMobileTheme.body,
                decoration:
                    YorksProjectSetupMobileTheme.inputDecoration(
                      hint: YorksV1ProjectStrings.searchTeam.active(language),
                      prefix: const Icon(Icons.search, size: 20),
                    ).copyWith(
                      labelText: YorksV1ProjectStrings.searchTeam.active(
                        language,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      constraints: const BoxConstraints(minHeight: 44),
                    ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 112,
              child: DropdownButtonFormField<YorksV1Role?>(
                key: const ValueKey('yorks-v1-mobile-directory-role-filter'),
                initialValue: _role,
                isExpanded: true,
                style: YorksProjectSetupMobileTheme.small,
                decoration: YorksProjectSetupMobileTheme.inputDecoration()
                    .copyWith(constraints: const BoxConstraints(minHeight: 44)),
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
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) =>
              YorksProjectSetupMobileTheme.showColumns(
                context,
                constraints.maxWidth,
              )
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: available),
                    const SizedBox(width: 8),
                    Expanded(child: selected),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [selected, const SizedBox(height: 14), available],
                ),
        ),
      ],
    );
  }
}

class _MobileBuildingsStage extends StatefulWidget {
  const _MobileBuildingsStage(this.config);
  final _BuildingsStage config;
  @override
  State<_MobileBuildingsStage> createState() => _MobileBuildingsStageState();
}

class _MobileBuildingsStageState extends State<_MobileBuildingsStage> {
  String _query = '';
  @override
  void didUpdateWidget(covariant _MobileBuildingsStage oldWidget) {
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
    Widget menu(int index) {
      final building = c.draft.buildings[index];
      final identity =
          building.localRowId ?? building.sourceScopeId ?? '$index';
      final selected = c.editingBuildingIndex == index;
      return PopupMenuButton<String>(
        key: ValueKey('yorks-v1-mobile-building-menu-$identity'),
        tooltip: YorksV1ProjectStrings.manage.active(language),
        icon: const Icon(Icons.more_vert, size: 20),
        constraints: const BoxConstraints(minWidth: 180),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            enabled: !editorPending || selected,
            child: Text(YorksV1ProjectStrings.editBuilding.active(language)),
          ),
          PopupMenuItem(
            value: 'duplicate',
            enabled: !editorPending,
            child: Text(
              YorksV1ProjectStrings.addAnotherLikeThis.active(language),
            ),
          ),
          PopupMenuItem(
            value: 'up',
            enabled: !editorPending && index > 0,
            child: Text(YorksV1ProjectStrings.moveBuildingUp.active(language)),
          ),
          PopupMenuItem(
            value: 'down',
            enabled: !editorPending && index < c.draft.buildings.length - 1,
            child: Text(
              YorksV1ProjectStrings.moveBuildingDown.active(language),
            ),
          ),
          PopupMenuItem(
            value: 'remove',
            enabled: !editorPending && building.sourceScopeId == null,
            child: Text(
              (building.sourceScopeId == null
                      ? YorksV1ProjectStrings.remove
                      : YorksV1ProjectStrings.existingBuildingRetirementBlocked)
                  .active(language),
            ),
          ),
        ],
        onSelected: (action) {
          switch (action) {
            case 'edit':
              if (!selected) c.onEditBuilding(index);
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
      );
    }

    Widget field(
      TranslatableString copy,
      TextEditingController controller,
      String focus,
      String key, {
      bool required = false,
      TranslatableString? helper,
      int lines = 1,
    }) => _MobileSetupField(
      key: ValueKey(key),
      label: copy,
      language: language,
      controller: controller,
      focusNode: c.focusNodes[focus],
      required: required,
      optional: !required,
      helper: helper,
      maxLines: lines,
      errorText:
          required &&
              c.validationErrors.contains(
                YorksV1ProjectValidationCode.invalidBuilding,
              ) &&
              controller.text.trim().isEmpty
          ? YorksV1ProjectStrings.requiredField.active(language)
          : null,
    );
    Widget table(bool columns) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (columns)
          Container(
            color: YorksProjectSetupMobileTheme.help,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (var column = 0; column < 4; column++)
                  Expanded(
                    flex: const [18, 36, 26, 20][column],
                    child: Text(
                      [
                        YorksV1ProjectSetupDesktopStrings.code,
                        YorksV1ProjectStrings.buildingName,
                        YorksV1ProjectSetupDesktopStrings.levels,
                        YorksV1ProjectSetupDesktopStrings.frp,
                      ][column].active(language),
                      style: YorksProjectSetupMobileTheme.small.copyWith(
                        color: YorksProjectSetupMobileTheme.navy,
                      ),
                    ),
                  ),
                const SizedBox(width: 44),
              ],
            ),
          ),
        for (final index in rows)
          Builder(
            builder: (context) {
              final building = c.draft.buildings[index];
              final selected = c.editingBuildingIndex == index;
              final identity =
                  building.localRowId ?? building.sourceScopeId ?? '$index';
              final frp =
                  (building.hasFrpRoom
                          ? YorksV1ProjectSetupDesktopStrings.yes
                          : YorksV1ProjectSetupDesktopStrings.no)
                      .active(language);
              final cells = [
                building.code.isEmpty ? '—' : building.code,
                building.name,
                building.floorsOrLevels.isEmpty
                    ? '—'
                    : building.floorsOrLevels.join(', '),
                frp,
              ];
              return Material(
                key: ValueKey('yorks-v1-mobile-building-$identity'),
                color: selected
                    ? YorksProjectSetupMobileTheme.selected
                    : Colors.white,
                child: InkWell(
                  onTap: !selected && !editorPending
                      ? () => c.onEditBuilding(index)
                      : null,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: const BorderSide(
                          color: YorksProjectSetupMobileTheme.border,
                        ),
                        left: BorderSide(
                          width: 3,
                          color: selected
                              ? YorksProjectSetupMobileTheme.blue
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: columns
                        ? Row(
                            children: [
                              for (var column = 0; column < 4; column++)
                                Expanded(
                                  flex: const [18, 36, 26, 20][column],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 2,
                                    ),
                                    child: Text(
                                      cells[column],
                                      style: YorksProjectSetupMobileTheme.body
                                          .copyWith(fontSize: 12),
                                    ),
                                  ),
                                ),
                              menu(index),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        building.name,
                                        style:
                                            YorksProjectSetupMobileTheme.label,
                                      ),
                                      if (building.code.isNotEmpty)
                                        Text(
                                          building.code,
                                          style: YorksProjectSetupMobileTheme
                                              .small,
                                        ),
                                      if (building.floorsOrLevels.isNotEmpty)
                                        Text(
                                          '${YorksV1ProjectSetupDesktopStrings.levels.active(language)}: ${building.floorsOrLevels.join(', ')}',
                                          style: YorksProjectSetupMobileTheme
                                              .small,
                                        ),
                                      Text(
                                        '${YorksV1ProjectSetupDesktopStrings.frp.active(language)}: $frp',
                                        style:
                                            YorksProjectSetupMobileTheme.small,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              menu(index),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              YorksV1ProjectStrings.noBuildingsAdded.active(language),
              style: YorksProjectSetupMobileTheme.small,
            ),
          ),
      ],
    );
    return Column(
      key: ValueKey(
        'mobile-building-editor-${c.draft.backendIdentity}-${c.draft.draftId}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileSetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MobileSetupHeading(
                title: YorksV1ProjectStrings.buildings,
                language: language,
                description: YorksV1ProjectSetupDesktopStrings.buildingsHelp,
                icon: Icons.apartment,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    readOnly: _ProjectSetupReadOnlyScope.of(context),
                    key: const ValueKey('yorks-v1-mobile-building-search'),
                    style: YorksProjectSetupMobileTheme.body,
                    decoration:
                        YorksProjectSetupMobileTheme.inputDecoration(
                          hint: YorksV1ProjectSetupDesktopStrings.findBuilding
                              .active(language),
                          prefix: const Icon(Icons.search, size: 20),
                        ).copyWith(
                          labelText: YorksV1ProjectSetupDesktopStrings
                              .findBuilding
                              .active(language),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          constraints: const BoxConstraints(minHeight: 44),
                        ),
                    onChanged: (value) => setState(() => _query = value),
                  );
                  final add = OutlinedButton.icon(
                    key: const ValueKey('yorks-v1-mobile-add-building'),
                    onPressed: editorPending
                        ? null
                        : () {
                            c.onCancelEditing();
                            c.focusNodes['buildingName']?.requestFocus();
                          },
                    style: YorksProjectSetupMobileTheme.outlineButton,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(
                      YorksV1ProjectStrings.addBuilding.active(language),
                    ),
                  );
                  return YorksProjectSetupMobileTheme.showColumns(
                        context,
                        constraints.maxWidth,
                      )
                      ? Row(
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: 10),
                            add,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            search,
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: add,
                            ),
                          ],
                        );
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) => table(
                  YorksProjectSetupMobileTheme.showColumns(
                    context,
                    constraints.maxWidth,
                  ),
                ),
              ),
              if (c.onUndoRemove != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: c.onUndoRemove,
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(
                      YorksV1ProjectStrings.undoBuildingChange.active(language),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _MobileSetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MobileSetupHeading(
                title: c.editingBuildingIndex == null
                    ? YorksV1ProjectStrings.addBuilding
                    : YorksV1ProjectStrings.editBuilding,
                language: language,
              ),
              const SizedBox(height: 12),
              _MobileFieldPair(
                first: field(
                  YorksV1ProjectStrings.buildingName,
                  c.nameController,
                  'buildingName',
                  'yorks-v1-building-name',
                  required: true,
                ),
                second: field(
                  YorksV1ProjectStrings.buildingCode,
                  c.codeController,
                  'buildingCode',
                  'yorks-v1-building-code',
                  helper:
                      YorksV1ProjectSetupDesktopStrings.leaveBuildingCodeBlank,
                ),
              ),
              const SizedBox(height: 16),
              _MobileFieldPair(
                first: field(
                  YorksV1ProjectStrings.floorsOrLevels,
                  c.floorsController,
                  'buildingFloors',
                  'yorks-v1-building-floors',
                  helper: YorksV1ProjectStrings.levelsLabelsHint,
                ),
                second: field(
                  YorksV1ProjectStrings.deliveryAddress,
                  c.deliveryAddressController,
                  'buildingAddress',
                  'yorks-v1-building-delivery-address',
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  key: const ValueKey('yorks-v1-mobile-building-frp'),
                  value: c.hasFrpRoom,
                  onChanged: _ProjectSetupReadOnlyScope.of(context)
                      ? null
                      : (value) => c.onHasFrpRoomChanged(value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  visualDensity: VisualDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  activeColor: YorksProjectSetupMobileTheme.blue,
                  title: Text(
                    YorksV1ProjectStrings.hasFrpRoom.active(language),
                    style: YorksProjectSetupMobileTheme.body,
                  ),
                  subtitle: Text(
                    YorksV1ProjectSetupMobileStrings.frpRoomHelp.active(
                      language,
                    ),
                    style: YorksProjectSetupMobileTheme.small,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('yorks-v1-mobile-cancel-building'),
                    onPressed: c.onCancelEditing,
                    style: YorksProjectSetupMobileTheme.outlineButton,
                    child: Text(
                      YorksV1ProjectSetupDesktopStrings.cancelEdit.active(
                        language,
                      ),
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('yorks-v1-mobile-apply-building'),
                    onPressed: c.nameController.text.trim().isEmpty
                        ? null
                        : c.onAddBuilding,
                    style: YorksProjectSetupMobileTheme.navyButton,
                    child: Text(
                      (c.editingBuildingIndex == null
                              ? YorksV1ProjectStrings.addBuilding
                              : YorksV1ProjectSetupDesktopStrings.saveBuilding)
                          .active(language),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _MobileSetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MobileSetupHeading(
                title: YorksV1ProjectStrings.commonScope,
                language: language,
                description:
                    YorksV1ProjectSetupDesktopStrings.commonAddedAutomatically,
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 10),
              Text(
                YorksV1ProjectSetupDesktopStrings.notEditable.active(language),
                style: YorksProjectSetupMobileTheme.label,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: YorksProjectSetupMobileTheme.help,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 22,
                      color: YorksProjectSetupMobileTheme.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        YorksV1ProjectSetupMobileStrings.commonScopeHelp.active(
                          language,
                        ),
                        style: YorksProjectSetupMobileTheme.small,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileAttachmentsStage extends StatefulWidget {
  const _MobileAttachmentsStage(this.config);
  final _AttachmentsStage config;
  @override
  State<_MobileAttachmentsStage> createState() =>
      _MobileAttachmentsStageState();
}

class _MobileAttachmentsStageState extends State<_MobileAttachmentsStage> {
  String _query = '';
  String _category = 'all';
  @override
  void didUpdateWidget(covariant _MobileAttachmentsStage oldWidget) {
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
    return _MobileSetupCard(
      child: Column(
        key: ValueKey(
          'mobile-attachments-${c.draft.backendIdentity}-${c.draft.draftId}',
        ),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileSetupHeading(
            title: YorksV1ProjectStrings.attachments,
            language: language,
            description: YorksV1ProjectSetupDesktopStrings.attachmentsHelp,
          ),
          const SizedBox(height: 14),
          _ProjectAttachmentDropzone(
            language: language,
            onPick: c.onAddAttachment,
            onDropped: c.onDroppedAttachments,
            onDropError: c.onDropError,
          ),
          const SizedBox(height: 14),
          Text(
            '${c.draft.attachments.length} ${YorksV1ProjectStrings.files.active(language).toLowerCase()}',
            style: YorksProjectSetupMobileTheme.title.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
          _MobileFieldPair(
            first: TextField(
              readOnly: _ProjectSetupReadOnlyScope.of(context),
              key: const ValueKey('yorks-v1-mobile-file-search'),
              style: YorksProjectSetupMobileTheme.body,
              decoration:
                  YorksProjectSetupMobileTheme.inputDecoration(
                    hint: YorksV1ProjectSetupDesktopStrings.searchFiles.active(
                      language,
                    ),
                    prefix: const Icon(Icons.search, size: 20),
                  ).copyWith(
                    labelText: YorksV1ProjectSetupDesktopStrings.searchFiles
                        .active(language),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    constraints: const BoxConstraints(minHeight: 44),
                  ),
              onChanged: (value) => setState(() => _query = value),
            ),
            second: DropdownButtonFormField<String>(
              key: const ValueKey('yorks-v1-mobile-file-category-filter'),
              initialValue: _category,
              isExpanded: true,
              style: YorksProjectSetupMobileTheme.small.copyWith(
                color: YorksProjectSetupMobileTheme.navy,
              ),
              decoration: YorksProjectSetupMobileTheme.inputDecoration()
                  .copyWith(constraints: const BoxConstraints(minHeight: 44)),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text(
                    YorksV1ProjectSetupDesktopStrings.allCategories.active(
                      language,
                    ),
                  ),
                ),
                for (final category in YorksV1ProjectAttachmentCategory.values)
                  DropdownMenuItem(
                    value: category.wireValue,
                    child: Text(
                      _attachmentCategoryLabel(category).active(language),
                    ),
                  ),
              ],
              onChanged: _ProjectSetupReadOnlyScope.of(context)
                  ? null
                  : (value) => setState(() => _category = value ?? 'all'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            YorksV1ProjectSetupDesktopStrings.categoryHelp.active(language),
            style: YorksProjectSetupMobileTheme.small,
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: YorksProjectSetupMobileTheme.border),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                      final pending = c._pendingFileFor(file, c.pendingFiles);
                      final fileStatus = manifest?.status;
                      final ready =
                          fileStatus == YorksV1ProjectSetupFileStatus.ready;
                      final removed =
                          fileStatus == YorksV1ProjectSetupFileStatus.removed;
                      final failed =
                          fileStatus == YorksV1ProjectSetupFileStatus.failed ||
                          fileStatus ==
                              YorksV1ProjectSetupFileStatus.outcomeUncertain;
                      final needsReselect =
                          pending == null && !ready && !removed;
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
                          : c.setupState?.operation?.coreSucceeded == true &&
                                (fileStatus ==
                                        YorksV1ProjectSetupFileStatus
                                            .selected ||
                                    fileStatus ==
                                        YorksV1ProjectSetupFileStatus
                                            .needsReselect);
                      return Container(
                        key: ValueKey('yorks-v1-mobile-file-$identity'),
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          8,
                          8,
                          0,
                          8,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: YorksProjectSetupMobileTheme.border,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _DesktopFileIcon(fileName: file.fileName),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    file.fileName,
                                    style: YorksProjectSetupMobileTheme.body
                                        .copyWith(fontSize: 13),
                                  ),
                                  if (file.sizeBytes != null)
                                    Text(
                                      _formatAttachmentSize(file.sizeBytes!),
                                      style: YorksProjectSetupMobileTheme.small,
                                    ),
                                  Row(
                                    children: [
                                      Icon(
                                        ready
                                            ? Icons.check_circle
                                            : failed || needsReselect
                                            ? Icons.info_outline
                                            : Icons.schedule,
                                        size: 17,
                                        color: ready
                                            ? YorksProjectSetupMobileTheme
                                                  .success
                                            : failed || needsReselect
                                            ? AppColors.warning
                                            : YorksProjectSetupMobileTheme.blue,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          status.active(language),
                                          style: YorksProjectSetupMobileTheme
                                              .small,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _AttachmentCategoryPicker(
                                    key: ValueKey(
                                      'yorks-v1-mobile-file-category-$identity',
                                    ),
                                    attachment: file,
                                    language: language,
                                    onChanged:
                                        manifest == null &&
                                            c.setupState?.outcomeUncertain !=
                                                true
                                        ? (category) => c.onChangeCategory(
                                            index,
                                            category,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: OutlinedButton.icon(
                                      key: ValueKey(
                                        'yorks-v1-mobile-file-preview-$identity',
                                      ),
                                      onPressed: pending == null
                                          ? c.onAddAttachment
                                          : () => c.onPreviewAttachment(file),
                                      style: YorksProjectSetupMobileTheme
                                          .outlineButton,
                                      icon: Icon(
                                        pending == null
                                            ? Icons.attach_file
                                            : Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        (pending == null
                                                ? YorksV1ProjectStrings
                                                      .fileReselect
                                                : YorksV1ProjectSetupDesktopStrings
                                                      .preview)
                                            .active(language),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: ValueKey(
                                'yorks-v1-mobile-file-menu-$identity',
                              ),
                              tooltip: YorksV1ProjectStrings.manage.active(
                                language,
                              ),
                              icon: const Icon(Icons.more_vert, size: 20),
                              itemBuilder: (_) => [
                                if (needsReselect)
                                  PopupMenuItem(
                                    value: 'reselect',
                                    child: Text(
                                      YorksV1ProjectStrings.fileReselect.active(
                                        language,
                                      ),
                                    ),
                                  ),
                                if (failed &&
                                    c.onRetryFile != null &&
                                    manifest != null)
                                  PopupMenuItem(
                                    value: 'retry',
                                    child: Text(
                                      YorksV1ProjectStrings.retryFile.active(
                                        language,
                                      ),
                                    ),
                                  ),
                                if (pending != null)
                                  PopupMenuItem(
                                    value: 'preview',
                                    child: Text(
                                      YorksV1ProjectSetupDesktopStrings.preview
                                          .active(language),
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'remove',
                                  enabled: canRemove,
                                  child: Text(
                                    YorksV1ProjectStrings.remove.active(
                                      language,
                                    ),
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
                          ],
                        ),
                      );
                    },
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      YorksV1ProjectStrings.noAttachmentsAdded.active(language),
                      style: YorksProjectSetupMobileTheme.small,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            YorksV1ProjectStrings.operationalFilesOnly.active(language),
            style: YorksProjectSetupMobileTheme.small,
          ),
        ],
      ),
    );
  }
}

class _MobileDropzoneContents extends StatelessWidget {
  const _MobileDropzoneContents({
    required this.language,
    required this.onPick,
    required this.dragging,
  });
  final AppLanguage language;
  final VoidCallback onPick;
  final bool dragging;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 188),
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.insert_drive_file_outlined,
          size: 32,
          color: YorksProjectSetupMobileTheme.muted,
        ),
        const SizedBox(height: 8),
        Text(
          (dragging
                  ? YorksV1ProjectStrings.attachmentsDropzoneActive
                  : YorksV1ProjectSetupDesktopStrings.dropFilesHere)
              .active(language),
          textAlign: TextAlign.center,
          style: YorksProjectSetupMobileTheme.label.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          YorksV1ProjectSetupDesktopStrings.browseDevice.active(language),
          textAlign: TextAlign.center,
          style: YorksProjectSetupMobileTheme.small.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _ProjectSetupReadOnlyScope.of(context) ? null : onPick,
          style: YorksProjectSetupMobileTheme.blueButton,
          child: Text(YorksV1ProjectStrings.addAttachment.active(language)),
        ),
        const SizedBox(height: 9),
        Text(
          YorksV1ProjectSetupDesktopStrings.desktopFileTypes.active(language),
          textAlign: TextAlign.center,
          style: YorksProjectSetupMobileTheme.small,
        ),
      ],
    ),
  );
}

class _MobileReviewStage extends StatelessWidget {
  const _MobileReviewStage(this.config);
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
    final automatic = _automaticCreatorMembershipText(c.creatorRole, language);
    final team = c.editItem != null
        ? YorksV1ProjectStrings.accessAppliedSeparately.active(language)
        : [
            ?automatic,
            for (final member in draft.initialMembers)
              if (member.authUserId != c.creatorAuthUserId ||
                  member.projectRole != autoRole)
                '${_safeMemberDisplayName(byId[member.authUserId])} · ${YorksV1ProjectStrings.roleLabel(member.projectRole.wireValue).active(language)}',
          ].join('\n');
    final willBeActive =
        draft.initialMembers.any(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        ) ||
        autoRole == YorksV1ProjectMembershipRole.projectEngineer;
    bool fileBytesAvailable(YorksV1ProjectAttachmentInput file) =>
        file.contentHash != null &&
        c.pendingFiles.any(
          (selected) =>
              selected.fileName == file.fileName &&
              selected.mimeType == file.mimeType &&
              selected.bytes.length == file.sizeBytes &&
              sha256.convert(selected.bytes).toString() == file.contentHash,
        );
    final invalidRawDate = ['dateStartText', 'dateEndText'].any((key) {
      final value = (draft.rawEditorState[key] as String? ?? '').trim();
      return value.isNotEmpty && _parseTypedDate(value) == null;
    });
    final unfinishedBuilding =
        [
          'buildingName',
          'buildingCode',
          'buildingFloors',
          'buildingAddress',
        ].any(
          (key) =>
              (draft.rawEditorState[key] as String? ?? '').trim().isNotEmpty,
        ) ||
        draft.rawEditorState['buildingFrp'] == true;
    final unfinishedParty = ['subcontractorText', 'otherContractorText'].any(
      (key) => (draft.rawEditorState[key] as String? ?? '').trim().isNotEmpty,
    );
    final teamVerified =
        c.editItem != null ||
        draft.initialMembers.isEmpty ||
        (c.teamDirectory.asData != null &&
            !_hasUnavailableInitialMember(
              draft,
              c.teamDirectory.asData!.value,
            ));
    final ready =
        errors.isEmpty &&
        c.validationErrors.isEmpty &&
        !invalidRawDate &&
        !unfinishedBuilding &&
        !unfinishedParty &&
        teamVerified;
    final complete = <YorksV1ProjectCreationStage, bool>{
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
          !unfinishedParty &&
          !errors.any(
            (error) => {
              YorksV1ProjectValidationCode.invalidProjectParty,
              YorksV1ProjectValidationCode.duplicateProjectParty,
              YorksV1ProjectValidationCode.missingMemberAuthUserId,
              YorksV1ProjectValidationCode.duplicateMember,
            }.contains(error),
          ),
      YorksV1ProjectCreationStage.buildings:
          !unfinishedBuilding &&
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
    Widget values(List<(TranslatableString, String)> rows) => LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            MediaQuery.textScalerOf(context).scale(1) > 1.1 ||
            constraints.maxWidth < 300;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: YorksProjectSetupMobileTheme.border),
                  ),
                ),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.$1.active(language),
                            style: YorksProjectSetupMobileTheme.small,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            row.$2,
                            style: YorksProjectSetupMobileTheme.body.copyWith(
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 39,
                            child: Text(
                              row.$1.active(language),
                              style: YorksProjectSetupMobileTheme.small,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 61,
                            child: Text(
                              row.$2,
                              style: YorksProjectSetupMobileTheme.body.copyWith(
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
          ],
        );
      },
    );
    Widget section(
      YorksV1ProjectCreationStage stage,
      IconData icon,
      Widget child,
    ) {
      final label = switch (stage) {
        YorksV1ProjectCreationStage.projectDetails =>
          YorksV1ProjectStrings.editProjectDetails,
        YorksV1ProjectCreationStage.partiesAndAccess =>
          YorksV1ProjectStrings.editPartiesAccess,
        YorksV1ProjectCreationStage.buildings =>
          YorksV1ProjectStrings.editBuildings,
        YorksV1ProjectCreationStage.attachments =>
          YorksV1ProjectStrings.editAttachments,
        YorksV1ProjectCreationStage.reviewAndCreate =>
          YorksV1ProjectStrings.edit,
      };
      return _MobileSetupCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MobileSetupHeading(
              title: _stageCopy(stage),
              language: language,
              icon: icon,
              action: Semantics(
                label: label.active(language),
                button: true,
                onTap: () => c.onEdit(stage),
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: () => c.onEdit(stage),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: YorksProjectSetupMobileTheme.body,
                    foregroundColor: YorksProjectSetupMobileTheme.blue,
                  ),
                  label: Text(YorksV1ProjectStrings.edit.active(language)),
                ),
              ),
            ),
            const SizedBox(height: 5),
            child,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ready
                ? const Color(0xFFE6F4EF)
                : YorksProjectSetupMobileTheme.help,
            border: Border.all(color: YorksProjectSetupMobileTheme.border),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ready ? Icons.check_circle : Icons.info_outline,
                size: 30,
                color: ready
                    ? YorksProjectSetupMobileTheme.success
                    : YorksProjectSetupMobileTheme.blue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (ready
                              ? YorksV1ProjectStrings.readyToCreateWorkspace
                              : YorksV1ProjectStrings.stageNeedsAttention)
                          .active(language),
                      style: YorksProjectSetupMobileTheme.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      YorksV1ProjectSetupMobileStrings.materialsLater.active(
                        language,
                      ),
                      style: YorksProjectSetupMobileTheme.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        section(
          YorksV1ProjectCreationStage.projectDetails,
          Icons.description_outlined,
          values([
            (YorksV1ProjectStrings.yorksReference, draft.reference),
            (YorksV1ProjectStrings.projectName, draft.name),
            if (_emptyToNull(draft.jobOrContractReference) != null)
              (
                YorksV1ProjectStrings.jobOrContractReference,
                draft.jobOrContractReference!,
              ),
            (YorksV1ProjectStrings.siteLocation, text(draft.siteLocation)),
            (YorksV1ProjectStrings.startDate, date(draft.startDate)),
            (YorksV1ProjectStrings.endDate, date(draft.endDate)),
            (YorksV1ProjectStrings.notes, text(draft.notes)),
            if (_emptyToNull(draft.clientContactName) != null)
              (YorksV1ProjectStrings.contactName, draft.clientContactName!),
            if (_emptyToNull(draft.clientContactPhone) != null)
              (YorksV1ProjectStrings.contactPhone, draft.clientContactPhone!),
            if (_emptyToNull(draft.clientContactEmail) != null)
              (YorksV1ProjectStrings.contactEmail, draft.clientContactEmail!),
            if (_emptyToNull(draft.clientAddress) != null)
              (YorksV1ProjectStrings.contactAddress, draft.clientAddress!),
          ]),
        ),
        const SizedBox(height: 10),
        section(
          YorksV1ProjectCreationStage.partiesAndAccess,
          Icons.people_outline,
          values([
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
                  draft.parties
                      .where((party) => party.kind == kind)
                      .map((party) => party.name)
                      .join(', '),
                ),
            (
              YorksV1ProjectStrings.projectTeam,
              team.isEmpty
                  ? YorksV1ProjectStrings.notProvided.active(language)
                  : team,
            ),
          ]),
        ),
        const SizedBox(height: 10),
        section(
          YorksV1ProjectCreationStage.buildings,
          Icons.apartment,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final building in draft.buildings)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: YorksProjectSetupMobileTheme.border,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              building.name,
                              style: YorksProjectSetupMobileTheme.body.copyWith(
                                fontSize: 12.5,
                              ),
                            ),
                            if (building.code.isNotEmpty)
                              Text(
                                building.code,
                                style: YorksProjectSetupMobileTheme.small,
                              ),
                            if (building.floorsOrLevels.isNotEmpty)
                              Text(
                                building.floorsOrLevels.join(', '),
                                style: YorksProjectSetupMobileTheme.small,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${YorksV1ProjectSetupDesktopStrings.frp.active(language)}: ${(building.hasFrpRoom ? YorksV1ProjectSetupDesktopStrings.yes : YorksV1ProjectSetupDesktopStrings.no).active(language)}',
                          style: YorksProjectSetupMobileTheme.small,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        section(
          YorksV1ProjectCreationStage.attachments,
          Icons.attach_file,
          draft.attachments.isEmpty
              ? Text(
                  YorksV1ProjectSetupDesktopStrings.optionalSkipped.active(
                    language,
                  ),
                  style: YorksProjectSetupMobileTheme.small,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final file in draft.attachments)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: YorksProjectSetupMobileTheme.border,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.fileName,
                              style: YorksProjectSetupMobileTheme.body.copyWith(
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${file.fileName.split('.').last.toUpperCase()} · ${file.sizeBytes == null ? '—' : _formatAttachmentSize(file.sizeBytes!)}',
                              style: YorksProjectSetupMobileTheme.small,
                            ),
                            Text(
                              (fileBytesAvailable(file)
                                      ? YorksV1ProjectSetupDesktopStrings
                                            .selectedLocally
                                      : YorksV1ProjectStrings.fileReselect)
                                  .active(language),
                              style: YorksProjectSetupMobileTheme.small,
                            ),
                            Text(
                              _attachmentCategoryLabel(
                                file.category,
                              ).active(language),
                              style: YorksProjectSetupMobileTheme.small,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        _MobileSetupCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MobileSetupHeading(
                title: ready && complete.values.every((value) => value)
                    ? YorksV1ProjectSetupDesktopStrings.allSelectionsComplete
                    : YorksV1ProjectStrings.stageNeedsAttention,
                language: language,
                icon: ready ? Icons.check_circle : Icons.info_outline,
                description:
                    YorksV1ProjectSetupDesktopStrings.reviewContinueHelp,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final stage in complete.keys)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          complete[stage]!
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 18,
                          color: complete[stage]!
                              ? YorksProjectSetupMobileTheme.success
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _stageCopy(stage).active(language),
                            style: YorksProjectSetupMobileTheme.small,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (c.editItem == null) ...[
                const SizedBox(height: 10),
                Text(
                  (willBeActive
                          ? YorksV1ProjectStrings.expectedActiveProject
                          : YorksV1ProjectStrings.expectedDraftProject)
                      .active(language),
                  style: YorksProjectSetupMobileTheme.small,
                ),
              ],
            ],
          ),
        ),
        if (c.editItem != null) ...[
          const SizedBox(height: 10),
          _EditProposalComparison(draft: draft, language: language),
        ],
        if (c.teamDirectory.hasError &&
            draft.initialMembers.isNotEmpty &&
            c.editItem == null) ...[
          const SizedBox(height: 10),
          Text(
            YorksV1ProjectStrings.teamDirectoryUnavailable.active(language),
            style: YorksProjectSetupMobileTheme.small.copyWith(
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
    );
  }
}
