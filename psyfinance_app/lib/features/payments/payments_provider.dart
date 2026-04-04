import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'payment_model.dart';
import 'payments_repository.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
  (ref) => PaymentsRepository(ref.watch(apiClientProvider)),
);

final paymentProvider =
    AsyncNotifierProvider.family<PaymentNotifier, Payment, String>(
  PaymentNotifier.new,
);

class PaymentNotifier extends FamilyAsyncNotifier<Payment, String> {
  @override
  Future<Payment> build(String sessionRecordId) =>
      ref.read(paymentsRepositoryProvider).getPayment(sessionRecordId);
}
