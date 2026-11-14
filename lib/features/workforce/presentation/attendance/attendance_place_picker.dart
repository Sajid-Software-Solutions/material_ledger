/// Workforce attendance — choosing where attendance is taken (a project or an
/// internal location such as the workshop) and the building of a row
/// (PRODUCT_DECISIONS section 51).
///
/// The list puts the places used most recently first, then the person's own
/// projects, then every other project they may keep or read, then the
/// workshop and other places. Typing finds a project by its number or name,
/// forgiving spelling; a name that matches nothing can be added as a new
/// place by anyone who keeps attendance.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import 'attendance_common.dart';

/// What was chosen in the place list.
sealed class AttendancePlaceChoice {
  const AttendancePlaceChoice();
}

final class AttendancePickProject extends AttendancePlaceChoice {
  const AttendancePickProject(this.project);

  final AttendancePlaceProject project;
}

/// An internal location: an open one ([crewId]) or a new one by [name].
final class AttendancePickLocation extends AttendancePlaceChoice {
  const AttendancePickLocation({required this.name, this.crewId});

  final String name;
  final String? crewId;
}

/// The place list in a tall sheet on phones and a dialog elsewhere.
Future<AttendancePlaceChoice?> showAttendancePlacePicker(
  BuildContext context, {
  required AppLanguage language,
  required AttendancePlaces places,
  List<String> recent = const [],
  String? currentCrewId,
}) {
  Widget list(BuildContext context) => AttendancePlaceList(
    language: language,
    places: places,
    recent: recent,
    currentCrewId: currentCrewId,
    autofocus: !AccountsV2Breakpoints.isPhone(context),
    onPick: (choice) => Navigator.of(context).pop(choice),
    onClose: () => Navigator.of(context).pop(),
  );
  if (AccountsV2Breakpoints.isPhone(context)) {
    return showModalBottomSheet<AttendancePlaceChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(heightFactor: .9, child: list(context)),
      ),
    );
  }
  return showDialog<AttendancePlaceChoice>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: list(context),
      ),
    ),
  );
}

/// Search and sections of places. Used in the picker and, when nothing is
/// chosen yet, on the page itself.
class AttendancePlaceList extends StatefulWidget {
  const AttendancePlaceList({
    super.key,
    required this.language,
    required this.places,
    required this.onPick,
    this.recent = const [],
    this.currentCrewId,
    this.onClose,
    this.autofocus = false,
    this.shrinkWrap = false,
  });

  final AppLanguage language;
  final AttendancePlaces places;
  final ValueChanged<AttendancePlaceChoice> onPick;
  final List<String> recent;
  final String? currentCrewId;
  final VoidCallback? onClose;
  final bool autofocus;

  /// Sized to its content, inside a page that scrolls.
  final bool shrinkWrap;

  @override
  State<AttendancePlaceList> createState() => _AttendancePlaceListState();
}

typedef _Entry = ({
  String key,
  String title,
  String subtitle,
  String icon,
  String? crewId,
  AttendancePlaceChoice choice,
});

class _AttendancePlaceListState extends State<AttendancePlaceList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppLanguage get _language => widget.language;

  _Entry _project(AttendancePlaceProject project) {
    final buildings = project.buildings.where((b) => !b.isCommon).length;
    final parts = <String>[
      if (buildings > 0) AS.t(AS.buildingsCount, _language, {'n': buildings}),
      if (!project.canTake && project.crewId == null)
        AS.t(AS.placeNothingRecorded, _language),
      if (!project.canTake && project.crewId != null)
        AS.t(AS.readOnly, _language),
    ];
    return (
      key: 'project-${project.id}',
      title: project.label,
      subtitle: parts.join(' · '),
      icon: 'bldg',
      crewId: project.crewId,
      choice: AttendancePickProject(project),
    );
  }

  _Entry _location(AttendancePlaceLocation location) => (
    key: 'location-${location.crewId}',
    title: location.name,
    subtitle: location.canTake ? '' : AS.t(AS.readOnly, _language),
    icon: 'box',
    crewId: location.crewId,
    choice: AttendancePickLocation(
      name: location.name,
      crewId: location.crewId,
    ),
  );

  List<(String?, List<_Entry>)> _sections() {
    final places = widget.places;
    final projects = [for (final p in places.projects) _project(p)];
    final locations = [for (final l in places.locations) _location(l)];
    final everything = [...projects, ...locations];
    final text = _search.text.trim();
    if (text.isNotEmpty) {
      final hits = attendanceFuzzySearch(
        text,
        everything,
        (entry) => entry.title,
        limit: 30,
      );
      return [
        (null, [for (final hit in hits) hit.item]),
      ];
    }
    final byCrew = {
      for (final entry in everything)
        if (entry.crewId != null) entry.crewId!: entry,
    };
    final recent = [
      for (final crewId in widget.recent) ?byCrew[crewId],
    ].take(3).toList();
    final shown = {for (final entry in recent) entry.key};
    final mine = [
      for (final p in places.projects)
        if (p.isMember && !shown.contains('project-${p.id}')) _project(p),
    ];
    final others = [
      for (final p in places.projects)
        if (!p.isMember && !shown.contains('project-${p.id}')) _project(p),
    ];
    final rest = [
      for (final entry in locations)
        if (!shown.contains(entry.key)) entry,
    ];
    return [
      if (recent.isNotEmpty) (AS.t(AS.placeRecent, _language), recent),
      if (mine.isNotEmpty) (AS.t(AS.placeMyProjects, _language), mine),
      if (others.isNotEmpty)
        (
          mine.isEmpty
              ? AS.t(AS.placeAllProjects, _language)
              : AS.t(AS.placeOtherProjects, _language),
          others,
        ),
      if (rest.isNotEmpty) (AS.t(AS.placeLocations, _language), rest),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final sections = _sections();
    final typed = _search.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final exact = widget.places.locations.any(
      (l) => l.name.toLowerCase() == typed.toLowerCase(),
    );
    final canAdd =
        widget.places.canTake &&
        typed.length >= 2 &&
        typed.length <= 80 &&
        !exact;
    final empty = sections.every((section) => section.$2.isEmpty);

    final tiles = <Widget>[
      for (final (title, entries) in sections) ...[
        if (title != null && entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Text(
              title.toUpperCase(),
              style: v2Style(
                11,
                weight: FontWeight.w700,
                color: AccountsV2Colors.mut,
                letterSpacing: 0.4,
              ),
            ),
          ),
        for (final entry in entries)
          _PlaceTile(
            key: ValueKey('attendance-place-${entry.key}'),
            entry: entry,
            selected:
                entry.crewId != null && entry.crewId == widget.currentCrewId,
            onTap: () => widget.onPick(entry.choice),
          ),
      ],
      if (empty && !canAdd)
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            AS.t(AS.placeNoMatch, language),
            style: v2Style(13, color: AccountsV2Colors.mut),
          ),
        ),
      if (canAdd)
        _PlaceTile(
          key: const ValueKey('attendance-place-add'),
          entry: (
            key: 'add',
            title: AS.t(AS.placeNewLocation, language, {'name': typed}),
            subtitle: '',
            icon: 'plus',
            crewId: null,
            choice: AttendancePickLocation(name: typed),
          ),
          selected: false,
          onTap: () => widget.onPick(AttendancePickLocation(name: typed)),
        ),
      if (widget.places.canTake && !canAdd)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: Text(
            AS.t(AS.placeNewLocationHint, language),
            style: v2Style(12, color: AccountsV2Colors.mut),
          ),
        ),
    ];

    final search = Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
      child: AccountsV2TextField(
        key: const ValueKey('attendance-place-search'),
        label: AS.t(AS.placeSearch, language),
        controller: _search,
        search: true,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          final first = sections.expand((section) => section.$2).firstOrNull;
          if (first != null) {
            widget.onPick(first.choice);
          } else if (canAdd) {
            widget.onPick(AttendancePickLocation(name: typed));
          }
        },
      ),
    );

    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AS.t(AS.choosePlaceTitle, language),
              style: v2Style(17, weight: FontWeight.w700),
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: AS.t(AS.cancel, language),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
        ],
      ),
    );

    if (widget.shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [search, ...tiles],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        search,
        Expanded(
          child: ListView(
            key: const ValueKey('attendance-place-list'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 12),
            children: tiles,
          ),
        ),
      ],
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _Entry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AccountsV2Colors.pri50 : Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AccountsV2Colors.pri50,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AccountsV2Icon(
                    entry.icon,
                    size: 17,
                    color: AccountsV2Colors.pri,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        style: v2Style(14, weight: FontWeight.w600),
                      ),
                      if (entry.subtitle.isNotEmpty)
                        Text(
                          entry.subtitle,
                          style: v2Style(12, color: AccountsV2Colors.mut),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: AccountsV2Colors.pri,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Buildings ───────────────────────────────────────────────────────────────

/// A building's name, with the project's Common scope shown as "Common".
String attendanceBuildingName(
  AttendanceBuilding building,
  AppLanguage language,
) => building.isCommon ? AS.t(AS.buildingCommon, language) : building.name;

/// The building a row names, by the place's buildings when it is one of
/// them; null when the row names none.
String? attendanceRowBuilding(
  AttendanceRow row,
  AttendanceCrew crew,
  AppLanguage language,
) {
  final id = row.workScopeId;
  if (id == null) return null;
  final known = crew.buildings.where((b) => b.id == id).firstOrNull;
  if (known != null) return attendanceBuildingName(known, language);
  final name = row.workScopeName;
  if (name == null) return null;
  return name == 'Common / All Buildings'
      ? AS.t(AS.buildingCommon, language)
      : name;
}

/// Chooses one of the place's buildings. Resolves to the chosen building
/// (null for No building), or to null when closed: callers read
/// `.building` from the record.
Future<({AttendanceBuilding? building})?> showAttendanceBuildingPicker(
  BuildContext context, {
  required AppLanguage language,
  required List<AttendanceBuilding> buildings,
  String? selectedId,
}) {
  Widget body(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AS.t(AS.chooseBuilding, language),
                style: v2Style(17, weight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: AS.t(AS.cancel, language),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            for (final building in buildings)
              _PlaceTile(
                key: ValueKey('attendance-building-${building.id}'),
                entry: (
                  key: building.id,
                  title: attendanceBuildingName(building, language),
                  subtitle: '',
                  icon: building.isCommon ? 'grid' : 'bldg',
                  crewId: null,
                  choice: const AttendancePickLocation(name: ''),
                ),
                selected: building.id == selectedId,
                onTap: () => Navigator.of(context).pop((building: building)),
              ),
            _PlaceTile(
              key: const ValueKey('attendance-building-none'),
              entry: (
                key: 'none',
                title: AS.t(AS.noBuilding, language),
                subtitle: '',
                icon: 'x',
                crewId: null,
                choice: const AttendancePickLocation(name: ''),
              ),
              selected: selectedId == null,
              onTap: () => Navigator.of(context).pop((building: null)),
            ),
          ],
        ),
      ),
    ],
  );
  if (AccountsV2Breakpoints.isPhone(context)) {
    return showModalBottomSheet<({AttendanceBuilding? building})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: body,
    );
  }
  return showDialog<({AttendanceBuilding? building})>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: body(context),
      ),
    ),
  );
}

/// A small tappable chip naming a row's building ("Tower A ▾"), or asking
/// for one.
class AttendanceBuildingChip extends StatelessWidget {
  const AttendanceBuildingChip({
    super.key,
    required this.label,
    required this.language,
    this.onTap,
  });

  /// The building's name, or null when none is chosen yet.
  final String? label;
  final AppLanguage language;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = label ?? AS.t(AS.chooseBuilding, language);
    final style = v2Style(
      12,
      weight: FontWeight.w600,
      color: label == null ? AccountsV2Colors.warn : AccountsV2Colors.ink2,
    );
    return Semantics(
      button: onTap != null,
      label: '${AS.t(AS.colBuilding, language)}: $text',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: onTap == null ? 0 : 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.apartment_rounded,
                  size: 14,
                  color: label == null
                      ? AccountsV2Colors.warn
                      : AccountsV2Colors.mut,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    text,
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: AccountsV2Colors.mut,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
