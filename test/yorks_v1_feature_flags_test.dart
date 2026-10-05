import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/nexus_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/providers/nexus_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';

void main() {
  group('Yorks V1 feature flags', () {
    test('project setup requires projects and stays off by default', () {
      expect(const YorksV1FeatureFlags.fromEnvironment().projectSetup, false);
      expect(const YorksV1FeatureFlags(projectSetup: true).projectSetup, false);
      expect(
        const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          projectSetup: true,
        ).projectSetup,
        true,
      );
    });
    test('all features default off', () {
      const flags = YorksV1FeatureFlags();

      expect(flags.foundation, false);
      expect(flags.projects, false);
      expect(flags.boq, false);
      expect(flags.excel, false);
      expect(flags.requests, false);
      expect(flags.arrangement, false);
      expect(flags.legacyArrangementReview, false);
      expect(flags.logistics, false);
      expect(flags.returnsDocuments, false);
      expect(flags.documents, false);
      expect(flags.accounts, false);
      expect(flags.workforce, false);
      expect(flags.analytics, false);
      expect(flags.inventorySuppliers, false);
      expect(flags.companyMaterialRequests, false);
    });

    test('downstream settings fail closed when foundation is disabled', () {
      const flags = YorksV1FeatureFlags(
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        returnsDocuments: true,
        documents: true,
      );

      expect(flags.foundation, false);
      expect(flags.projects, false);
      expect(flags.boq, false);
      expect(flags.excel, false);
      expect(flags.requests, false);
      expect(flags.arrangement, false);
      expect(flags.legacyArrangementReview, false);
      expect(flags.logistics, false);
      expect(flags.returnsDocuments, false);
      expect(flags.documents, false);
      expect(flags.accounts, false);
      expect(flags.workforce, false);
      expect(flags.analytics, false);
      expect(flags.inventorySuppliers, false);
      expect(flags.companyMaterialRequests, false);
    });

    test('a missing intermediate dependency closes every later feature', () {
      const flags = YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        returnsDocuments: true,
        documents: true,
      );

      expect(flags.foundation, true);
      expect(flags.projects, true);
      expect(flags.boq, false);
      expect(flags.excel, false);
      expect(flags.requests, false);
      expect(flags.arrangement, false);
      expect(flags.legacyArrangementReview, false);
      expect(flags.logistics, false);
      expect(flags.returnsDocuments, false);
      expect(flags.documents, false);
      expect(flags.accounts, false);
      expect(flags.workforce, false);
      expect(flags.analytics, false);
      expect(flags.inventorySuppliers, false);
      expect(flags.companyMaterialRequests, false);
    });

    test('the complete approved dependency chain can be enabled', () {
      const flags = YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        returnsDocuments: true,
        documents: true,
      );

      expect(flags.foundation, true);
      expect(flags.projects, true);
      expect(flags.boq, true);
      expect(flags.excel, true);
      expect(flags.requests, true);
      expect(flags.arrangement, true);
      expect(flags.legacyArrangementReview, false);
      expect(flags.logistics, true);
      expect(flags.returnsDocuments, true);
      expect(flags.documents, true);
      expect(flags.accounts, false);
      expect(flags.isCompleteR35, true);
    });

    test(
      'Accounts stays off by default and fails closed without documents',
      () {
        const defaultEnvironment = YorksV1FeatureFlags.fromEnvironment();
        const missingDocuments = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          accounts: true,
        );
        const complete = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          documents: true,
          accounts: true,
        );

        expect(defaultEnvironment.accounts, false);
        expect(missingDocuments.accounts, false);
        expect(complete.accounts, true);
        expect(complete.isCompleteR35, true);
      },
    );

    test(
      'Workforce stays off by default and fails closed without documents',
      () {
        const defaultEnvironment = YorksV1FeatureFlags.fromEnvironment();
        const missingDocuments = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          workforce: true,
        );
        const complete = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          documents: true,
          workforce: true,
        );

        expect(defaultEnvironment.workforce, false);
        expect(missingDocuments.workforce, false);
        expect(complete.workforce, true);
        expect(complete.isCompleteR35, true);
      },
    );

    test(
      'Analytics stays off by default and requires the protected document chain',
      () {
        const defaultEnvironment = YorksV1FeatureFlags.fromEnvironment();
        const missingDocuments = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          analytics: true,
        );
        const complete = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          arrangement: true,
          logistics: true,
          returnsDocuments: true,
          documents: true,
          analytics: true,
        );

        expect(defaultEnvironment.analytics, false);
        expect(missingDocuments.analytics, false);
        expect(complete.analytics, true);
      },
    );

    test('supplier folders require the secure document chain', () {
      const withoutDocuments = YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        inventorySuppliers: true,
      );
      const complete = YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        returnsDocuments: true,
        documents: true,
        inventorySuppliers: true,
      );

      expect(withoutDocuments.inventorySuppliers, false);
      expect(complete.inventorySuppliers, true);
    });

    test(
      'Company Material Requests default off and require the request chain',
      () {
        const withoutRequests = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          companyMaterialRequests: true,
        );
        const enabled = YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
          companyMaterialRequests: true,
        );

        expect(withoutRequests.companyMaterialRequests, false);
        expect(enabled.companyMaterialRequests, true);
      },
    );

    test('production defaults enable the complete Yorks chain', () {
      final container = ProviderContainer(
        overrides: [
          nexusFeatureFlagsProvider.overrideWithValue(
            const NexusFeatureFlags(
              projects: true,
              browseMaterials: true,
              phase1Planning: true,
              procurementReview: true,
              phase2Requests: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final flags = container.read(yorksV1FeatureFlagsProvider);

      expect(flags.foundation, true);
      expect(flags.projects, true);
      expect(flags.boq, true);
      expect(flags.excel, true);
      expect(flags.requests, true);
      expect(flags.arrangement, true);
      expect(flags.legacyArrangementReview, false);
      expect(flags.logistics, true);
      expect(flags.returnsDocuments, true);
      expect(flags.documents, true);
      expect(flags.accounts, false);
      expect(flags.workforce, false);
      expect(flags.companyMaterialRequests, false);
      expect(flags.isCompleteR35, true);
    });

    test('legacy Nexus provider is disabled by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final flags = container.read(nexusFeatureFlagsProvider);

      expect(flags.projects, false);
      expect(flags.browseMaterials, false);
      expect(flags.phase1Planning, false);
      expect(flags.procurementReview, false);
      expect(flags.phase2Requests, false);
    });
  });
}
