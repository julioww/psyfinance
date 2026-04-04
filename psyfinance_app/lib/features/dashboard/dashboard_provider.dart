import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'dashboard_model.dart';
import 'dashboard_repository.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Dashboard provider — keyed by year
// ---------------------------------------------------------------------------

class DashboardNotifier extends FamilyAsyncNotifier<DashboardData, int> {
  @override
  Future<DashboardData> build(int arg) =>
      ref.read(dashboardRepositoryProvider).getDashboard(arg);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dashboardRepositoryProvider).getDashboard(arg),
    );
  }
}

final dashboardProvider =
    AsyncNotifierProvider.family<DashboardNotifier, DashboardData, int>(
  DashboardNotifier.new,
);

// ---------------------------------------------------------------------------
// Comparison provider — fixed set of years
// ---------------------------------------------------------------------------

final _comparisonYears = [2023, 2024, 2025, 2026];

class ComparisonNotifier extends AsyncNotifier<List<YearlyComparison>> {
  @override
  Future<List<YearlyComparison>> build() =>
      ref.read(dashboardRepositoryProvider).getComparison(_comparisonYears);
}

final comparisonProvider =
    AsyncNotifierProvider<ComparisonNotifier, List<YearlyComparison>>(
  ComparisonNotifier.new,
);
