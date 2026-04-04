import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// GET /api/monthly-view?year=2026&month=3
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  const month = parseInt(req.query['month'] as string, 10);

  if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
    res.status(400).json({ message: 'year e month são obrigatórios e devem ser válidos' });
    return;
  }

  // Single query: all active patients with their session record (if any) for the month.
  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      rateHistory: {
        where: { effectiveTo: null },
        take: 1,
      },
      sessionRecords: {
        where: { year, month, deletedAt: null },
        include: { payment: true },
        take: 1,
      },
    },
    orderBy: [{ location: 'asc' }, { name: 'asc' }],
  });

  // Build per-patient rows.
  const rows = patients.map((p) => {
    const record = p.sessionRecords[0] ?? null;
    const payment = record?.payment ?? null;
    const currentRate =
      p.rateHistory.length > 0 ? Number(p.rateHistory[0]!.rate) : null;

    return {
      patient: {
        id: p.id,
        name: p.name,
        location: p.location,
        currency: p.currency,
        paymentModel: p.paymentModel,
        currentRate,
      },
      sessionRecord: record
        ? {
            id: record.id,
            sessionDates: record.sessionDates,
            sessionCount: record.sessionCount,
            expectedAmount: Number(record.expectedAmount),
            observations: record.observations,
            isReposicao: record.isReposicao,
          }
        : null,
      payment: payment
        ? {
            id: payment.id,
            amountPaid: Number(payment.amountPaid),
            status: payment.status,
            revenueShareAmount:
              payment.revenueShareAmount != null
                ? Number(payment.revenueShareAmount)
                : null,
          }
        : null,
    };
  });

  // Build summary keyed by currency (never by country).
  const summary: Record<string, { totalExpected: number; totalReceived: number }> = {
    BRL: { totalExpected: 0, totalReceived: 0 },
    EUR: { totalExpected: 0, totalReceived: 0 },
  };

  for (const row of rows) {
    const c = row.patient.currency as 'BRL' | 'EUR';
    if (row.sessionRecord) {
      summary[c]!.totalExpected += row.sessionRecord.expectedAmount;
    }
    if (row.payment) {
      summary[c]!.totalReceived += row.payment.amountPaid;
    }
  }

  res.json({ patients: rows, summary });
});

export default router;
