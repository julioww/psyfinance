import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'monthly_repository.dart';
import 'monthly_view_model.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final monthlyRepositoryProvider = Provider<MonthlyRepository>(
  (ref) => MonthlyRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Args typedef
// ---------------------------------------------------------------------------

typedef MonthlyArgs = ({int year, int month});

// ---------------------------------------------------------------------------
// StateNotifier — holds AsyncValue<MonthlyView> and supports in-place mutations
// ---------------------------------------------------------------------------

class MonthlyViewNotifier
    extends StateNotifier<AsyncValue<MonthlyView>> {
  final MonthlyRepository _repo;
  final MonthlyArgs _args;

  MonthlyViewNotifier(this._repo, this._args) : super(const AsyncLoading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.getMonthlyView(_args.year, _args.month),
    );
  }

  Future<void> refresh() => _load();

  /// Updates a single row's session record in-place after SessionEntrySheet saves.
  /// Triggers a full refresh so the session count and expectedAmount are accurate.
  Future<void> refreshAfterSessionSave() => _load();

  /// Updates a single row's payment in-place without a network round-trip.
  /// Recalculates summary totals from the updated local state.
  void updateRowPayment(
    String patientId,
    double amountPaid,
    String status,
  ) {
    final current = state.value;
    if (current == null) return;

    final updatedRows = current.patients.map((row) {
      if (row.patient.id != patientId) return row;
      final existingPayment = row.payment;
      final newPayment = existingPayment != null
          ? existingPayment.copyWith(amountPaid: amountPaid, status: status)
          : MonthlyPayment(
              id: '',
              amountPaid: amountPaid,
              status: status,
              revenueShareAmount: null,
            );
      return row.copyWith(payment: newPayment);
    }).toList();

    final newSummary = computeSummaryFromRows(updatedRows);
    state = AsyncData(current.copyWith(patients: updatedRows, summary: newSummary));
  }
}

// ---------------------------------------------------------------------------
// Provider — family by (year, month)
// ---------------------------------------------------------------------------

final monthlyViewProvider = StateNotifierProvider.family<
    MonthlyViewNotifier, AsyncValue<MonthlyView>, MonthlyArgs>(
  (ref, args) => MonthlyViewNotifier(ref.read(monthlyRepositoryProvider), args),
);
