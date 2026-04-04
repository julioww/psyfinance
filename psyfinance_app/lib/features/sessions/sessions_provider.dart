import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:psyfinance_app/features/patients/patients_provider.dart';
import 'session_record_model.dart';
import 'sessions_repository.dart';

final sessionsRepositoryProvider = Provider<SessionsRepository>(
  (ref) => SessionsRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Session record loader — null when the month has no session yet (404)
// ---------------------------------------------------------------------------

typedef SessionArgs = ({String patientId, int year, int month});

final sessionProvider = AsyncNotifierProvider.family<
    SessionNotifier, SessionRecord?, SessionArgs>(
  SessionNotifier.new,
);

class SessionNotifier
    extends FamilyAsyncNotifier<SessionRecord?, SessionArgs> {
  @override
  Future<SessionRecord?> build(SessionArgs arg) =>
      ref.read(sessionsRepositoryProvider).getSession(
            arg.patientId,
            arg.year,
            arg.month,
          );
}
