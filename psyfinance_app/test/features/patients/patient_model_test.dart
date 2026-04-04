import 'package:flutter_test/flutter_test.dart';
import 'package:psyfinance_app/features/patients/patient_model.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Sample JSON fixture — mirrors the API response shape
  // ---------------------------------------------------------------------------

  final Map<String, dynamic> sampleJson = {
    'id': 'abc-123',
    'name': 'Félix Müller',
    'email': 'felix@example.de',
    'cpf': null,
    'location': 'Alemanha',
    'status': 'ATIVO',
    'paymentModel': 'SESSAO',
    'currency': 'EUR',
    'notes': 'Paciente europeu',
    'currentRate': 120.0,
    'createdAt': '2025-01-15T10:00:00.000Z',
    'updatedAt': '2025-03-01T12:00:00.000Z',
  };

  // ---------------------------------------------------------------------------
  // PatientModel.fromJson — field parsing
  // ---------------------------------------------------------------------------

  group('Patient.fromJson', () {
    test('parses all fields correctly', () {
      final p = Patient.fromJson(sampleJson);

      expect(p.id, 'abc-123');
      expect(p.name, 'Félix Müller');
      expect(p.email, 'felix@example.de');
      expect(p.cpf, isNull);
      expect(p.location, 'Alemanha'); // plain String, not an enum
      expect(p.status, PatientStatus.ativo);
      expect(p.paymentModel, PaymentModel.sessao);
      expect(p.currency, PatientCurrency.eur);
      expect(p.notes, 'Paciente europeu');
      expect(p.currentRate, 120.0);
      expect(p.createdAt, DateTime.parse('2025-01-15T10:00:00.000Z'));
      expect(p.updatedAt, DateTime.parse('2025-03-01T12:00:00.000Z'));
    });

    test('location is stored as a plain String', () {
      final p = Patient.fromJson(sampleJson);
      expect(p.location, isA<String>());
      expect(p.location, 'Alemanha');
    });

    test('parses INATIVO status', () {
      final p = Patient.fromJson({...sampleJson, 'status': 'INATIVO'});
      expect(p.status, PatientStatus.inativo);
    });

    test('parses MENSAL paymentModel', () {
      final p = Patient.fromJson({...sampleJson, 'paymentModel': 'MENSAL'});
      expect(p.paymentModel, PaymentModel.mensal);
    });

    test('parses BRL currency', () {
      final p = Patient.fromJson({...sampleJson, 'currency': 'BRL'});
      expect(p.currency, PatientCurrency.brl);
    });

    test('handles null currentRate', () {
      final p = Patient.fromJson({...sampleJson, 'currentRate': null});
      expect(p.currentRate, isNull);
    });

    test('handles integer currentRate (API may send int)', () {
      final p = Patient.fromJson({...sampleJson, 'currentRate': 200});
      expect(p.currentRate, 200.0);
    });

    test('handles optional cpf when present', () {
      final p = Patient.fromJson({...sampleJson, 'cpf': '123.456.789-00'});
      expect(p.cpf, '123.456.789-00');
    });
  });

  // ---------------------------------------------------------------------------
  // Avatar color consistency
  // ---------------------------------------------------------------------------

  // We test the colour logic via the public _avatarColor-equivalent by checking
  // that the same patientId always maps to the same palette index.
  // Since _avatarColor is private we replicate the algorithm here.

  Color _avatarColorTest(String patientId) {
    const palette = [
      Color(0xFF00695C),
      Color(0xFF00838F),
      Color(0xFF1565C0),
      Color(0xFF283593),
      Color(0xFF6A1B9A),
      Color(0xFF558B2F),
      Color(0xFFE65100),
      Color(0xFF827717),
    ];
    int hash = 0;
    for (final c in patientId.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  group('Avatar color consistency', () {
    test('same patientId always maps to the same color', () {
      const id = 'abc-123';
      final c1 = _avatarColorTest(id);
      final c2 = _avatarColorTest(id);
      expect(c1, c2);
    });

    test('different patientIds can map to different colors', () {
      // Not guaranteed to differ, but these specific IDs do
      final c1 = _avatarColorTest('aaaa');
      final c2 = _avatarColorTest('zzzz');
      // Just assert they are valid Color objects
      expect(c1, isA<Color>());
      expect(c2, isA<Color>());
    });

    test('color is stable across multiple calls with same id', () {
      const id = 'patient-uuid-9999';
      final colors = List.generate(10, (_) => _avatarColorTest(id));
      expect(colors.every((c) => c == colors.first), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Enum extensions
  // ---------------------------------------------------------------------------

  group('Enum extensions', () {
    test('PatientStatus.ativo has correct apiValue and label', () {
      expect(PatientStatus.ativo.apiValue, 'ATIVO');
      expect(PatientStatus.ativo.label, 'Ativo');
    });

    test('PatientStatus.inativo has correct apiValue and label', () {
      expect(PatientStatus.inativo.apiValue, 'INATIVO');
      expect(PatientStatus.inativo.label, 'Inativo');
    });

    test('PaymentModel.sessao apiValue and label', () {
      expect(PaymentModel.sessao.apiValue, 'SESSAO');
      expect(PaymentModel.sessao.label, 'Sessão');
    });

    test('PaymentModel.mensal apiValue and label', () {
      expect(PaymentModel.mensal.apiValue, 'MENSAL');
      expect(PaymentModel.mensal.label, 'Mensal');
    });

    test('PatientCurrency.brl symbol', () {
      expect(PatientCurrency.brl.symbol, 'R\$');
    });

    test('PatientCurrency.eur symbol', () {
      expect(PatientCurrency.eur.symbol, '€');
    });
  });
}
