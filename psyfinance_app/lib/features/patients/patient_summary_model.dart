import 'package:psyfinance_app/features/patients/patient_model.dart';
import 'package:psyfinance_app/features/patients/rate_history_model.dart';

enum MonthPaymentStatus { pago, parcial, pendente, atrasado }

extension MonthPaymentStatusX on MonthPaymentStatus {
  String get label {
    switch (this) {
      case MonthPaymentStatus.pago:
        return 'Pago';
      case MonthPaymentStatus.parcial:
        return 'Parcial';
      case MonthPaymentStatus.pendente:
        return 'Pendente';
      case MonthPaymentStatus.atrasado:
        return 'Atrasado';
    }
  }

  static MonthPaymentStatus? fromString(String? s) {
    switch (s?.toUpperCase()) {
      case 'PAGO':
        return MonthPaymentStatus.pago;
      case 'PARCIAL':
        return MonthPaymentStatus.parcial;
      case 'PENDENTE':
        return MonthPaymentStatus.pendente;
      case 'ATRASADO':
        return MonthPaymentStatus.atrasado;
      default:
        return null;
    }
  }
}

class MonthSummary {
  final int month;
  final String? sessionRecordId;
  final int? sessionCount;
  final double? expectedAmount;
  final double? amountPaid;
  final double? balance;
  final MonthPaymentStatus? status;
  final String? observations;

  const MonthSummary({
    required this.month,
    this.sessionRecordId,
    this.sessionCount,
    this.expectedAmount,
    this.amountPaid,
    this.balance,
    this.status,
    this.observations,
  });

  bool get hasData => sessionCount != null;

  factory MonthSummary.fromJson(Map<String, dynamic> json) => MonthSummary(
        month: json['month'] as int,
        sessionRecordId: json['sessionRecordId'] as String?,
        sessionCount: json['sessionCount'] as int?,
        expectedAmount: json['expectedAmount'] == null
            ? null
            : (json['expectedAmount'] as num).toDouble(),
        amountPaid: json['amountPaid'] == null
            ? null
            : (json['amountPaid'] as num).toDouble(),
        balance: json['balance'] == null
            ? null
            : (json['balance'] as num).toDouble(),
        status: MonthPaymentStatusX.fromString(json['status'] as String?),
        observations: json['observations'] as String?,
      );
}

class PatientSummary {
  final Patient patient;
  final List<RateHistory> rates;
  final List<MonthSummary> months;

  const PatientSummary({
    required this.patient,
    required this.rates,
    required this.months,
  });

  factory PatientSummary.fromJson(Map<String, dynamic> json) => PatientSummary(
        patient: Patient.fromJson(json['patient'] as Map<String, dynamic>),
        rates: (json['rates'] as List)
            .map((e) => RateHistory.fromJson(e as Map<String, dynamic>))
            .toList(),
        months: (json['months'] as List)
            .map((e) => MonthSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get totalSessions =>
      months.where((m) => m.hasData).fold(0, (s, m) => s + m.sessionCount!);

  double get totalExpected =>
      months.where((m) => m.hasData).fold(0.0, (s, m) => s + m.expectedAmount!);

  double get totalPaid =>
      months.where((m) => m.hasData).fold(0.0, (s, m) => s + m.amountPaid!);

  double get totalBalance =>
      months.where((m) => m.hasData).fold(0.0, (s, m) => s + m.balance!);
}
