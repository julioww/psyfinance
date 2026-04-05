/// Compact patient info embedded in each agenda entry.
class AgendaPatient {
  final String id;
  final String name;
  final String currency; // 'BRL' or 'EUR'
  final double? currentRate;
  final String location;

  const AgendaPatient({
    required this.id,
    required this.name,
    required this.currency,
    this.currentRate,
    required this.location,
  });

  factory AgendaPatient.fromJson(Map<String, dynamic> json) => AgendaPatient(
        id: json['id'] as String,
        name: json['name'] as String,
        currency: json['currency'] as String,
        currentRate: json['currentRate'] == null
            ? null
            : (json['currentRate'] as num).toDouble(),
        location: json['location'] as String,
      );
}

/// Minimal session-record info embedded in each agenda entry.
class AgendaSessionRecord {
  final String id;
  final String? observations;
  final bool isReposicao;

  const AgendaSessionRecord({
    required this.id,
    this.observations,
    required this.isReposicao,
  });

  factory AgendaSessionRecord.fromJson(Map<String, dynamic> json) =>
      AgendaSessionRecord(
        id: json['id'] as String,
        observations: json['observations'] as String?,
        isReposicao: json['isReposicao'] as bool,
      );
}

/// One expanded session date returned by GET /api/agenda.
class AgendaSession {
  final String date;      // "YYYY-MM-DD"
  final int dayOfWeek;    // 1=Mon … 7=Sun (ISO weekday)
  final AgendaPatient patient;
  final AgendaSessionRecord sessionRecord;

  const AgendaSession({
    required this.date,
    required this.dayOfWeek,
    required this.patient,
    required this.sessionRecord,
  });

  factory AgendaSession.fromJson(Map<String, dynamic> json) => AgendaSession(
        date: json['date'] as String,
        dayOfWeek: json['dayOfWeek'] as int,
        patient:
            AgendaPatient.fromJson(json['patient'] as Map<String, dynamic>),
        sessionRecord: AgendaSessionRecord.fromJson(
            json['sessionRecord'] as Map<String, dynamic>),
      );

  DateTime get dateTime => DateTime.parse(date);
}
