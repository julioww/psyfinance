enum PatientStatus { ativo, inativo }

enum PaymentModel { sessao, mensal }

enum PatientCurrency { brl, eur }

extension PatientStatusX on PatientStatus {
  String get apiValue => name.toUpperCase();
  String get label => this == PatientStatus.ativo ? 'Ativo' : 'Inativo';
}

extension PaymentModelX on PaymentModel {
  String get apiValue => name.toUpperCase();
  String get label => this == PaymentModel.sessao ? 'Sessão' : 'Mensal';
}

extension PatientCurrencyX on PatientCurrency {
  String get apiValue => name.toUpperCase();
  String get symbol => this == PatientCurrency.brl ? 'R\$' : '€';
}

PatientStatus _parseStatus(String v) =>
    v.toUpperCase() == 'INATIVO' ? PatientStatus.inativo : PatientStatus.ativo;

PaymentModel _parsePaymentModel(String v) =>
    v.toUpperCase() == 'MENSAL' ? PaymentModel.mensal : PaymentModel.sessao;

PatientCurrency _parseCurrency(String v) =>
    v.toUpperCase() == 'EUR' ? PatientCurrency.eur : PatientCurrency.brl;

class Patient {
  final String id;
  final String name;
  final String email;
  final String? cpf;
  final String location;
  final PatientStatus status;
  final PaymentModel paymentModel;
  final PatientCurrency currency;
  final String? notes;
  final double? currentRate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Patient({
    required this.id,
    required this.name,
    required this.email,
    this.cpf,
    required this.location,
    required this.status,
    required this.paymentModel,
    required this.currency,
    this.notes,
    this.currentRate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        cpf: json['cpf'] as String?,
        location: json['location'] as String,
        status: _parseStatus(json['status'] as String),
        paymentModel: _parsePaymentModel(json['paymentModel'] as String),
        currency: _parseCurrency(json['currency'] as String),
        notes: json['notes'] as String?,
        currentRate: json['currentRate'] == null ? null : (json['currentRate'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        if (cpf != null) 'cpf': cpf,
        'location': location,
        'status': status.apiValue,
        'paymentModel': paymentModel.apiValue,
        'currency': currency.apiValue,
        if (notes != null) 'notes': notes,
        'currentRate': currentRate,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Patient copyWith({
    String? name,
    String? email,
    String? cpf,
    String? location,
    PatientStatus? status,
    PaymentModel? paymentModel,
    PatientCurrency? currency,
    String? notes,
    double? currentRate,
  }) =>
      Patient(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        cpf: cpf ?? this.cpf,
        location: location ?? this.location,
        status: status ?? this.status,
        paymentModel: paymentModel ?? this.paymentModel,
        currency: currency ?? this.currency,
        notes: notes ?? this.notes,
        currentRate: currentRate ?? this.currentRate,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

// ---------------------------------------------------------------------------
// DTOs
// ---------------------------------------------------------------------------

class CreatePatientDto {
  final String name;
  final String email;
  final String? cpf;
  final String location;
  final PaymentModel paymentModel;
  final PatientCurrency currency;
  final double initialRate;
  final DateTime rateEffectiveFrom;
  final String? notes;

  const CreatePatientDto({
    required this.name,
    required this.email,
    this.cpf,
    required this.location,
    required this.paymentModel,
    required this.currency,
    required this.initialRate,
    required this.rateEffectiveFrom,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        if (cpf != null && cpf!.isNotEmpty) 'cpf': cpf,
        'location': location,
        'paymentModel': paymentModel.apiValue,
        'currency': currency.apiValue,
        'initialRate': initialRate,
        'rateEffectiveFrom': rateEffectiveFrom.toIso8601String().split('T').first,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class UpdatePatientDto {
  final String? name;
  final String? email;
  final String? cpf;
  final String? location;
  final PaymentModel? paymentModel;
  final PatientCurrency? currency;
  final String? notes;
  final PatientStatus? status;

  const UpdatePatientDto({
    this.name,
    this.email,
    this.cpf,
    this.location,
    this.paymentModel,
    this.currency,
    this.notes,
    this.status,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (cpf != null) 'cpf': cpf,
        if (location != null) 'location': location,
        if (paymentModel != null) 'paymentModel': paymentModel!.apiValue,
        if (currency != null) 'currency': currency!.apiValue,
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status!.apiValue,
      };
}
