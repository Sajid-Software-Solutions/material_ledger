import 'dart:convert';

/// Employment status of a roster employee.
enum EmployeeStatus {
  active('Active', 'نشط', 'فعال', 'सक्रिय'),
  onLeave('On Leave', 'في إجازة', 'چھٹی پر', 'अवकाश पर'),
  inactive('Inactive', 'غير نشط', 'غیر فعال', 'निष्क्रिय');

  const EmployeeStatus(this.label, this.ar, this.ur, this.hi);
  final String label;
  final String ar;
  final String ur;
  final String hi;

  static EmployeeStatus fromName(String n) => EmployeeStatus.values.firstWhere(
    (s) => s.name == n,
    orElse: () => active,
  );
}

/// A roster employee in the People / HR module (FR-124). Salary and document
/// fields are restricted to Admin in the UI and Security Rules (FR-128);
/// procurement manages the roster but not compensation.
class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    required this.jobRole,
    required this.department,
    required this.nationality,
    this.contact,
    this.emiratesId,
    this.emiratesIdExpiry,
    this.passportNo,
    this.passportExpiry,
    this.visaExpiry,
    this.joinDate,
    this.salaryAED,
    this.basicWageAED,
    this.documents = const [],
    this.status = EmployeeStatus.active,
  });

  final String id;
  final String fullName;
  final String jobRole;
  final String department;
  final String nationality;
  final String? contact;

  // ── Restricted (Admin only) ──
  final String? emiratesId;
  final DateTime? emiratesIdExpiry;
  final String? passportNo;
  final DateTime? passportExpiry;
  final DateTime? visaExpiry;
  final DateTime? joinDate;
  final double? salaryAED;

  /// Monthly BASIC wage (excludes housing/transport/other allowances) — the
  /// figure UAE end-of-service gratuity is calculated on (Art. 51). Falls back
  /// to [salaryAED] when not set separately, since many small employers only
  /// track one figure; set this explicitly for an accurate gratuity estimate.
  final double? basicWageAED;

  final List<String> documents;

  final EmployeeStatus status;

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Monthly basic wage used for gratuity — falls back to [salaryAED] when
  /// [basicWageAED] wasn't set separately.
  double? get effectiveBasicWageAED => basicWageAED ?? salaryAED;

  Employee copyWith({
    String? fullName,
    String? jobRole,
    String? department,
    String? nationality,
    String? contact,
    String? emiratesId,
    DateTime? emiratesIdExpiry,
    String? passportNo,
    DateTime? passportExpiry,
    DateTime? visaExpiry,
    DateTime? joinDate,
    double? salaryAED,
    double? basicWageAED,
    List<String>? documents,
    EmployeeStatus? status,
  }) => Employee(
    id: id,
    fullName: fullName ?? this.fullName,
    jobRole: jobRole ?? this.jobRole,
    department: department ?? this.department,
    nationality: nationality ?? this.nationality,
    contact: contact ?? this.contact,
    emiratesId: emiratesId ?? this.emiratesId,
    emiratesIdExpiry: emiratesIdExpiry ?? this.emiratesIdExpiry,
    passportNo: passportNo ?? this.passportNo,
    passportExpiry: passportExpiry ?? this.passportExpiry,
    visaExpiry: visaExpiry ?? this.visaExpiry,
    joinDate: joinDate ?? this.joinDate,
    salaryAED: salaryAED ?? this.salaryAED,
    basicWageAED: basicWageAED ?? this.basicWageAED,
    documents: documents ?? this.documents,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'jobRole': jobRole,
    'department': department,
    'nationality': nationality,
    'contact': contact,
    'emiratesId': emiratesId,
    'emiratesIdExpiry': emiratesIdExpiry?.toIso8601String(),
    'passportNo': passportNo,
    'passportExpiry': passportExpiry?.toIso8601String(),
    'visaExpiry': visaExpiry?.toIso8601String(),
    'joinDate': joinDate?.toIso8601String(),
    'salaryAED': salaryAED,
    'basicWageAED': basicWageAED,
    'documents': documents,
    'status': status.name,
  };

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
    id: json['id'] as String? ?? '',
    fullName: json['fullName'] as String? ?? '',
    jobRole: json['jobRole'] as String? ?? '',
    department: json['department'] as String? ?? '',
    nationality: json['nationality'] as String? ?? '',
    contact: json['contact'] as String?,
    emiratesId: json['emiratesId'] as String?,
    emiratesIdExpiry: DateTime.tryParse(
      json['emiratesIdExpiry'] as String? ?? '',
    ),
    passportNo: json['passportNo'] as String?,
    passportExpiry: DateTime.tryParse(json['passportExpiry'] as String? ?? ''),
    visaExpiry: DateTime.tryParse(json['visaExpiry'] as String? ?? ''),
    joinDate: DateTime.tryParse(json['joinDate'] as String? ?? ''),
    salaryAED: (json['salaryAED'] as num?)?.toDouble(),
    basicWageAED: (json['basicWageAED'] as num?)?.toDouble(),
    documents:
        (json['documents'] as List<dynamic>?)?.cast<String>() ?? const [],
    status: EmployeeStatus.fromName(json['status'] as String? ?? 'active'),
  );

  static String encodeList(List<Employee> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<Employee> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => Employee.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
