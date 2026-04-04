// ---------------------------------------------------------------------------
// MonthlyTotal
// ---------------------------------------------------------------------------

class MonthlyTotal {
  final int month;
  final double expected;
  final double received;

  const MonthlyTotal({
    required this.month,
    required this.expected,
    required this.received,
  });

  factory MonthlyTotal.fromJson(Map<String, dynamic> json) => MonthlyTotal(
        month: json['month'] as int,
        expected: (json['expected'] as num).toDouble(),
        received: (json['received'] as num).toDouble(),
      );
}

// ---------------------------------------------------------------------------
// CurrencyDashboard
// ---------------------------------------------------------------------------

class CurrencyDashboard {
  final List<MonthlyTotal> monthlyTotals;
  final double yearToDateExpected;
  final double yearToDateReceived;
  final List<String> countries;

  const CurrencyDashboard({
    required this.monthlyTotals,
    required this.yearToDateExpected,
    required this.yearToDateReceived,
    required this.countries,
  });

  factory CurrencyDashboard.fromJson(Map<String, dynamic> json) {
    final ytd = json['yearToDate'] as Map<String, dynamic>;
    return CurrencyDashboard(
      monthlyTotals: (json['monthlyTotals'] as List)
          .map((e) => MonthlyTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
      yearToDateExpected: (ytd['expected'] as num).toDouble(),
      yearToDateReceived: (ytd['received'] as num).toDouble(),
      countries: (json['countries'] as List).map((e) => e as String).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// DashboardPatient
// ---------------------------------------------------------------------------

class DashboardPatient {
  final String id;
  final String name;
  final String location;
  final String currency; // 'BRL' | 'EUR'
  final int totalSessions;
  final double totalExpected;
  final double totalReceived;
  final double balance;
  final bool hasOutstanding;

  const DashboardPatient({
    required this.id,
    required this.name,
    required this.location,
    required this.currency,
    required this.totalSessions,
    required this.totalExpected,
    required this.totalReceived,
    required this.balance,
    required this.hasOutstanding,
  });

  factory DashboardPatient.fromJson(Map<String, dynamic> json) => DashboardPatient(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String,
        currency: json['currency'] as String,
        totalSessions: json['totalSessions'] as int,
        totalExpected: (json['totalExpected'] as num).toDouble(),
        totalReceived: (json['totalReceived'] as num).toDouble(),
        balance: (json['balance'] as num).toDouble(),
        hasOutstanding: json['hasOutstanding'] as bool,
      );
}

// ---------------------------------------------------------------------------
// RepasseEntry
// ---------------------------------------------------------------------------

class RepasseEntry {
  final String patientId;
  final String patientName;
  final String currency;
  final String beneficiaryName;
  final int totalSessions;
  final double totalRepass;

  const RepasseEntry({
    required this.patientId,
    required this.patientName,
    required this.currency,
    required this.beneficiaryName,
    required this.totalSessions,
    required this.totalRepass,
  });

  factory RepasseEntry.fromJson(Map<String, dynamic> json) => RepasseEntry(
        patientId: json['patientId'] as String,
        patientName: json['patientName'] as String,
        currency: json['currency'] as String,
        beneficiaryName: json['beneficiaryName'] as String,
        totalSessions: json['totalSessions'] as int,
        totalRepass: (json['totalRepass'] as num).toDouble(),
      );
}

// ---------------------------------------------------------------------------
// DashboardData — top-level response
// ---------------------------------------------------------------------------

class DashboardData {
  final int year;
  final CurrencyDashboard brl;
  final CurrencyDashboard eur;
  final List<DashboardPatient> patients;
  final List<RepasseEntry> repasses;

  const DashboardData({
    required this.year,
    required this.brl,
    required this.eur,
    required this.patients,
    required this.repasses,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
        year: json['year'] as int,
        brl: CurrencyDashboard.fromJson(json['BRL'] as Map<String, dynamic>),
        eur: CurrencyDashboard.fromJson(json['EUR'] as Map<String, dynamic>),
        patients: (json['patients'] as List)
            .map((e) => DashboardPatient.fromJson(e as Map<String, dynamic>))
            .toList(),
        repasses: (json['repasses'] as List? ?? [])
            .map((e) => RepasseEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// YearlyComparison — response from /api/dashboard/comparison
// ---------------------------------------------------------------------------

class YearlyComparison {
  final int year;
  final double brlExpected;
  final double brlReceived;
  final double eurExpected;
  final double eurReceived;

  const YearlyComparison({
    required this.year,
    required this.brlExpected,
    required this.brlReceived,
    required this.eurExpected,
    required this.eurReceived,
  });

  factory YearlyComparison.fromJson(Map<String, dynamic> json) {
    final brl = json['BRL'] as Map<String, dynamic>;
    final eur = json['EUR'] as Map<String, dynamic>;
    return YearlyComparison(
      year: json['year'] as int,
      brlExpected: (brl['expected'] as num).toDouble(),
      brlReceived: (brl['received'] as num).toDouble(),
      eurExpected: (eur['expected'] as num).toDouble(),
      eurReceived: (eur['received'] as num).toDouble(),
    );
  }
}
