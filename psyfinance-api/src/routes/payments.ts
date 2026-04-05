import { Router, Request, Response } from 'express';
import { $Enums } from '@prisma/client';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function computeStatus(
  amountPaid: number,
  expectedAmount: number,
  year: number,
  month: number,
): $Enums.PaymentStatus {
  if (amountPaid >= expectedAmount) return 'PAGO';

  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth() + 1;
  const isPast =
    year < currentYear || (year === currentYear && month < currentMonth);

  if (isPast && amountPaid < expectedAmount) return 'ATRASADO';
  if (amountPaid > 0) return 'PARCIAL';
  return 'PENDENTE';
}

function serializePayment(payment: {
  id: string;
  sessionRecordId: string;
  amountPaid: unknown;
  status: string;
  revenueShareAmount: unknown;
  sessionRecord: { expectedAmount: unknown };
}) {
  return {
    id: payment.id,
    sessionRecordId: payment.sessionRecordId,
    amountPaid: Number(payment.amountPaid),
    status: payment.status,
    expectedAmount: Number(payment.sessionRecord.expectedAmount),
    revenueShareAmount:
      payment.revenueShareAmount != null
        ? Number(payment.revenueShareAmount)
        : null,
  };
}

// ---------------------------------------------------------------------------
// GET /api/payments?year=2026&month=3&status=all
// Returns all patient-month payment records for a given month.
// status accepts: PENDENTE | PARCIAL | PAGO | ATRASADO | all (default: all)
// ---------------------------------------------------------------------------

const STATUS_ORDER: Record<string, number> = {
  ATRASADO: 0,
  PARCIAL: 1,
  PENDENTE: 2,
  PAGO: 3,
};

router.get('/', async (req: Request, res: Response) => {
  const year = Number(req.query['year']);
  const month = Number(req.query['month']);
  const statusFilter = (req.query['status'] as string) || 'all';

  if (!year || !month || isNaN(year) || isNaN(month)) {
    res.status(400).json({ message: 'year e month são obrigatórios' });
    return;
  }

  const validStatuses = ['PENDENTE', 'PARCIAL', 'PAGO', 'ATRASADO', 'all'];
  if (!validStatuses.includes(statusFilter)) {
    res.status(400).json({ message: 'status inválido' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    orderBy: { name: 'asc' },
    include: {
      sessionRecords: {
        where: { year, month, deletedAt: null },
        include: { payment: true },
      },
    },
  });

  const rows: Array<{
    patient: { id: string; name: string; location: string; currency: string };
    sessionRecord: {
      id: string;
      month: number;
      year: number;
      sessionCount: number;
      expectedAmount: number;
    };
    payment: {
      id: string;
      amountPaid: number;
      status: string;
      revenueShareAmount: number | null;
    };
  }> = [];

  for (const patient of patients) {
    const sr = patient.sessionRecords[0];
    if (!sr || !sr.payment || sr.payment.deletedAt) continue;

    const amountPaid = Number(sr.payment.amountPaid);
    const expectedAmount = Number(sr.expectedAmount);
    const status = computeStatus(amountPaid, expectedAmount, year, month);

    rows.push({
      patient: {
        id: patient.id,
        name: patient.name,
        location: patient.location,
        currency: patient.currency,
      },
      sessionRecord: {
        id: sr.id,
        month: sr.month,
        year: sr.year,
        sessionCount: sr.sessionCount,
        expectedAmount,
      },
      payment: {
        id: sr.payment.id,
        amountPaid,
        status,
        revenueShareAmount:
          sr.payment.revenueShareAmount != null
            ? Number(sr.payment.revenueShareAmount)
            : null,
      },
    });
  }

  // Sort: ATRASADO → PARCIAL → PENDENTE → PAGO, then name ascending
  rows.sort((a, b) => {
    const oa = STATUS_ORDER[a.payment.status] ?? 3;
    const ob = STATUS_ORDER[b.payment.status] ?? 3;
    if (oa !== ob) return oa - ob;
    return a.patient.name.localeCompare(b.patient.name, 'pt-BR');
  });

  // Compute summary from ALL rows (always, regardless of filter)
  const makeZero = () => ({
    totalExpected: 0,
    totalReceived: 0,
    totalOutstanding: 0,
    countPaid: 0,
    countPending: 0,
    countOverdue: 0,
  });

  const summary: Record<string, ReturnType<typeof makeZero>> = {
    BRL: makeZero(),
    EUR: makeZero(),
  };

  for (const row of rows) {
    const cur = row.patient.currency as 'BRL' | 'EUR';
    const s = summary[cur] ?? makeZero();
    s.totalExpected += row.sessionRecord.expectedAmount;
    s.totalReceived += row.payment.amountPaid;
    s.totalOutstanding +=
      row.sessionRecord.expectedAmount - row.payment.amountPaid;
    if (row.payment.status === 'PAGO') {
      s.countPaid++;
    } else if (row.payment.status === 'ATRASADO') {
      s.countOverdue++;
    } else {
      s.countPending++;
    }
  }

  const filtered =
    statusFilter === 'all'
      ? rows
      : rows.filter((r) => r.payment.status === statusFilter);

  res.json({ summary, payments: filtered });
});

// ---------------------------------------------------------------------------
// GET /api/payments/:sessionRecordId
// ---------------------------------------------------------------------------

router.get('/:sessionRecordId', async (req: Request, res: Response) => {
  const sessionRecordId = req.params['sessionRecordId'] as string;

  const payment = await prisma.payment.findUnique({
    where: { sessionRecordId },
    include: { sessionRecord: true },
  });

  if (!payment || payment.deletedAt) {
    res.status(404).json({ message: 'Pagamento não encontrado' });
    return;
  }

  res.json(serializePayment(payment));
});

// ---------------------------------------------------------------------------
// PUT /api/payments/:sessionRecordId
// ---------------------------------------------------------------------------

router.put('/:sessionRecordId', async (req: Request, res: Response) => {
  const sessionRecordId = req.params['sessionRecordId'] as string;
  const { amountPaid } = req.body as { amountPaid: number };

  if (typeof amountPaid !== 'number' || amountPaid < 0) {
    res
      .status(400)
      .json({ message: 'amountPaid deve ser um número não-negativo' });
    return;
  }

  const existing = await prisma.payment.findUnique({
    where: { sessionRecordId },
    include: { sessionRecord: true },
  });

  if (!existing || existing.deletedAt) {
    res.status(404).json({ message: 'Pagamento não encontrado' });
    return;
  }

  const expectedAmount = Number(existing.sessionRecord.expectedAmount);
  const { year, month } = existing.sessionRecord;
  const status = computeStatus(amountPaid, expectedAmount, year, month);

  const updated = await prisma.payment.update({
    where: { sessionRecordId },
    data: { amountPaid, status },
    include: { sessionRecord: true },
  });

  res.json(serializePayment(updated));
});

export default router;
