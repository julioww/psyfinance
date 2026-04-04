import { PrismaClient, PaymentModel, Currency, Status, PaymentStatus } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  // ─── Patients ────────────────────────────────────────────────────────────
  const ana = await prisma.patient.upsert({
    where: { id: 'patient-ana-00000000-0000-0000-0000-000000000001' },
    update: {},
    create: {
      id: 'patient-ana-00000000-0000-0000-0000-000000000001',
      name: 'Ana Beatriz Santos',
      email: 'ana.beatriz@email.com',
      cpf: '123.456.789-00',
      location: 'Brasil',
      status: Status.ATIVO,
      paymentModel: PaymentModel.SESSAO,
      currency: Currency.BRL,
      notes: 'Sessões semanais às quintas-feiras.',
    },
  });

  const carlos = await prisma.patient.upsert({
    where: { id: 'patient-carlos-0000-0000-0000-000000000002' },
    update: {},
    create: {
      id: 'patient-carlos-0000-0000-0000-000000000002',
      name: 'Carlos Eduardo Lima',
      email: 'carlos.lima@email.com',
      cpf: '987.654.321-00',
      location: 'Brasil',
      status: Status.ATIVO,
      paymentModel: PaymentModel.MENSAL,
      currency: Currency.BRL,
      notes: 'Pagamento mensal, 4 sessões fixas por mês.',
    },
  });

  const mariana = await prisma.patient.upsert({
    where: { id: 'patient-mariana-000-0000-0000-000000000003' },
    update: {},
    create: {
      id: 'patient-mariana-000-0000-0000-000000000003',
      name: 'Mariana Oliveira',
      email: 'mariana.oliveira@email.com',
      cpf: '111.222.333-44',
      location: 'Brasil',
      status: Status.ATIVO,
      paymentModel: PaymentModel.SESSAO,
      currency: Currency.BRL,
    },
  });

  const felix = await prisma.patient.upsert({
    where: { id: 'patient-felix-0000-0000-0000-000000000004' },
    update: {},
    create: {
      id: 'patient-felix-0000-0000-0000-000000000004',
      name: 'Félix Müller',
      email: 'felix.muller@email.de',
      location: 'Alemanha',
      status: Status.ATIVO,
      paymentModel: PaymentModel.SESSAO,
      currency: Currency.EUR,
      notes: 'Sessões online, fuso horário Europa/Berlim.',
    },
  });

  const claire = await prisma.patient.upsert({
    where: { id: 'patient-claire-000-0000-0000-000000000005' },
    update: {},
    create: {
      id: 'patient-claire-000-0000-0000-000000000005',
      name: 'Claire Dubois',
      email: 'claire.dubois@email.fr',
      location: 'França',
      status: Status.ATIVO,
      paymentModel: PaymentModel.SESSAO,
      currency: Currency.EUR,
      notes: 'Sessões online, fuso horário Europe/Paris.',
    },
  });

  console.log('Patients created:', [ana.name, carlos.name, mariana.name, felix.name, claire.name]);

  // ─── Rate History ─────────────────────────────────────────────────────────
  // Ana: rate changed from R$200 to R$220 starting March 2025
  await prisma.rateHistory.upsert({
    where: { id: 'rate-ana-01-00000-0000-0000-000000000001' },
    update: {},
    create: {
      id: 'rate-ana-01-00000-0000-0000-000000000001',
      patientId: ana.id,
      rate: 200.00,
      effectiveFrom: new Date('2024-01-01'),
      effectiveTo: new Date('2025-02-28'),
    },
  });
  await prisma.rateHistory.upsert({
    where: { id: 'rate-ana-02-00000-0000-0000-000000000002' },
    update: {},
    create: {
      id: 'rate-ana-02-00000-0000-0000-000000000002',
      patientId: ana.id,
      rate: 220.00,
      effectiveFrom: new Date('2025-03-01'),
      effectiveTo: null,
    },
  });

  // Carlos: flat R$800/month (mensal), rate changed from R$750 to R$800 in 2025
  await prisma.rateHistory.upsert({
    where: { id: 'rate-carlos-01-000-0000-0000-000000000003' },
    update: {},
    create: {
      id: 'rate-carlos-01-000-0000-0000-000000000003',
      patientId: carlos.id,
      rate: 750.00,
      effectiveFrom: new Date('2024-01-01'),
      effectiveTo: new Date('2024-12-31'),
    },
  });
  await prisma.rateHistory.upsert({
    where: { id: 'rate-carlos-02-000-0000-0000-000000000004' },
    update: {},
    create: {
      id: 'rate-carlos-02-000-0000-0000-000000000004',
      patientId: carlos.id,
      rate: 800.00,
      effectiveFrom: new Date('2025-01-01'),
      effectiveTo: null,
    },
  });

  // Mariana: single rate R$180
  await prisma.rateHistory.upsert({
    where: { id: 'rate-mariana-01-00-0000-0000-000000000005' },
    update: {},
    create: {
      id: 'rate-mariana-01-00-0000-0000-000000000005',
      patientId: mariana.id,
      rate: 180.00,
      effectiveFrom: new Date('2024-06-01'),
      effectiveTo: null,
    },
  });

  // Félix: €90/session
  await prisma.rateHistory.upsert({
    where: { id: 'rate-felix-01-0000-0000-0000-000000000006' },
    update: {},
    create: {
      id: 'rate-felix-01-0000-0000-0000-000000000006',
      patientId: felix.id,
      rate: 90.00,
      effectiveFrom: new Date('2024-01-01'),
      effectiveTo: null,
    },
  });

  // Claire: €85/session
  await prisma.rateHistory.upsert({
    where: { id: 'rate-claire-01-000-0000-0000-000000000007' },
    update: {},
    create: {
      id: 'rate-claire-01-000-0000-0000-000000000007',
      patientId: claire.id,
      rate: 85.00,
      effectiveFrom: new Date('2024-01-01'),
      effectiveTo: null,
    },
  });

  console.log('Rate history created.');

  // ─── Session Records & Payments ─────────────────────────────────────────
  // Helper to create session + payment
  async function createSessionAndPayment(
    sessionId: string,
    paymentId: string,
    patientId: string,
    year: number,
    month: number,
    sessionDates: string[],
    rate: number,
    status: PaymentStatus,
    amountPaid: number,
  ) {
    const sessionCount = sessionDates.length;
    const expectedAmount = sessionCount * rate;

    const session = await prisma.sessionRecord.upsert({
      where: { id: sessionId },
      update: {},
      create: {
        id: sessionId,
        patientId,
        year,
        month,
        sessionDates,
        sessionCount,
        expectedAmount,
      },
    });

    await prisma.payment.upsert({
      where: { id: paymentId },
      update: {},
      create: {
        id: paymentId,
        sessionRecordId: session.id,
        amountPaid,
        status,
      },
    });
  }

  // Ana — February & March 2025
  await createSessionAndPayment(
    'sess-ana-2025-02-00000-000000000001',
    'pay-ana-2025-02-000000-000000000001',
    ana.id, 2025, 2,
    ['06/02', '13/02', '20/02', '27/02'],
    200.00,
    PaymentStatus.PAGO,
    800.00,
  );
  await createSessionAndPayment(
    'sess-ana-2025-03-00000-000000000002',
    'pay-ana-2025-03-000000-000000000002',
    ana.id, 2025, 3,
    ['06/03', '13/03', '20/03', '27/03'],
    220.00, // rate changed in March
    PaymentStatus.PENDENTE,
    0,
  );

  // Carlos — February & March 2025 (mensal, 4 sessions/month fixed)
  await createSessionAndPayment(
    'sess-carlos-2025-02-0000-000000000003',
    'pay-carlos-2025-02-000-000000000003',
    carlos.id, 2025, 2,
    ['04/02', '11/02', '18/02', '25/02'],
    800.00,
    PaymentStatus.PAGO,
    800.00,
  );
  await createSessionAndPayment(
    'sess-carlos-2025-03-0000-000000000004',
    'pay-carlos-2025-03-000-000000000004',
    carlos.id, 2025, 3,
    ['04/03', '11/03', '18/03', '25/03'],
    800.00,
    PaymentStatus.PARCIAL,
    400.00,
  );

  // Mariana — February & March 2025
  await createSessionAndPayment(
    'sess-mariana-2025-02-00-000000000005',
    'pay-mariana-2025-02-0000-000000000005',
    mariana.id, 2025, 2,
    ['05/02', '12/02', '19/02'],
    180.00,
    PaymentStatus.PAGO,
    540.00,
  );
  await createSessionAndPayment(
    'sess-mariana-2025-03-00-000000000006',
    'pay-mariana-2025-03-0000-000000000006',
    mariana.id, 2025, 3,
    ['05/03', '12/03'],
    180.00,
    PaymentStatus.ATRASADO,
    0,
  );

  // Félix — February & March 2025
  await createSessionAndPayment(
    'sess-felix-2025-02-0000-000000000007',
    'pay-felix-2025-02-00000-000000000007',
    felix.id, 2025, 2,
    ['07/02', '14/02', '21/02', '28/02'],
    90.00,
    PaymentStatus.PAGO,
    360.00,
  );
  await createSessionAndPayment(
    'sess-felix-2025-03-0000-000000000008',
    'pay-felix-2025-03-00000-000000000008',
    felix.id, 2025, 3,
    ['07/03', '14/03', '21/03'],
    90.00,
    PaymentStatus.PENDENTE,
    0,
  );

  // Claire — February & March 2025
  await createSessionAndPayment(
    'sess-claire-2025-02-000-000000000009',
    'pay-claire-2025-02-0000-000000000009',
    claire.id, 2025, 2,
    ['03/02', '10/02', '17/02', '24/02'],
    85.00,
    PaymentStatus.PAGO,
    340.00,
  );
  await createSessionAndPayment(
    'sess-claire-2025-03-000-000000000010',
    'pay-claire-2025-03-0000-000000000010',
    claire.id, 2025, 3,
    ['03/03', '10/03', '17/03'],
    85.00,
    PaymentStatus.PAGO,
    255.00,
  );

  console.log('Session records and payments created.');
  console.log('Seed complete!');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
