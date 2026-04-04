class Payment {
  final String id;
  final String sessionRecordId;
  final double amountPaid;
  final String status;
  final double expectedAmount;
  final double? revenueShareAmount;

  const Payment({
    required this.id,
    required this.sessionRecordId,
    required this.amountPaid,
    required this.status,
    required this.expectedAmount,
    this.revenueShareAmount,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        sessionRecordId: json['sessionRecordId'] as String,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        status: json['status'] as String,
        expectedAmount: (json['expectedAmount'] as num).toDouble(),
        revenueShareAmount: json['revenueShareAmount'] == null
            ? null
            : (json['revenueShareAmount'] as num).toDouble(),
      );
}
