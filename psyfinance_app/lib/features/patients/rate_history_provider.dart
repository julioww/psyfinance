import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'patients_provider.dart';
import 'rate_history_model.dart';

final rateHistoryProvider =
    AsyncNotifierProvider.family<RateHistoryNotifier, List<RateHistory>, String>(
  RateHistoryNotifier.new,
);

class RateHistoryNotifier extends FamilyAsyncNotifier<List<RateHistory>, String> {
  @override
  Future<List<RateHistory>> build(String patientId) {
    final repo = ref.watch(patientsRepositoryProvider);
    return repo.getRateHistory(patientId);
  }
}
