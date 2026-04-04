import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// GET /api/dashboard?year=2026
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      sessionRecords: {
        where: { year, deletedAt: null },
        include: { payment: true },
      },
    },
    orderBy: [{ location: 'asc' }, { name: 'asc' }],
  });

  // Initialize monthly buckets for each currency.
  const brlMonthly: Record<number, { expected: number; received: number }> = {};
  const eurMonthly: Record<number, { expected: number; received: number }> = {};
  for (let m = 1; m <= 12; m++) {
    brlMonthly[m] = { expected: 0, received: 0 };
    eurMonthly[m] = { expected: 0, received: 0 };
  }

  const brlCountries = new Set<string>();
  const eurCountries = new Set<string>();
  const patientSummaries: object[] = [];
  const repasses: object[] = [];

  for (const p of patients) {
    if (p.currency === 'BRL') brlCountries.add(p.location);
    else eurCountries.add(p.location);

    let totalSessions = 0;
    let totalExpected = 0;
    let totalReceived = 0;
    let totalRepass = 0;

    for (const record of p.sessionRecords) {
      const m = record.month;
      const expected = Number(record.expectedAmount);
      const received = record.payment ? Number(record.payment.amountPaid) : 0;
      const repass = record.payment?.revenueShareAmount
        ? Number(record.payment.revenueShareAmount)
        : 0;

      totalSessions += record.sessionCount;
      totalExpected += expected;
      totalReceived += received;
      totalRepass += repass;

      const monthly = p.currency === 'BRL' ? brlMonthly : eurMonthly;
      monthly[m]!.expected += expected;
      monthly[m]!.received += received;
    }

    const balance = totalExpected - totalReceived;

    patientSummaries.push({
      id: p.id,
      name: p.name,
      location: p.location,
      currency: p.currency,
      totalSessions,
      totalExpected,
      totalReceived,
      balance,
      hasOutstanding: balance > 0.005, // float tolerance
    });

    if (totalRepass > 0.005) {
      repasses.push({
        patientId: p.id,
        patientName: p.name,
        currency: p.currency,
        beneficiaryName: p.location,
        totalSessions,
        totalRepass,
      });
    }
  }

  // Sort: most outstanding first.
  (patientSummaries as { balance: number }[]).sort((a, b) => b.balance - a.balance);

  const toTotals = (monthly: Record<number, { expected: number; received: number }>) =>
    Array.from({ length: 12 }, (_, i) => ({
      month: i + 1,
      expected: monthly[i + 1]!.expected,
      received: monthly[i + 1]!.received,
    }));

  const ytd = (totals: { expected: number; received: number }[]) =>
    totals.reduce(
      (acc, m) => ({ expected: acc.expected + m.expected, received: acc.received + m.received }),
      { expected: 0, received: 0 },
    );

  const brlTotals = toTotals(brlMonthly);
  const eurTotals = toTotals(eurMonthly);

  res.json({
    year,
    BRL: {
      monthlyTotals: brlTotals,
      yearToDate: ytd(brlTotals),
      countries: Array.from(brlCountries).sort(),
    },
    EUR: {
      monthlyTotals: eurTotals,
      yearToDate: ytd(eurTotals),
      countries: Array.from(eurCountries).sort(),
    },
    patients: patientSummaries,
    repasses,
  });
});

// ---------------------------------------------------------------------------
// GET /api/dashboard/comparison?years=2023,2024,2025,2026
// ---------------------------------------------------------------------------

router.get('/comparison', async (req: Request, res: Response) => {
  const yearsParam = req.query['years'] as string;
  if (!yearsParam) {
    res.status(400).json({ message: 'years é obrigatório' });
    return;
  }

  const years = yearsParam
    .split(',')
    .map((y) => parseInt(y.trim(), 10))
    .filter((y) => !isNaN(y));

  if (years.length === 0) {
    res.status(400).json({ message: 'Nenhum ano válido informado' });
    return;
  }

  const records = await prisma.sessionRecord.findMany({
    where: {
      year: { in: years },
      deletedAt: null,
      patient: { status: 'ATIVO', deletedAt: null },
    },
    include: {
      patient: { select: { currency: true } },
      payment: { select: { amountPaid: true } },
    },
  });

  const result: Record<
    number,
    { BRL: { expected: number; received: number }; EUR: { expected: number; received: number } }
  > = {};

  for (const year of years) {
    result[year] = {
      BRL: { expected: 0, received: 0 },
      EUR: { expected: 0, received: 0 },
    };
  }

  for (const record of records) {
    const { year } = record;
    const currency = record.patient.currency as 'BRL' | 'EUR';
    result[year]![currency].expected += Number(record.expectedAmount);
    if (record.payment) {
      result[year]![currency].received += Number(record.payment.amountPaid);
    }
  }

  res.json(years.map((year) => ({ year, BRL: result[year]!.BRL, EUR: result[year]!.EUR })));
});

// ---------------------------------------------------------------------------
// CSV export helpers
// ---------------------------------------------------------------------------

const MONTHS_PT = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

function buildCsv(rows: (string | number)[][]): string {
  return rows.map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n');
}

function sendCsv(res: Response, filename: string, rows: (string | number)[][]): void {
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.send(buildCsv(rows));
}

// ---------------------------------------------------------------------------
// GET /api/dashboard/export/monthly-csv?year=2026
// ---------------------------------------------------------------------------

router.get('/export/monthly-csv', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const records = await prisma.sessionRecord.findMany({
    where: { year, deletedAt: null, patient: { status: 'ATIVO', deletedAt: null } },
    include: {
      patient: { select: { name: true, currency: true, location: true } },
      payment: { select: { amountPaid: true, status: true } },
    },
    orderBy: [{ month: 'asc' }, { patient: { name: 'asc' } }],
  });

  const header = ['Ano', 'Mês', 'Paciente', 'Localização', 'Moeda', 'Sessões', 'Esperado', 'Recebido', 'Status'];
  const rows = records.map((r) => [
    r.year,
    MONTHS_PT[r.month - 1]!,
    r.patient.name,
    r.patient.location,
    r.patient.currency,
    r.sessionCount,
    Number(r.expectedAmount).toFixed(2),
    r.payment ? Number(r.payment.amountPaid).toFixed(2) : '0.00',
    r.payment?.status ?? 'PENDENTE',
  ]);

  sendCsv(res, `mensal_${year}.csv`, [header, ...rows]);
});

// ---------------------------------------------------------------------------
// GET /api/dashboard/export/annual-csv?year=2026
// ---------------------------------------------------------------------------

router.get('/export/annual-csv', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      sessionRecords: {
        where: { year, deletedAt: null },
        include: { payment: { select: { amountPaid: true } } },
      },
    },
  });

  const brl = Array.from({ length: 12 }, () => ({ expected: 0, received: 0 }));
  const eur = Array.from({ length: 12 }, () => ({ expected: 0, received: 0 }));

  for (const p of patients) {
    for (const r of p.sessionRecords) {
      const bucket = p.currency === 'BRL' ? brl : eur;
      bucket[r.month - 1]!.expected += Number(r.expectedAmount);
      bucket[r.month - 1]!.received += r.payment ? Number(r.payment.amountPaid) : 0;
    }
  }

  const header = ['Mês', 'BRL Esperado', 'BRL Recebido', 'EUR Esperado', 'EUR Recebido'];
  const rows = Array.from({ length: 12 }, (_, i) => [
    MONTHS_PT[i]!,
    brl[i]!.expected.toFixed(2),
    brl[i]!.received.toFixed(2),
    eur[i]!.expected.toFixed(2),
    eur[i]!.received.toFixed(2),
  ]);

  sendCsv(res, `anual_${year}.csv`, [header, ...rows]);
});

// ---------------------------------------------------------------------------
// GET /api/dashboard/export/summary-csv?year=2026
// ---------------------------------------------------------------------------

router.get('/export/summary-csv', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      sessionRecords: {
        where: { year, deletedAt: null },
        include: { payment: { select: { amountPaid: true } } },
      },
    },
    orderBy: [{ location: 'asc' }, { name: 'asc' }],
  });

  const header = ['Paciente', 'Localização', 'Moeda', 'Sessões', 'Esperado', 'Recebido', 'Saldo'];
  const rows = patients.map((p) => {
    const totalSessions = p.sessionRecords.reduce((a, r) => a + r.sessionCount, 0);
    const totalExpected = p.sessionRecords.reduce((a, r) => a + Number(r.expectedAmount), 0);
    const totalReceived = p.sessionRecords.reduce(
      (a, r) => a + (r.payment ? Number(r.payment.amountPaid) : 0),
      0,
    );
    return [
      p.name,
      p.location,
      p.currency,
      totalSessions,
      totalExpected.toFixed(2),
      totalReceived.toFixed(2),
      (totalExpected - totalReceived).toFixed(2),
    ];
  });

  sendCsv(res, `resumo_${year}.csv`, [header, ...rows]);
});

// ---------------------------------------------------------------------------
// PDF stubs — not implemented
// ---------------------------------------------------------------------------

router.get('/export/monthly-pdf', (_req: Request, res: Response) => {
  res.status(501).json({ message: 'Exportação PDF ainda não disponível' });
});

router.get('/export/annual-pdf', (_req: Request, res: Response) => {
  res.status(501).json({ message: 'Exportação PDF ainda não disponível' });
});

router.get('/export/summary-pdf', (_req: Request, res: Response) => {
  res.status(501).json({ message: 'Exportação PDF ainda não disponível' });
});

export default router;
