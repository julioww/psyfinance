// ---------------------------------------------------------------------------
// ShareType enum
// ---------------------------------------------------------------------------

enum ShareType { percentage, fixedPerSession }

extension ShareTypeX on ShareType {
  String get apiValue => switch (this) {
        ShareType.percentage => 'PERCENTAGE',
        ShareType.fixedPerSession => 'FIXED_PER_SESSION',
      };

  String get label => switch (this) {
        ShareType.percentage => 'Percentual',
        ShareType.fixedPerSession => 'Fixo por sessão',
      };

  static ShareType fromApi(String value) => switch (value) {
        'PERCENTAGE' => ShareType.percentage,
        'FIXED_PER_SESSION' => ShareType.fixedPerSession,
        _ => throw ArgumentError('Unknown ShareType: $value'),
      };
}

// ---------------------------------------------------------------------------
// RevenueShareConfig
// ---------------------------------------------------------------------------

class RevenueShareConfig {
  final String id;
  final String patientId;
  final ShareType shareType;
  final double shareValue;
  final String beneficiaryName;
  final bool active;

  const RevenueShareConfig({
    required this.id,
    required this.patientId,
    required this.shareType,
    required this.shareValue,
    required this.beneficiaryName,
    required this.active,
  });

  factory RevenueShareConfig.fromJson(Map<String, dynamic> json) =>
      RevenueShareConfig(
        id: json['id'] as String,
        patientId: json['patientId'] as String,
        shareType: ShareTypeX.fromApi(json['shareType'] as String),
        shareValue: (json['shareValue'] as num).toDouble(),
        beneficiaryName: json['beneficiaryName'] as String,
        active: json['active'] as bool,
      );
}

// ---------------------------------------------------------------------------
// RevenueShareDto  — sent when creating / updating
// ---------------------------------------------------------------------------

class RevenueShareDto {
  final ShareType shareType;
  final double shareValue;
  final String beneficiaryName;

  const RevenueShareDto({
    required this.shareType,
    required this.shareValue,
    required this.beneficiaryName,
  });

  Map<String, dynamic> toJson() => {
        'shareType': shareType.apiValue,
        'shareValue': shareValue,
        'beneficiaryName': beneficiaryName,
      };
}

// ---------------------------------------------------------------------------
// Local calculation helper (mirrors backend logic; useful for unit tests)
// ---------------------------------------------------------------------------

double computeRevenueShare(
  double expectedAmount,
  int sessionCount,
  RevenueShareConfig config,
) {
  if (!config.active) return 0.0;
  return switch (config.shareType) {
    ShareType.percentage => expectedAmount * (config.shareValue / 100),
    ShareType.fixedPerSession => sessionCount * config.shareValue,
  };
}
