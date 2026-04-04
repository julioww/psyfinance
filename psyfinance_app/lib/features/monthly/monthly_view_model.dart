import 'package:psyfinance_app/features/patients/patient_model.dart';

// ---------------------------------------------------------------------------
// MonthlyPatient — slim patient data returned by the monthly-view endpoint.
// ---------------------------------------------------------------------------

class MonthlyPatient {
  final String id;
  final String name;
  final String location;
  final PatientCurrency currency;
  final PaymentModel paymentModel;
  final double? currentRate;

  const MonthlyPatient({
    required this.id,
    required this.name,
    required this.location,
    required this.currency,
    required this.paymentModel,
    this.currentRate,
  });

  factory MonthlyPatient.fromJson(Map<String, dynamic> json) => MonthlyPatient(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String,
        currency: json['currency'] as String == 'EUR'
            ? PatientCurrency.eur
            : PatientCurrency.brl,
        paymentModel: json['paymentModel'] as String == 'MENSAL'
            ? PaymentModel.mensal
            : PaymentModel.sessao,
        currentRate: json['currentRate'] == null
            ? null
            : (json['currentRate'] as num).toDouble(),
      );
}

// ---------------------------------------------------------------------------
// MonthlySessionRecord
// ---------------------------------------------------------------------------

class MonthlySessionRecord {
  final String id;
  final List<String> sessionDates;
  final int sessionCount;
  final double expectedAmount;
  final String? observations;
  final bool isReposicao;

  const MonthlySessionRecord({
    required this.id,
    required this.sessionDates,
    required this.sessionCount,
    required this.expectedAmount,
    this.observations,
    required this.isReposicao,
  });

  factory MonthlySessionRecord.fromJson(Map<String, dynamic> json) =>
      MonthlySessionRecord(
        id: json['id'] as String,
        sessionDates:
            (json['sessionDates'] as List).map((e) => e as String).toList(),
        sessionCount: json['sessionCount'] as int,
        expectedAmount: (json['expectedAmount'] as num).toDouble(),
        observations: json['observations'] as String?,
        isReposicao: json['isReposicao'] as bool,
      );

  MonthlySessionRecord copyWith({double? expectedAmount}) =>
      MonthlySessionRecord(
        id: id,
        sessionDates: sessionDates,
        sessionCount: sessionCount,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        observations: observations,
        isReposicao: isReposicao,
      );
}

// ---------------------------------------------------------------------------
// MonthlyPayment
// ---------------------------------------------------------------------------

class MonthlyPayment {
  final String id;
  final double amountPaid;
  final String status; // PENDENTE | PARCIAL | PAGO | ATRASADO
  final double? revenueShareAmount;

  const MonthlyPayment({
    required this.id,
    required this.amountPaid,
    required this.status,
    this.revenueShareAmount,
  });

  factory MonthlyPayment.fromJson(Map<String, dynamic> json) => MonthlyPayment(
        id: json['id'] as String,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        status: json['status'] as String,
        revenueShareAmount: json['revenueShareAmount'] == null
            ? null
            : (json['revenueShareAmount'] as num).toDouble(),
      );

  MonthlyPayment copyWith({double? amountPaid, String? status}) =>
      MonthlyPayment(
        id: id,
        amountPaid: amountPaid ?? this.amountPaid,
        status: status ?? this.status,
        revenueShareAmount: revenueShareAmount,
      );
}

// ---------------------------------------------------------------------------
// MonthlyPatientRow
// ---------------------------------------------------------------------------

class MonthlyPatientRow {
  final MonthlyPatient patient;
  final MonthlySessionRecord? sessionRecord;
  final MonthlyPayment? payment;

  const MonthlyPatientRow({
    required this.patient,
    this.sessionRecord,
    this.payment,
  });

  factory MonthlyPatientRow.fromJson(Map<String, dynamic> json) =>
      MonthlyPatientRow(
        patient:
            MonthlyPatient.fromJson(json['patient'] as Map<String, dynamic>),
        sessionRecord: json['sessionRecord'] == null
            ? null
            : MonthlySessionRecord.fromJson(
                json['sessionRecord'] as Map<String, dynamic>),
        payment: json['payment'] == null
            ? null
            : MonthlyPayment.fromJson(
                json['payment'] as Map<String, dynamic>),
      );

  MonthlyPatientRow copyWith({
    MonthlySessionRecord? sessionRecord,
    MonthlyPayment? payment,
    bool clearPayment = false,
  }) =>
      MonthlyPatientRow(
        patient: patient,
        sessionRecord: sessionRecord ?? this.sessionRecord,
        payment: clearPayment ? null : (payment ?? this.payment),
      );
}

// ---------------------------------------------------------------------------
// CurrencySummary
// ---------------------------------------------------------------------------

class CurrencySummary {
  final double totalExpected;
  final double totalReceived;

  const CurrencySummary({
    required this.totalExpected,
    required this.totalReceived,
  });

  factory CurrencySummary.fromJson(Map<String, dynamic> json) =>
      CurrencySummary(
        totalExpected: (json['totalExpected'] as num).toDouble(),
        totalReceived: (json['totalReceived'] as num).toDouble(),
      );

  CurrencySummary operator +(CurrencySummary other) => CurrencySummary(
        totalExpected: totalExpected + other.totalExpected,
        totalReceived: totalReceived + other.totalReceived,
      );
}

// ---------------------------------------------------------------------------
// MonthlyView — top-level response object
// ---------------------------------------------------------------------------

class MonthlyView {
  final List<MonthlyPatientRow> patients;

  /// Keyed by currency string: 'BRL' or 'EUR'.
  final Map<String, CurrencySummary> summary;

  const MonthlyView({
    required this.patients,
    required this.summary,
  });

  factory MonthlyView.fromJson(Map<String, dynamic> json) {
    final summaryJson = json['summary'] as Map<String, dynamic>;
    return MonthlyView(
      patients: (json['patients'] as List)
          .map((e) => MonthlyPatientRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: summaryJson.map(
        (k, v) => MapEntry(k, CurrencySummary.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  MonthlyView copyWith({
    List<MonthlyPatientRow>? patients,
    Map<String, CurrencySummary>? summary,
  }) =>
      MonthlyView(
        patients: patients ?? this.patients,
        summary: summary ?? this.summary,
      );
}

// ---------------------------------------------------------------------------
// Helper: compute summary totals from a list of rows (used for in-place updates)
// ---------------------------------------------------------------------------

Map<String, CurrencySummary> computeSummaryFromRows(
    List<MonthlyPatientRow> rows) {
  var brl = const CurrencySummary(totalExpected: 0, totalReceived: 0);
  var eur = const CurrencySummary(totalExpected: 0, totalReceived: 0);

  for (final row in rows) {
    final expected = row.sessionRecord?.expectedAmount ?? 0.0;
    final received = row.payment?.amountPaid ?? 0.0;
    final delta =
        CurrencySummary(totalExpected: expected, totalReceived: received);
    if (row.patient.currency == PatientCurrency.brl) {
      brl = brl + delta;
    } else {
      eur = eur + delta;
    }
  }

  return {'BRL': brl, 'EUR': eur};
}
