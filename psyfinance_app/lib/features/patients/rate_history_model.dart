class RateHistory {
  final String id;
  final String patientId;
  final double rate;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;

  const RateHistory({
    required this.id,
    required this.patientId,
    required this.rate,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  factory RateHistory.fromJson(Map<String, dynamic> json) => RateHistory(
        id: json['id'] as String,
        patientId: json['patientId'] as String,
        rate: (json['rate'] as num).toDouble(),
        effectiveFrom: DateTime.parse(json['effectiveFrom'] as String),
        effectiveTo: json['effectiveTo'] == null
            ? null
            : DateTime.parse(json['effectiveTo'] as String),
      );

  bool get isCurrent => effectiveTo == null;
}
