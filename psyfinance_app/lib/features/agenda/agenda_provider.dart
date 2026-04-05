import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'agenda_repository.dart';
import 'agenda_session_model.dart';

final agendaRepositoryProvider = Provider<AgendaRepository>(
  (ref) => AgendaRepository(ref.watch(apiClientProvider)),
);

typedef AgendaArgs = ({int year, int month});

/// Fetches all expanded session entries for a given year/month.
///
/// Uses autoDispose so the cached result is discarded when the screen is left.
/// This ensures a fresh API call every time the Sessões screen is entered,
/// picking up any sessions added in other screens (Monthly, Quick-add, etc.).
final agendaProvider =
    FutureProvider.autoDispose.family<List<AgendaSession>, AgendaArgs>(
        (ref, args) {
  return ref
      .read(agendaRepositoryProvider)
      .getAgenda(args.year, args.month);
});
