import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'payment_panel_model.dart';
import 'payments_panel_repository.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final paymentsPanelRepositoryProvider = Provider<PaymentsPanelRepository>(
  (ref) => PaymentsPanelRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Args typedef
// ---------------------------------------------------------------------------

typedef PaymentPanelArgs = ({int year, int month});

// ---------------------------------------------------------------------------
// Sort order for status (ATRASADO first, PAGO last)
// ---------------------------------------------------------------------------

const _statusOrder = {
  'ATRASADO': 0,
  'PARCIAL': 1,
  'PENDENTE': 2,
  'PAGO': 3,
};

// ---------------------------------------------------------------------------
// StateNotifier — holds AsyncValue<PaymentPanel> and supports in-place updates
// ---------------------------------------------------------------------------

class PaymentPanelNotifier
    extends StateNotifier<AsyncValue<PaymentPanel>> {
  final PaymentsPanelRepository _repo;
  final PaymentPanelArgs _args;

  PaymentPanelNotifier(this._repo, this._args) : super(const AsyncLoading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.getPaymentPanel(_args.year, _args.month),
    );
  }

  Future<void> refresh() => _load();

  /// Updates a single row's payment in-place after a PUT call.
  /// Re-sorts rows and recomputes summary totals from updated local state.
  void updateRow(
    String sessionRecordId,
    double amountPaid,
    String status,
  ) {
    final current = state.value;
    if (current == null) return;

    final updatedRows = current.payments.map((row) {
      if (row.sessionRecord.id != sessionRecordId) return row;
      return row.copyWith(
        payment: row.payment.copyWith(amountPaid: amountPaid, status: status),
      );
    }).toList();

    // Re-sort to reflect updated status
    updatedRows.sort((a, b) {
      final oa = _statusOrder[a.payment.status] ?? 3;
      final ob = _statusOrder[b.payment.status] ?? 3;
      if (oa != ob) return oa.compareTo(ob);
      return a.patient.name.compareTo(b.patient.name);
    });

    final newSummary = computePanelSummaryFromRows(updatedRows);
    state = AsyncData(
        current.copyWith(payments: updatedRows, summary: newSummary));
  }
}

// ---------------------------------------------------------------------------
// Provider — family by (year, month)
// ---------------------------------------------------------------------------

final paymentPanelProvider = StateNotifierProvider.family<
    PaymentPanelNotifier, AsyncValue<PaymentPanel>, PaymentPanelArgs>(
  (ref, args) =>
      PaymentPanelNotifier(ref.read(paymentsPanelRepositoryProvider), args),
);
