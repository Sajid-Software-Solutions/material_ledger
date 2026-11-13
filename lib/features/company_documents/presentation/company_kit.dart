/// Company documents — shared pieces. The surfaces, pills, metric cards and
/// date helpers are the People ones, so both sections read alike.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_company_documents.dart';
import '../../../shared/models/yorks_v1_company_documents_strings.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../people_records/presentation/people_kit.dart';

export '../../people_records/presentation/people_kit.dart'
    show
        PS,
        PeopleFact,
        PeopleMessage,
        PeopleMetricCard,
        PeoplePill,
        PeopleSectionHeading,
        PeopleStatusPill,
        PeopleSurface,
        peopleDate,
        peopleStamp,
        peopleStatusColors,
        peopleStatusLabel,
        peopleToast;

typedef CS = CompanyStrings;

const companyPath = '/yorks/company-documents';
const companyNewPath = '/yorks/company-documents/new';
String companyNewKindPath(CompanyRecordKind kind) =>
    '$companyNewPath?kind=${kind.wire}';
String companyRecordPath(String id) => '/yorks/company-documents/$id';
String companyEditPath(String id) => '/yorks/company-documents/$id/edit';

String companyKindLabel(CompanyRecordKind kind, AppLanguage language) =>
    CS.t(switch (kind) {
      CompanyRecordKind.entity => CS.kindEntity,
      CompanyRecordKind.item => CS.kindItem,
      CompanyRecordKind.vehicle => CS.kindVehicle,
      CompanyRecordKind.policy => CS.kindPolicy,
      CompanyRecordKind.contract => CS.kindContract,
    }, language);

IconData companyKindIcon(CompanyRecordKind kind) => switch (kind) {
  CompanyRecordKind.entity => Icons.apartment_outlined,
  CompanyRecordKind.item => Icons.workspace_premium_outlined,
  CompanyRecordKind.vehicle => Icons.directions_car_outlined,
  CompanyRecordKind.policy => Icons.health_and_safety_outlined,
  CompanyRecordKind.contract => Icons.handshake_outlined,
};

({Color color, Color background}) companyKindColors(CompanyRecordKind kind) =>
    switch (kind) {
      CompanyRecordKind.entity => (
        color: AppColors.blue,
        background: AppColors.blueContainer,
      ),
      CompanyRecordKind.item => (
        color: AppColors.purple,
        background: AppColors.purpleContainer,
      ),
      CompanyRecordKind.vehicle => (
        color: AppColors.success,
        background: AppColors.successContainer,
      ),
      CompanyRecordKind.policy => (
        color: AppColors.warning,
        background: AppColors.warningContainer,
      ),
      CompanyRecordKind.contract => (
        color: AppColors.neutralText,
        background: AppColors.neutralContainer,
      ),
    };

String companyDocumentKindLabel(
  CompanyDocumentKind kind,
  AppLanguage language,
) => CS.t(switch (kind) {
  CompanyDocumentKind.licence => CS.docLicence,
  CompanyDocumentKind.establishmentCard => CS.docEstablishment,
  CompanyDocumentKind.labourFile => CS.docLabourFile,
  CompanyDocumentKind.proCard => CS.docProCard,
  CompanyDocumentKind.registration => CS.docRegistration,
  CompanyDocumentKind.asateelPermit => CS.docAsateel,
  CompanyDocumentKind.cicpaPass => CS.docCicpa,
  CompanyDocumentKind.insurance => CS.docInsurance,
  CompanyDocumentKind.contract => CS.docContract,
  CompanyDocumentKind.certificate => CS.docCertificate,
  CompanyDocumentKind.other => CS.docOther,
}, language);

/// A document's name: its own label when it has one ("PRO card Ahmad"),
/// otherwise its kind. A tracker column label ("Value 2") keeps the kind.
String companyDocumentLabel(
  CompanyDocumentKind kind,
  AppLanguage language, {
  String? label,
}) {
  final kindLabel = companyDocumentKindLabel(kind, language);
  if (label == null || label.isEmpty) return kindLabel;
  if (RegExp(r'^Value \d+$').hasMatch(label)) return '$kindLabel · $label';
  return label;
}

IconData companyDocumentIcon(CompanyDocumentKind kind) => switch (kind) {
  CompanyDocumentKind.licence => Icons.storefront_outlined,
  CompanyDocumentKind.establishmentCard => Icons.badge_outlined,
  CompanyDocumentKind.labourFile => Icons.folder_shared_outlined,
  CompanyDocumentKind.proCard => Icons.contact_mail_outlined,
  CompanyDocumentKind.registration => Icons.directions_car_outlined,
  CompanyDocumentKind.asateelPermit => Icons.local_shipping_outlined,
  CompanyDocumentKind.cicpaPass => Icons.verified_user_outlined,
  CompanyDocumentKind.insurance => Icons.health_and_safety_outlined,
  CompanyDocumentKind.contract => Icons.handshake_outlined,
  CompanyDocumentKind.certificate => Icons.workspace_premium_outlined,
  CompanyDocumentKind.other => Icons.description_outlined,
};

String companyReferenceLabel(CompanyRecordKind kind, AppLanguage language) =>
    CS.t(switch (kind) {
      CompanyRecordKind.entity => CS.refLicence,
      CompanyRecordKind.vehicle => CS.refPlate,
      CompanyRecordKind.policy => CS.refPolicy,
      CompanyRecordKind.contract => CS.refLoa,
      CompanyRecordKind.item => CS.refOther,
    }, language);

String companyOwnerLabel(CompanyRecordKind kind, AppLanguage language) => CS.t(
  kind == CompanyRecordKind.vehicle ? CS.ownerVehicle : CS.owner,
  language,
);

/// "12 days left", "Expired 3 days ago", "Expires today" or "No expiry".
String companyDaysText(int? days, AppLanguage language) {
  if (days == null) return PS.t(PS.noExpiry, language);
  if (days == 0) return PS.t(PS.expiresToday, language);
  if (days < 0) return PS.t(PS.expiredAgo, language, {'n': -days});
  return PS.t(PS.daysLeft, language, {'n': days});
}

String companyErrorText(Object? error, AppLanguage language) {
  if (error is YorksV1DomainException &&
      (error.code == YorksV1DomainErrorCode.unauthorized ||
          error.code == YorksV1DomainErrorCode.unauthenticated)) {
    return CS.t(CS.errDenied, language);
  }
  return peopleErrorText(error, language);
}

/// An expiry date coloured by how soon it ends; a number when the document
/// has no expiry (a labour file); a dash when nothing is held.
class CompanyExpiryCell extends StatelessWidget {
  const CompanyExpiryCell({
    super.key,
    required this.document,
    required this.language,
    this.dense = false,
  });

  final CompanyDocument? document;
  final AppLanguage language;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    if (doc == null) {
      return Text(
        '—',
        style: AppTypography.bodySmall.copyWith(color: AppColors.mutedLight),
      );
    }
    final colors = peopleStatusColors(doc.status);
    final text = doc.expiryDate == null
        ? (doc.number ?? PS.t(PS.noExpiry, language))
        : peopleDate(doc.expiryDate);
    return Tooltip(
      message: [
        companyDocumentLabel(doc.kind, language, label: doc.label),
        if (doc.number != null) doc.number!,
        companyDaysText(doc.daysLeft, language),
      ].join(' · '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (dense ? AppTypography.labelMedium : AppTypography.bodySmall)
                      .copyWith(
                        color: doc.status.needsAttention
                            ? colors.color
                            : AppColors.ink,
                        fontWeight: doc.status.needsAttention
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
