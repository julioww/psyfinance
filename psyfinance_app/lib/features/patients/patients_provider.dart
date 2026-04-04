import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/core/api_client.dart';
import 'patient_model.dart';
import 'patient_summary_model.dart';
import 'patients_repository.dart';

// ---------------------------------------------------------------------------
// Shared ApiClient + Repository providers
// ---------------------------------------------------------------------------

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final patientsRepositoryProvider = Provider<PatientsRepository>(
  (ref) => PatientsRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------

class PatientsFilter {
  final String statusFilter; // 'ATIVO' | 'INATIVO' | 'all'
  final String? location;
  final String? currency;
  final String? paymentModel;
  final String query;

  const PatientsFilter({
    this.statusFilter = 'ATIVO',
    this.location,
    this.currency,
    this.paymentModel,
    this.query = '',
  });

  PatientsFilter copyWith({
    String? statusFilter,
    Object? location = _sentinel,
    Object? currency = _sentinel,
    Object? paymentModel = _sentinel,
    String? query,
  }) =>
      PatientsFilter(
        statusFilter: statusFilter ?? this.statusFilter,
        location: location == _sentinel ? this.location : location as String?,
        currency: currency == _sentinel ? this.currency : currency as String?,
        paymentModel: paymentModel == _sentinel ? this.paymentModel : paymentModel as String?,
        query: query ?? this.query,
      );

  bool get hasActiveNonDefaultFilters =>
      statusFilter != 'ATIVO' ||
      location != null ||
      currency != null ||
      paymentModel != null ||
      query.isNotEmpty;
}

// Sentinel for nullable copyWith
const Object _sentinel = Object();

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PatientsNotifier extends AsyncNotifier<List<Patient>> {
  PatientsFilter _filter = const PatientsFilter();

  PatientsFilter get filter => _filter;

  @override
  Future<List<Patient>> build() => _fetch();

  Future<List<Patient>> _fetch() {
    final repo = ref.read(patientsRepositoryProvider);
    return repo.getPatients(
      status: _filter.statusFilter,
      location: _filter.location,
      currency: _filter.currency,
      paymentModel: _filter.paymentModel,
      q: _filter.query.isEmpty ? null : _filter.query,
    );
  }

  Future<void> applyFilter(PatientsFilter filter) async {
    _filter = filter;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> createPatient(CreatePatientDto dto) async {
    await ref.read(patientsRepositoryProvider).createPatient(dto);
    await refresh();
  }

  Future<void> updatePatient(String id, UpdatePatientDto dto) async {
    await ref.read(patientsRepositoryProvider).updatePatient(id, dto);
    await refresh();
  }

  Future<void> archivePatient(String id) async {
    await ref.read(patientsRepositoryProvider).archivePatient(id);
    await refresh();
  }
}

final patientsProvider = AsyncNotifierProvider<PatientsNotifier, List<Patient>>(
  PatientsNotifier.new,
);

// ---------------------------------------------------------------------------
// Patient summary (detail screen)
// ---------------------------------------------------------------------------

typedef PatientSummaryArgs = ({String patientId, int year});

final patientSummaryProvider = AsyncNotifierProvider.family<
    PatientSummaryNotifier, PatientSummary, PatientSummaryArgs>(
  PatientSummaryNotifier.new,
);

class PatientSummaryNotifier
    extends FamilyAsyncNotifier<PatientSummary, PatientSummaryArgs> {
  @override
  Future<PatientSummary> build(PatientSummaryArgs arg) =>
      ref.watch(patientsRepositoryProvider).getPatientSummary(arg.patientId, arg.year);
}
