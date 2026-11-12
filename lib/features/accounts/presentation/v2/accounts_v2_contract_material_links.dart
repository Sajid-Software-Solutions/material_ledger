part of 'accounts_v2_contract_tab.dart';

/// The stage deliveries to site measure. Installation and later stages are
/// done on site, so a delivery says nothing about them.
const _materialSupplyStage = 'material_supply';

/// A BOQ folder name as the screen compares it.
String _folderNameKey(String name) => name.trim().toLowerCase();

/// The folders of the contract's buildings, grouped by name: picking a name
/// links the folder of that name in every building that has one.
final class _FolderNames {
  _FolderNames(YorksAccountsMaterialSources sources, this.buildingIds) {
    for (final f in sources.folders) {
      if (!buildingIds.contains(f.projectScopeId)) continue;
      final key = _folderNameKey(f.name);
      names.putIfAbsent(key, () => f.name.trim());
      byName.putIfAbsent(key, () => {})[f.projectScopeId] = f;
      byId[f.boqGroupId] = key;
    }
  }

  final List<String> buildingIds;

  /// Name key → the name as first shown.
  final Map<String, String> names = {};

  /// Name key → building → folder.
  final Map<String, Map<String, YorksAccountsBoqFolder>> byName = {};

  /// Folder id → name key.
  final Map<String, String> byId = {};

  bool get isEmpty => names.isEmpty;

  int buildingCount(String key) => byName[key]?.length ?? 0;

  /// The buildings in which an item is linked to the folder named [key].
  int linkedBuildings(
    YorksAccountsMaterialSources sources,
    String stageKey,
    String itemKey,
    String key,
  ) => {
    for (final l in sources.links)
      if (l.stageKey == stageKey &&
          l.itemKey == itemKey &&
          byId[l.boqGroupId] == key)
        l.projectScopeId,
  }.length;

  /// The name keys linked to an item, in folder-name order.
  List<String> linkedTo(
    YorksAccountsMaterialSources sources,
    String stageKey,
    String itemKey,
  ) {
    final keys = <String>{
      for (final l in sources.links)
        if (l.stageKey == stageKey &&
            l.itemKey == itemKey &&
            byId.containsKey(l.boqGroupId))
          byId[l.boqGroupId]!,
    };
    return [
      for (final k in names.keys)
        if (keys.contains(k)) k,
    ];
  }
}

/// One saved item of an items-measured stage, with every building it is in.
final class _LinkItem {
  _LinkItem({
    required this.stageKey,
    required this.itemKey,
    required this.label,
    required this.unit,
    required this.quantity,
  });

  final String stageKey;
  final String itemKey;
  final String label;
  final String unit;

  /// The item's quantity in the first building, for its label.
  final YorksAccountsDecimal quantity;

  /// The item's quantity in each building that has it.
  final Map<String, YorksAccountsDecimal> quantityIn = {};

  Iterable<String> get buildingIds => quantityIn.keys;

  String get id => '$stageKey|$itemKey';
}

/// The saved items of [stageKey], one per item key.
List<_LinkItem> _linkItems(
  YorksAccountsCommercialSetupRead setup,
  String stageKey,
) {
  final byKey = <String, _LinkItem>{};
  for (final it in setup.itemsForStage(stageKey)) {
    byKey
            .putIfAbsent(
              it.itemKey,
              () => _LinkItem(
                stageKey: stageKey,
                itemKey: it.itemKey,
                label: it.itemLabel,
                unit: it.unitCode,
                quantity: it.quantity,
              ),
            )
            .quantityIn[it.projectScopeId] =
        it.quantity;
  }
  return byKey.values.toList(growable: false);
}

/// How well a BOQ folder name fits an item label, from 0 to 1: 1 when one
/// name contains the other ("AC Units" in "AC Units (Package Unit)"),
/// otherwise the share of meaningful words they have in common, a word
/// matching one it starts ("Attenuator" and "Attenuators"). Suggestions use
/// only clear matches, above one half, so "Duct heater" is not "GI Ductwork".
double _nameScore(String label, String folder) {
  const generic = {
    'supply',
    'supplies',
    'installation',
    'install',
    'works',
    'work',
    'material',
    'materials',
    'item',
    'items',
    'unit',
    'units',
    'system',
    'systems',
    'general',
    'misc',
    'with',
  };
  String flat(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final a = flat(label);
  final b = flat(folder);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b ||
      (b.length >= 5 && a.contains(b)) ||
      (a.length >= 5 && b.contains(a))) {
    return 1;
  }
  List<String> words(String s) => [
    for (final w in s.toLowerCase().split(RegExp('[^a-z0-9]+')))
      if (w.length >= 4 && !generic.contains(w)) w,
  ];
  bool same(String x, String y) {
    if (x.startsWith(y) || y.startsWith(x)) return true;
    var common = 0;
    while (common < x.length && common < y.length && x[common] == y[common]) {
      common++;
    }
    return common >= 5;
  }

  final ofLabel = words(label);
  final ofFolder = words(folder);
  if (ofLabel.isEmpty || ofFolder.isEmpty) return 0;
  final matched = ofFolder.where((y) => ofLabel.any((x) => same(x, y))).length;
  return 2 * matched / (ofLabel.length + ofFolder.length);
}

/// The links a choice of folder names makes: for each item, the folder of each
/// chosen name in every building that has both the item and the folder.
List<YorksAccountsMaterialLink> _linksFor(
  Map<String, Set<String>> chosen,
  Map<String, _LinkItem> items,
  _FolderNames folders,
) {
  return [
    for (final entry in chosen.entries)
      if (items[entry.key] case final item?)
        for (final name in entry.value)
          for (final building in item.buildingIds)
            if (folders.byName[name]?[building] case final folder?)
              YorksAccountsMaterialLink(
                projectScopeId: building,
                stageKey: item.stageKey,
                itemKey: item.itemKey,
                boqGroupId: folder.boqGroupId,
              ),
  ];
}

/// Under an items-measured stage: which BOQ folders each item stands for and
/// what has reached site from them. Read-only; [onEdit] opens the editor.
class _MaterialLinksCard extends StatelessWidget {
  const _MaterialLinksCard({
    required this.setup,
    required this.stage,
    required this.sources,
    required this.language,
    required this.onEdit,
  });

  final YorksAccountsCommercialSetupRead setup;
  final YorksAccountsSetupReadStage stage;
  final YorksAccountsMaterialSources sources;
  final AppLanguage language;
  final VoidCallback? onEdit;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final buildingIds = [for (final b in setup.buildings) b.projectScopeId];
    final folders = _FolderNames(sources, buildingIds);
    final items = _linkItems(setup, stage.stageKey);
    final anyLinked = items.any(
      (i) => folders.linkedTo(sources, i.stageKey, i.itemKey).isNotEmpty,
    );
    final canEdit = onEdit != null && !folders.isEmpty;
    return AccountsV2Panel(
      key: ValueKey('v2m_card_${stage.stageKey}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'folder',
            title: '${stage.stageName} — ${_t('v2m_title_suffix')}',
            subtitle: _t('v2m_sub'),
            actions: canEdit
                ? [
                    AccountsV2Button(
                      key: ValueKey('v2m_edit_${stage.stageKey}'),
                      label: _t(anyLinked ? 'v2m_edit' : 'v2m_link'),
                      icon: anyLinked ? 'edit' : 'folder',
                      kind: anyLinked
                          ? AccountsV2ButtonKind.normal
                          : AccountsV2ButtonKind.primary,
                      size: AccountsV2ButtonSize.small,
                      onPressed: onEdit,
                    ),
                  ]
                : const [],
          ),
          if (folders.isEmpty)
            AccountsV2CardBody(
              child: AccountsV2Empty(
                icon: 'folder',
                title: _t('v2m_no_folders'),
                body: _t('v2m_no_folders_body'),
              ),
            )
          else
            AccountsV2Table(
              phoneCards: true,
              columns: [
                const AccountsV2Column('#', width: 44, center: true),
                AccountsV2Column(_t('v2c_item')),
                AccountsV2Column(_t('v2m_col_folders'), flex: 2),
                AccountsV2Column(_t('v2m_col_delivered'), width: 190),
              ],
              rows: [
                for (final (i, item) in items.indexed)
                  AccountsV2Row([
                    Text(
                      '${i + 1}',
                      style: v2Style(12.5, color: AccountsV2Colors.mut),
                    ),
                    AccountsV2CellStack(
                      primary: item.label,
                      secondary:
                          '${item.quantity.displayText(maximumFractionDigits: 2)} '
                          '${item.unit}',
                    ),
                    _LinkedFolders(
                      item: item,
                      sources: sources,
                      folders: folders,
                      language: language,
                    ),
                    _DeliveredCell(
                      item: item,
                      sources: sources,
                      linked: folders
                          .linkedTo(sources, item.stageKey, item.itemKey)
                          .isNotEmpty,
                      language: language,
                    ),
                  ]),
              ],
              emptyRow: AccountsV2Empty(
                icon: 'list',
                title: _t('v2c_no_items'),
              ),
            ),
        ],
      ),
    );
  }
}

/// The folder names an item is linked to, with how many of its buildings
/// each covers when that is not all of them.
class _LinkedFolders extends StatelessWidget {
  const _LinkedFolders({
    required this.item,
    required this.sources,
    required this.folders,
    required this.language,
  });

  final _LinkItem item;
  final YorksAccountsMaterialSources sources;
  final _FolderNames folders;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final names = folders.linkedTo(sources, item.stageKey, item.itemKey);
    final buildings = item.buildingIds.length;
    if (names.isEmpty) {
      return Text(
        accountsV2Text(language, 'v2m_not_linked'),
        style: v2Style(12.5, color: AccountsV2Colors.mut),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final k in names)
          AccountsV2Chip(
            switch (folders.linkedBuildings(
              sources,
              item.stageKey,
              item.itemKey,
              k,
            )) {
              final n when n < buildings =>
                '${folders.names[k]} · $n/$buildings',
              _ => folders.names[k]!,
            },
            tone: AccountsV2ChipTone.pri,
            icon: 'folder',
          ),
      ],
    );
  }
}

/// Delivered across the item's buildings, against its total quantity.
class _DeliveredCell extends StatelessWidget {
  const _DeliveredCell({
    required this.item,
    required this.sources,
    required this.linked,
    required this.language,
  });

  final _LinkItem item;
  final YorksAccountsMaterialSources sources;
  final bool linked;
  final AppLanguage language;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    if (!linked) {
      return Text('—', style: v2Style(12.5, color: AccountsV2Colors.mut));
    }
    var delivered = YorksAccountsDecimal.zero;
    var total = YorksAccountsDecimal.zero;
    var deliveries = 0;
    var share = false;
    YorksAccountsItemDelivered? latest;
    for (final MapEntry(key: b, value: quantity) in item.quantityIn.entries) {
      total = total + quantity;
      final d = sources.deliveredFor(b, item.stageKey, item.itemKey);
      if (d == null) continue;
      delivered =
          delivered +
          (d.deliveredQty.compareTo(quantity) > 0 ? quantity : d.deliveredQty);
      deliveries += d.deliveries;
      share = share || d.isShare;
      if (latest == null ||
          (d.lastDeliveryDate ?? '').compareTo(latest.lastDeliveryDate ?? '') >
              0) {
        latest = d;
      }
    }
    if (deliveries == 0) {
      return Text(
        _t('v2m_nothing_yet'),
        style: v2Style(12.5, color: AccountsV2Colors.mut),
      );
    }
    final figure =
        '${share ? '~ ' : ''}'
        '${delivered.displayText(maximumFractionDigits: 2)} ${_t('v2o_of')} '
        '${total.displayText(maximumFractionDigits: 2)} ${item.unit}';
    final cell = AccountsV2CellStack(
      primary: figure,
      secondary: [
        '$deliveries ${_t(deliveries == 1 ? 'v2m_delivery' : 'v2m_deliveries')}',
        ?latest?.lastDeliveryReference,
      ].join(' · '),
    );
    return share ? Tooltip(message: _t('v2m_share_hint'), child: cell) : cell;
  }
}

/// The link editor, in a drawer: every items-measured stage of the saved
/// contract, each item with the folder names it may stand for. A folder stands
/// for one item of a stage. Saving replaces every link of the project.
class _MaterialLinksDrawer extends StatefulWidget {
  const _MaterialLinksDrawer({
    required this.setup,
    required this.sources,
    required this.language,
    required this.onSave,
  });

  final YorksAccountsCommercialSetupRead setup;
  final YorksAccountsMaterialSources sources;
  final AppLanguage language;
  final YorksSaveMaterialLinksAction onSave;

  @override
  State<_MaterialLinksDrawer> createState() => _MaterialLinksDrawerState();
}

class _MaterialLinksDrawerState extends State<_MaterialLinksDrawer> {
  late final _FolderNames _folders;
  late final List<YorksAccountsSetupReadStage> _stages;
  late final Map<String, List<_LinkItem>> _itemsByStage;
  late final Map<String, _LinkItem> _items;
  final Map<String, Set<String>> _chosen = {};
  late final String _initial;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final setup = widget.setup;
    _folders = _FolderNames(widget.sources, [
      for (final b in setup.buildings) b.projectScopeId,
    ]);
    _stages = [
      for (final s in setup.stages)
        if (s.stageKey == _materialSupplyStage &&
            s.isItemsMode &&
            setup.itemsForStage(s.stageKey).isNotEmpty)
          s,
    ];
    _itemsByStage = {
      for (final s in _stages) s.stageKey: _linkItems(setup, s.stageKey),
    };
    _items = {
      for (final list in _itemsByStage.values)
        for (final i in list) i.id: i,
    };
    for (final i in _items.values) {
      _chosen[i.id] = _folders
          .linkedTo(widget.sources, i.stageKey, i.itemKey)
          .toSet();
    }
    _initial = _snapshot();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _snapshot() => [
    for (final id in _items.keys)
      '$id=${(_chosen[id]!.toList()..sort()).join(',')}',
  ].join(';');

  bool get _dirty => _snapshot() != _initial;

  /// Saving replaces every link of the project, so links this editor does not
  /// show (another stage's) go back as they are, while they are still valid:
  /// a folder that can be linked and an item the contract still has.
  List<YorksAccountsMaterialLink> _otherLinks() {
    final shown = {for (final s in _stages) s.stageKey};
    final folderIds = {for (final f in widget.sources.folders) f.boqGroupId};
    return [
      for (final l in widget.sources.links)
        if (!shown.contains(l.stageKey) &&
            folderIds.contains(l.boqGroupId) &&
            widget.setup.items.any(
              (i) =>
                  i.projectScopeId == l.projectScopeId &&
                  i.stageKey == l.stageKey &&
                  i.itemKey == l.itemKey,
            ))
          l,
    ];
  }

  /// The other item of the same stage that already stands for [name].
  _LinkItem? _usedBy(_LinkItem item, String name) {
    for (final other in _itemsByStage[item.stageKey]!) {
      if (other.id != item.id && _chosen[other.id]!.contains(name)) {
        return other;
      }
    }
    return null;
  }

  void _toggle(_LinkItem item, String name) {
    setState(() {
      final set = _chosen[item.id]!;
      if (!set.remove(name)) set.add(name);
      _error = null;
    });
  }

  /// Gives each folder name no item uses yet to the item it fits best, among
  /// items with nothing chosen. Choices already made are kept.
  void _suggest() {
    var added = 0;
    setState(() {
      final open = [
        for (final item in _items.values)
          if (_chosen[item.id]!.isEmpty) item,
      ];
      for (final name in _folders.names.keys) {
        _LinkItem? best;
        var bestScore = 0.5;
        for (final item in open) {
          if (_usedBy(item, name) != null) continue;
          final score = _nameScore(item.label, _folders.names[name]!);
          if (score > bestScore) {
            best = item;
            bestScore = score;
          }
        }
        if (best == null) continue;
        _chosen[best.id]!.add(name);
        added++;
      }
    });
    if (added == 0) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(_t('v2m_suggest_none'))));
    }
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty || !_dirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave([
      ..._linksFor(_chosen, _items, _folders),
      ..._otherLinks(),
    ], reason);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = accountsV2ErrorText(widget.language, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _dirty && _reason.text.trim().isNotEmpty && !_saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              Text(
                _t('v2m_drawer_intro'),
                style: v2Style(
                  12.5,
                  color: AccountsV2Colors.ink2,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AccountsV2Button(
                  key: const ValueKey('v2m_suggest'),
                  label: _t('v2m_suggest'),
                  icon: 'spark',
                  size: AccountsV2ButtonSize.small,
                  onPressed: _saving ? null : _suggest,
                ),
              ),
              for (final (si, stage) in _stages.indexed) ...[
                AccountsV2Section(stage.stageName, first: false),
                for (final item in _itemsByStage[stage.stageKey]!)
                  _itemBlock(item, last: si == _stages.length - 1),
              ],
              AccountsV2Section(_t('v2m_reason')),
              AccountsV2TextField(
                key: const ValueKey('v2m_reason'),
                label: _t('v2m_reason'),
                hint: _t('v2m_reason_hint'),
                controller: _reason,
                enabled: !_saving,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AccountsV2Note(
                  tone: AccountsV2NoteTone.bad,
                  child: Text(_error!),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AccountsV2Colors.line)),
          ),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AccountsV2Button(
                label: _t('v2_cancel'),
                kind: AccountsV2ButtonKind.ghost,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
              AccountsV2Button(
                key: const ValueKey('v2m_save'),
                label: _saving ? _t('v2_saving') : _t('v2m_save'),
                icon: 'check',
                kind: AccountsV2ButtonKind.primary,
                onPressed: canSave ? _save : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemBlock(_LinkItem item, {required bool last}) {
    final buildings = item.buildingIds.length;
    return Container(
      key: ValueKey('v2m_item_${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: v2Style(13.5, weight: FontWeight.w700),
                ),
              ),
              Text(
                '${item.quantity.displayText(maximumFractionDigits: 2)} '
                '${item.unit}',
                style: v2Style(
                  12.5,
                  color: AccountsV2Colors.ink2,
                  tabular: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _folders.names.keys)
                _FolderChoice(
                  key: ValueKey('v2m_choice_${item.id}_$name'),
                  label: _folders.names[name]!,
                  detail: _folders.buildingCount(name) < buildings
                      ? '${_folders.buildingCount(name)}/$buildings'
                      : null,
                  selected: _chosen[item.id]!.contains(name),
                  usedBy: _usedBy(item, name)?.label,
                  usedByLabel: _t('v2m_used_by'),
                  onTap: _saving ? null : () => _toggle(item, name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A folder name that can be picked for an item; greyed out while another
/// item of the stage stands for it.
class _FolderChoice extends StatelessWidget {
  const _FolderChoice({
    super.key,
    required this.label,
    required this.detail,
    required this.selected,
    required this.usedBy,
    required this.usedByLabel,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final bool selected;
  final String? usedBy;
  final String usedByLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final blocked = usedBy != null && !selected;
    final phone = AccountsV2Breakpoints.isPhone(context);
    final fg = selected
        ? AccountsV2Colors.pri
        : blocked
        ? AccountsV2Colors.mut
        : AccountsV2Colors.ink;
    final chip = Semantics(
      button: true,
      selected: selected,
      enabled: !blocked && onTap != null,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: blocked ? null : onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: phone ? 44 : 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AccountsV2Colors.pri50 : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AccountsV2Colors.pri
                  : AccountsV2Colors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountsV2Icon(
                selected ? 'check' : 'folder',
                size: 14,
                color: fg,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: v2Style(12.5, weight: FontWeight.w600, color: fg),
                ),
              ),
              if (detail != null) ...[
                const SizedBox(width: 6),
                Text(
                  detail!,
                  style: v2Style(11.5, color: AccountsV2Colors.mut),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return blocked
        ? Tooltip(message: '$usedByLabel $usedBy', child: chip)
        : chip;
  }
}
