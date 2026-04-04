// Session record returned by the API.
class SessionRecord {
  final String id;
  final String patientId;
  final int year;
  final int month;

  /// ISO-8601 date strings ("YYYY-MM-DD") for each session day.
  final List<String> sessionDates;

  final int sessionCount;
  final double expectedAmount;
  final String? observations;
  final bool isReposicao;
  final SessionPayment? payment;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionRecord({
    required this.id,
    required this.patientId,
    required this.year,
    required this.month,
    required this.sessionDates,
    required this.sessionCount,
    required this.expectedAmount,
    this.observations,
    required this.isReposicao,
    this.payment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        id: json['id'] as String,
        patientId: json['patientId'] as String,
        year: json['year'] as int,
        month: json['month'] as int,
        sessionDates: (json['sessionDates'] as List)
            .map((e) => e as String)
            .toList(),
        sessionCount: json['sessionCount'] as int,
        expectedAmount: (json['expectedAmount'] as num).toDouble(),
        observations: json['observations'] as String?,
        isReposicao: json['isReposicao'] as bool,
        payment: json['payment'] == null
            ? null
            : SessionPayment.fromJson(
                json['payment'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class SessionPayment {
  final String id;
  final double amountPaid;
  final String status;
  final double? revenueShareAmount;

  const SessionPayment({
    required this.id,
    required this.amountPaid,
    required this.status,
    this.revenueShareAmount,
  });

  factory SessionPayment.fromJson(Map<String, dynamic> json) => SessionPayment(
        id: json['id'] as String,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        status: json['status'] as String,
        revenueShareAmount: json['revenueShareAmount'] == null
            ? null
            : (json['revenueShareAmount'] as num).toDouble(),
      );
}

class SaveSessionDto {
  final List<String> sessionDates;
  final String? observations;
  final bool isReposicao;

  const SaveSessionDto({
    required this.sessionDates,
    this.observations,
    required this.isReposicao,
  });

  Map<String, dynamic> toJson() => {
        'sessionDates': sessionDates,
        if (observations != null && observations!.isNotEmpty)
          'observations': observations,
        'isReposicao': isReposicao,
      };
}
