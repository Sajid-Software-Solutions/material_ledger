/// Configuration workspace — what `v1_cfg_get_workspace` returns
/// (docs/yorks-v1/CONFIGURATION_REDESIGN_PLAN.md).
library;

String _s(Object? value) => value?.toString() ?? '';
int _i(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
bool _b(Object? value) => value == true;
List<Map<String, dynamic>> _list(Object? value) => [
  for (final item in (value as List? ?? const []))
    Map<String, dynamic>.from(item as Map),
];
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

/// Sections of Configuration, in reading order.
enum ConfigSection {
  checklist('checklist'),
  company('company'),
  projects('projects'),
  requests('requests'),
  inventory('inventory'),
  accounts('accounts'),
  workforce('workforce'),
  rentals('rentals'),
  notifications('notifications'),
  access('access'),
  numbering('numbering'),
  history('history');

  const ConfigSection(this.wire);
  final String wire;

  static ConfigSection? from(String? value) {
    for (final section in values) {
      if (section.wire == value) return section;
    }
    return null;
  }
}

final class ConfigSetting {
  const ConfigSetting({
    required this.key,
    required this.value,
    required this.mode,
  });

  final String key;
  final Object? value;

  /// `operational` (editable here), `protected` (a fixed fact) or `planned`
  /// (not in use; never shown).
  final String mode;

  String get text => value?.toString() ?? '';
  bool get flag => value == true;
}

final class ConfigListItem {
  const ConfigListItem({
    required this.id,
    required this.name,
    required this.active,
    this.code = '',
    this.system = false,
    this.order = 0,
    this.usage = 0,
    this.aliases = const [],
    this.extra = const {},
  });

  final String id;
  final String name;
  final bool active;
  final String code;
  final bool system;
  final int order;

  /// How many records use it (folders created from a template).
  final int usage;
  final List<String> aliases;
  final Map<String, dynamic> extra;
}

final class ConfigStage {
  const ConfigStage({
    required this.key,
    required this.name,
    required this.percent,
    required this.active,
  });

  final String? key;
  final String name;
  final String percent;
  final bool active;
}

final class ConfigChecks {
  const ConfigChecks({
    this.bankMissing = false,
    this.trnMissing = false,
    this.pushOff = false,
    this.holidaysThisYear = 0,
    this.activePrUsers = 0,
    this.defaultFolders = 0,
    this.rentalsOff = false,
  });

  factory ConfigChecks.fromJson(Map<String, dynamic> json) => ConfigChecks(
    bankMissing: _b(json['bank_missing']),
    trnMissing: _b(json['trn_missing']),
    pushOff: _b(json['push_off']),
    holidaysThisYear: _i(json['holidays_this_year']),
    activePrUsers: _i(json['active_pr_users']),
    defaultFolders: _i(json['default_folders']),
    rentalsOff: _b(json['rentals_off']),
  );

  final bool bankMissing;
  final bool trnMissing;
  final bool pushOff;
  final int holidaysThisYear;
  final int activePrUsers;
  final int defaultFolders;
  final bool rentalsOff;
}

final class ConfigWorkspace {
  const ConfigWorkspace({
    required this.version,
    required this.today,
    required this.editable,
    required this.settings,
    required this.boqTemplates,
    required this.inventoryCategories,
    required this.units,
    required this.mrCategories,
    required this.mrDepartments,
    required this.checks,
    this.paymentTermsDays,
    this.reminderLeadDays,
    this.stages = const [],
    this.rentalsEnabled = false,
    this.rentalsPush = false,
    this.rentalsLastRun,
    this.weeklyOffDays = const ['sunday'],
  });

  factory ConfigWorkspace.fromJson(Map<String, dynamic> json) {
    final accounts = _map(json['accounts']);
    final rentals = _map(json['rentals']);
    final editable = _map(json['editable']);
    return ConfigWorkspace(
      version: _i(json['version']),
      today: _s(json['today']),
      editable: {
        for (final entry in editable.entries)
          if (entry.value == true) entry.key,
      },
      settings: {
        for (final entry in _map(json['settings']).entries)
          entry.key: ConfigSetting(
            key: entry.key,
            value: _map(entry.value)['value'],
            mode: _s(_map(entry.value)['mode']),
          ),
      },
      boqTemplates: [
        for (final item in _list(json['boq_templates']))
          ConfigListItem(
            id: _s(item['id']),
            name: _s(item['name']),
            code: _s(item['key']),
            active: _b(item['active']),
            order: _i(item['order']),
            usage: _i(item['scopes']),
          ),
      ],
      inventoryCategories: [
        for (final item in _list(json['inventory_categories']))
          ConfigListItem(
            id: _s(item['id']),
            name: _s(item['name']),
            active: _b(item['active']),
            system: _b(item['system']),
            aliases: [
              for (final alias in (item['aliases'] as List? ?? const []))
                alias.toString(),
            ],
            extra: {'parent_id': item['parent_id']},
          ),
      ],
      units: [
        for (final item in _list(json['units']))
          ConfigListItem(
            id: _s(item['id']),
            name: _s(item['name']),
            code: _s(item['code']),
            active: _b(item['active']),
            system: _b(item['system']),
            extra: {'type': item['type'], 'decimals': item['decimals']},
          ),
      ],
      mrCategories: [
        for (final item in _list(json['mr_categories']))
          ConfigListItem(
            id: _s(item['id']),
            name: _s(item['name']),
            code: _s(item['code']),
            active: _b(item['active']),
          ),
      ],
      mrDepartments: [
        for (final item in _list(json['mr_departments']))
          ConfigListItem(
            id: _s(item['id']),
            name: _s(item['name']),
            code: _s(item['code']),
            active: _b(item['active']),
          ),
      ],
      paymentTermsDays: accounts['payment_terms_days'] == null
          ? null
          : _i(accounts['payment_terms_days']),
      reminderLeadDays: accounts['reminder_lead_days'] == null
          ? null
          : _i(accounts['reminder_lead_days']),
      stages: [
        for (final item in _list(accounts['stages']))
          ConfigStage(
            key: _s(item['key']),
            name: _s(item['name']),
            percent: _trimPercent(_s(item['percent'])),
            active: _b(item['active']),
          ),
      ],
      rentalsEnabled: _b(rentals['enabled']),
      rentalsPush: _b(rentals['push']),
      rentalsLastRun: rentals['last_run_at'] == null
          ? null
          : DateTime.tryParse('${rentals['last_run_at']}')?.toLocal(),
      checks: ConfigChecks.fromJson(_map(json['checks'])),
      weeklyOffDays: json['weekly_off_days'] is List
          ? [for (final day in json['weekly_off_days'] as List) day.toString()]
          : const ['sunday'],
    );
  }

  final int version;
  final String today;
  final Set<String> editable;
  final Map<String, ConfigSetting> settings;
  final List<ConfigListItem> boqTemplates;
  final List<ConfigListItem> inventoryCategories;
  final List<ConfigListItem> units;
  final List<ConfigListItem> mrCategories;
  final List<ConfigListItem> mrDepartments;
  final int? paymentTermsDays;
  final int? reminderLeadDays;
  final List<ConfigStage> stages;
  final bool rentalsEnabled;
  final bool rentalsPush;
  final DateTime? rentalsLastRun;
  final ConfigChecks checks;

  /// Weekday names (`sunday`, …) that are off; work on them is holiday
  /// overtime.
  final List<String> weeklyOffDays;

  bool canEdit(ConfigSection section) => editable.contains(section.wire);

  /// Admin sees every section; PR sees Workforce and Rentals.
  bool get isAdmin => editable.contains('company');

  ConfigSetting? setting(String key) => settings[key];
  String text(String key) => settings[key]?.text ?? '';
  bool flag(String key, {bool fallback = false}) =>
      settings[key] == null ? fallback : settings[key]!.flag;
}

/// "10.0000" -> "10", "12.5000" -> "12.5".
String _trimPercent(String value) {
  if (!value.contains('.')) return value;
  var result = value.replaceFirst(RegExp(r'0+$'), '');
  if (result.endsWith('.')) result = result.substring(0, result.length - 1);
  return result;
}

/// One change sent to `v1_cfg_apply`.
final class ConfigChange {
  const ConfigChange(this.json, {required this.label, this.before, this.after});

  final Map<String, Object?> json;

  /// For the review sheet: what changes, before -> after.
  final String label;
  final String? before;
  final String? after;

  static ConfigChange setting(
    String key,
    Object? value, {
    required String label,
    String? before,
  }) => ConfigChange(
    {'kind': 'setting', 'key': key, 'value': value},
    label: label,
    before: before,
    after: value?.toString(),
  );
}
