// ---------------------------------------------------------------------------
// PanelCurrencySummary
// ---------------------------------------------------------------------------

class PanelCurrencySummary {
  final double totalExpected;
  final double totalReceived;
  final double totalOutstanding;
  final int countPaid;
  final int countPending;
  final int countOverdue;

  const PanelCurrencySummary({
    required this.totalExpected,
    required this.totalReceived,
    required this.totalOutstanding,
    required this.countPaid,
    required this.countPending,
    required this.countOverdue,
  });

  factory PanelCurrencySummary.zero() => const PanelCurrencySummary(
        totalExpected: 0,
        totalReceived: 0,
        totalOutstanding: 0,
        countPaid: 0,
        countPending: 0,
        countOverdue: 0,
      );

  factory PanelCurrencySummary.fromJson(Map<String, dynamic> json) =>
      PanelCurrencySummary(
        totalExpected: (json['totalExpected'] as num).toDouble(),
        totalReceived: (json['totalReceived'] as num).toDouble(),
        totalOutstanding: (json['totalOutstanding'] as num).toDouble(),
        countPaid: json['countPaid'] as int,
        countPending: json['countPending'] as int,
        countOverdue: json['countOverdue'] as int,
      );

  PanelCurrencySummary operator +(PanelCurrencySummary other) =>
      PanelCurrencySummary(
        totalExpected: totalExpected + other.totalExpected,
        totalReceived: totalReceived + other.totalReceived,
        totalOutstanding: totalOutstanding + other.totalOutstanding,
        countPaid: countPaid + other.countPaid,
        countPending: countPending + other.countPending,
        countOverdue: countOverdue + other.countOverdue,
      );
}

// ---------------------------------------------------------------------------
// PanelPatient
// ---------------------------------------------------------------------------

class PanelPatient {
  final String id;
  final String name;
  final String location;
  final String currency; // 'BRL' | 'EUR'

  const PanelPatient({
    required this.id,
    required this.name,
    required this.location,
    required this.currency,
  });

  factory PanelPatient.fromJson(Map<String, dynamic> json) => PanelPatient(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String,
        currency: json['currency'] as String,
      );
}

// ---------------------------------------------------------------------------
// PanelSessionRecord
// ---------------------------------------------------------------------------

class PanelSessionRecord {
  final String id;
  final int month;
  final int year;
  final int sessionCount;
  final double expectedAmount;

  const PanelSessionRecord({
    required this.id,
    required this.month,
    required this.year,
    required this.sessionCount,
    required this.expectedAmount,
  });

  factory PanelSessionRecord.fromJson(Map<String, dynamic> json) =>
      PanelSessionRecord(
        id: json['id'] as String,
        month: json['month'] as int,
        year: json['year'] as int,
        sessionCount: json['sessionCount'] as int,
        expectedAmount: (json['expectedAmount'] as num).toDouble(),
      );
}

// ---------------------------------------------------------------------------
// PanelPayment
// ---------------------------------------------------------------------------

class PanelPayment {
  final String id;
  final double amountPaid;
  final String status; // PENDENTE | PARCIAL | PAGO | ATRASADO
  final double? revenueShareAmount;

  const PanelPayment({
    required this.id,
    required this.amountPaid,
    required this.status,
    this.revenueShareAmount,
  });

  factory PanelPayment.fromJson(Map<String, dynamic> json) => PanelPayment(
        id: json['id'] as String,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        status: json['status'] as String,
        revenueShareAmount: json['revenueShareAmount'] == null
            ? null
            : (json['revenueShareAmount'] as num).toDouble(),
      );

  PanelPayment copyWith({double? amountPaid, String? status}) => PanelPayment(
        id: id,
        amountPaid: amountPaid ?? this.amountPaid,
        status: status ?? this.status,
        revenueShareAmount: revenueShareAmount,
      );
}

// ---------------------------------------------------------------------------
// PaymentPanelRow
// ---------------------------------------------------------------------------

class PaymentPanelRow {
  final PanelPatient patient;
  final PanelSessionRecord sessionRecord;
  final PanelPayment payment;

  const PaymentPanelRow({
    required this.patient,
    required this.sessionRecord,
    required this.payment,
  });

  factory PaymentPanelRow.fromJson(Map<String, dynamic> json) =>
      PaymentPanelRow(
        patient:
            PanelPatient.fromJson(json['patient'] as Map<String, dynamic>),
        sessionRecord: PanelSessionRecord.fromJson(
            json['sessionRecord'] as Map<String, dynamic>),
        payment:
            PanelPayment.fromJson(json['payment'] as Map<String, dynamic>),
      );

  PaymentPanelRow copyWith({PanelPayment? payment}) => PaymentPanelRow(
        patient: patient,
        sessionRecord: sessionRecord,
        payment: payment ?? this.payment,
      );
}

// ---------------------------------------------------------------------------
// PaymentPanel — top-level response object
// ---------------------------------------------------------------------------

class PaymentPanel {
  /// Keyed by currency string: 'BRL' or 'EUR'.
  final Map<String, PanelCurrencySummary> summary;
  final List<PaymentPanelRow> payments;

  const PaymentPanel({
    required this.summary,
    required this.payments,
  });

  factory PaymentPanel.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'] as Map<String, dynamic>;
    return PaymentPanel(
      summary: summaryJson.map(
        (k, v) => MapEntry(
            k, PanelCurrencySummary.fromJson(v as Map<String, dynamic>)),
      ),
      payments: (json['payments'] as List)
          .map((e) => PaymentPanelRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  PaymentPanel copyWith({
    Map<String, PanelCurrencySummary>? summary,
    List<PaymentPanelRow>? payments,
  }) =>
      PaymentPanel(
        summary: summary ?? this.summary,
        payments: payments ?? this.payments,
      );
}

// ---------------------------------------------------------------------------
// Helper: recompute summary from rows (used for in-place updates)
// ---------------------------------------------------------------------------

Map<String, PanelCurrencySummary> computePanelSummaryFromRows(
    List<PaymentPanelRow> rows) {
  var brl = PanelCurrencySummary.zero();
  var eur = PanelCurrencySummary.zero();

  for (final row in rows) {
    final expected = row.sessionRecord.expectedAmount;
    final paid = row.payment.amountPaid;
    final status = row.payment.status;

    final delta = PanelCurrencySummary(
      totalExpected: expected,
      totalReceived: paid,
      totalOutstanding: expected - paid,
      countPaid: status == 'PAGO' ? 1 : 0,
      countPending: (status == 'PENDENTE' || status == 'PARCIAL') ? 1 : 0,
      countOverdue: status == 'ATRASADO' ? 1 : 0,
    );

    if (row.patient.currency == 'BRL') {
      brl = brl + delta;
    } else {
      eur = eur + delta;
    }
  }

  return {'BRL': brl, 'EUR': eur};
}
