import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'revenue_share_model.dart';

// ---------------------------------------------------------------------------
// Provider — nullable: null means no active config for the patient
// ---------------------------------------------------------------------------

final revenueShareProvider =
    AsyncNotifierProvider.family<RevenueShareNotifier, RevenueShareConfig?, String>(
  RevenueShareNotifier.new,
);

class RevenueShareNotifier
    extends FamilyAsyncNotifier<RevenueShareConfig?, String> {
  @override
  Future<RevenueShareConfig?> build(String patientId) async {
    final repo = ref.watch(patientsRepositoryProvider);
    try {
      return await repo.getRevenueShare(patientId);
    } catch (_) {
      // 404 = no active config
      return null;
    }
  }

  Future<void> save(String patientId, RevenueShareDto dto) async {
    final repo = ref.read(patientsRepositoryProvider);
    final config = await repo.saveRevenueShare(patientId, dto);
    state = AsyncData(config);
  }

  Future<void> deactivate(String patientId) async {
    final repo = ref.read(patientsRepositoryProvider);
    await repo.deleteRevenueShare(patientId);
    state = const AsyncData(null);
  }
}
