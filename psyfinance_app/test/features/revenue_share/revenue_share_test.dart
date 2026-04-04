import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'package:psyfinance_app/features/patients/patients_repository.dart';
import 'package:psyfinance_app/features/revenue_share/revenue_share_model.dart';
import 'package:psyfinance_app/features/revenue_share/revenue_share_provider.dart';

// ---------------------------------------------------------------------------
// Unit tests — computeRevenueShare
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // PERCENTAGE
  // -------------------------------------------------------------------------

  group('computeRevenueShare — PERCENTAGE', () {
    final config = RevenueShareConfig(
      id: 'c1',
      patientId: 'p1',
      shareType: ShareType.percentage,
      shareValue: 15,
      beneficiaryName: 'Supervisora Ar',
      active: true,
    );

    test('calculates 15% of expectedAmount correctly', () {
      expect(computeRevenueShare(1000, 4, config), closeTo(150.0, 0.001));
    });

    test('scales with different expectedAmount', () {
      expect(computeRevenueShare(500, 4, config), closeTo(75.0, 0.001));
    });

    test('decimal shareValue is handled', () {
      final dec = RevenueShareConfig(
        id: 'c2',
        patientId: 'p1',
        shareType: ShareType.percentage,
        shareValue: 12.5,
        beneficiaryName: 'Super',
        active: true,
      );
      expect(computeRevenueShare(800, 4, dec), closeTo(100.0, 0.001));
    });

    test('returns 0 when config is inactive', () {
      final inactive = RevenueShareConfig(
        id: 'c3',
        patientId: 'p1',
        shareType: ShareType.percentage,
        shareValue: 20,
        beneficiaryName: 'X',
        active: false,
      );
      expect(computeRevenueShare(1000, 4, inactive), 0.0);
    });
  });

  // -------------------------------------------------------------------------
  // FIXED_PER_SESSION
  // -------------------------------------------------------------------------

  group('computeRevenueShare — FIXED_PER_SESSION', () {
    final config = RevenueShareConfig(
      id: 'c4',
      patientId: 'p1',
      shareType: ShareType.fixedPerSession,
      shareValue: 30,
      beneficiaryName: 'Supervisora Ar',
      active: true,
    );

    test('multiplies shareValue by sessionCount', () {
      expect(computeRevenueShare(0, 4, config), closeTo(120.0, 0.001));
    });

    test('zero sessions yields zero', () {
      expect(computeRevenueShare(0, 0, config), 0.0);
    });

    test('ignores expectedAmount (only uses sessionCount)', () {
      expect(computeRevenueShare(9999, 3, config), closeTo(90.0, 0.001));
    });

    test('returns 0 when config is inactive', () {
      final inactive = RevenueShareConfig(
        id: 'c5',
        patientId: 'p1',
        shareType: ShareType.fixedPerSession,
        shareValue: 30,
        beneficiaryName: 'X',
        active: false,
      );
      expect(computeRevenueShare(0, 4, inactive), 0.0);
    });
  });

  // -------------------------------------------------------------------------
  // Model parsing
  // -------------------------------------------------------------------------

  group('RevenueShareConfig.fromJson', () {
    test('parses PERCENTAGE correctly', () {
      final json = {
        'id': 'abc',
        'patientId': 'p1',
        'shareType': 'PERCENTAGE',
        'shareValue': 15.0,
        'beneficiaryName': 'Supervisora',
        'active': true,
      };
      final config = RevenueShareConfig.fromJson(json);
      expect(config.shareType, ShareType.percentage);
      expect(config.shareValue, 15.0);
      expect(config.beneficiaryName, 'Supervisora');
      expect(config.active, true);
    });

    test('parses FIXED_PER_SESSION correctly', () {
      final json = {
        'id': 'abc',
        'patientId': 'p1',
        'shareType': 'FIXED_PER_SESSION',
        'shareValue': 30,
        'beneficiaryName': 'Co-therapist',
        'active': true,
      };
      final config = RevenueShareConfig.fromJson(json);
      expect(config.shareType, ShareType.fixedPerSession);
      expect(config.shareValue, 30.0);
    });
  });

  // -------------------------------------------------------------------------
  // Provider — deactivating removes the configured state
  // -------------------------------------------------------------------------

  group('RevenueShareNotifier — deactivate', () {
    test('state becomes null after deactivate is called', () async {
      final initialConfig = RevenueShareConfig(
        id: 'c1',
        patientId: 'p1',
        shareType: ShareType.percentage,
        shareValue: 15,
        beneficiaryName: 'Super',
        active: true,
      );

      final fakeRepo = _FakePatientsRepository(initialConfig);

      final container = ProviderContainer(
        overrides: [
          patientsRepositoryProvider.overrideWith((_) => fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      // Initial state: config present
      final initial =
          await container.read(revenueShareProvider('p1').future);
      expect(initial, isNotNull);
      expect(initial!.shareType, ShareType.percentage);

      // Deactivate
      await container
          .read(revenueShareProvider('p1').notifier)
          .deactivate('p1');

      final after =
          await container.read(revenueShareProvider('p1').future);
      expect(after, isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake repository — no HTTP, returns in-memory state
// ---------------------------------------------------------------------------

class _FakePatientsRepository extends PatientsRepository {
  RevenueShareConfig? _config;

  _FakePatientsRepository(this._config)
      : super(ApiClient(baseUrl: 'http://localhost:0'));

  @override
  Future<RevenueShareConfig?> getRevenueShare(String patientId) async =>
      _config;

  @override
  Future<void> deleteRevenueShare(String patientId) async {
    _config = null;
  }
}
