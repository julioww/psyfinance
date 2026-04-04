import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function serializeRecord(r: {
  id: string;
  patientId: string;
  year: number;
  month: number;
  sessionDates: unknown;
  sessionCount: number;
  expectedAmount: unknown;
  observations: string | null;
  isReposicao: boolean;
  createdAt: Date;
  updatedAt: Date;
  payment: {
    id: string;
    amountPaid: unknown;
    status: string;
    revenueShareAmount: unknown;
  } | null;
}) {
  return {
    id: r.id,
    patientId: r.patientId,
    year: r.year,
    month: r.month,
    sessionDates: r.sessionDates as string[],
    sessionCount: r.sessionCount,
    expectedAmount: Number(r.expectedAmount),
    observations: r.observations,
    isReposicao: r.isReposicao,
    payment: r.payment
      ? {
          id: r.payment.id,
          amountPaid: Number(r.payment.amountPaid),
          status: r.payment.status,
          revenueShareAmount: r.payment.revenueShareAmount != null
            ? Number(r.payment.revenueShareAmount)
            : null,
        }
      : null,
    createdAt: r.createdAt.toISOString(),
    updatedAt: r.updatedAt.toISOString(),
  };
}

// ---------------------------------------------------------------------------
// GET /api/sessions/:patientId/:year/:month
// ---------------------------------------------------------------------------

router.get('/:patientId/:year/:month', async (req: Request, res: Response) => {
  const patientId = req.params.patientId as string;
  const year = parseInt(req.params.year as string, 10);
  const month = parseInt(req.params.month as string, 10);

  if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
    res.status(400).json({ message: 'Ano ou mês inválido' });
    return;
  }

  const record = await prisma.sessionRecord.findUnique({
    where: { patientId_year_month: { patientId, year, month } },
    include: { payment: true },
  });

  if (!record || record.deletedAt) {
    res.status(404).json({ message: 'Registro de sessão não encontrado' });
    return;
  }

  res.json(serializeRecord(record));
});

// ---------------------------------------------------------------------------
// POST /api/sessions/:patientId/:year/:month  (upsert)
// ---------------------------------------------------------------------------

router.post('/:patientId/:year/:month', async (req: Request, res: Response) => {
  const patientId = req.params.patientId as string;
  const year = parseInt(req.params.year as string, 10);
  const month = parseInt(req.params.month as string, 10);

  if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
    res.status(400).json({ message: 'Ano ou mês inválido' });
    return;
  }

  const { sessionDates, observations, isReposicao } = req.body as {
    sessionDates: string[];
    observations?: string;
    isReposicao?: boolean;
  };

  // Validate patient exists
  const patient = await prisma.patient.findUnique({
    where: { id: patientId },
    include: {
      rateHistory: { orderBy: { effectiveFrom: 'asc' } },
    },
  });
  if (!patient || patient.deletedAt) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  // Validate sessionDates is an array
  if (!Array.isArray(sessionDates)) {
    res.status(400).json({ message: 'sessionDates deve ser um array' });
    return;
  }

  // Validate each date falls within the given month
  for (const d of sessionDates) {
    const parsed = new Date(d);
    if (isNaN(parsed.getTime())) {
      res.status(400).json({ message: `Data inválida: ${d}` });
      return;
    }
    if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() + 1 !== month) {
      res.status(400).json({ message: `Data ${d} fora do mês especificado` });
      return;
    }
  }

  // Business rule 1: sessionCount = sessionDates.length
  const sessionCount = sessionDates.length;

  // Business rule 2: find rate effective on the 1st of the month
  const firstOfMonth = new Date(`${year}-${String(month).padStart(2, '0')}-01`);
  const effectiveRate = patient.rateHistory.find((r) => {
    const from = r.effectiveFrom;
    const to = r.effectiveTo;
    return from <= firstOfMonth && (to === null || to >= firstOfMonth);
  });
  const rate = effectiveRate ? Number(effectiveRate.rate) : 0;

  // MENSAL: fixed monthly rate; SESSAO: sessionCount × rate
  const expectedAmount =
    patient.paymentModel === 'MENSAL' ? rate : sessionCount * rate;

  // Upsert the session record
  const record = await prisma.sessionRecord.upsert({
    where: { patientId_year_month: { patientId, year, month } },
    create: {
      patientId,
      year,
      month,
      sessionDates,
      sessionCount,
      expectedAmount,
      observations: observations ?? null,
      isReposicao: isReposicao ?? false,
    },
    update: {
      sessionDates,
      sessionCount,
      expectedAmount,
      observations: observations ?? null,
      isReposicao: isReposicao ?? false,
      deletedAt: null,
    },
    include: { payment: true },
  });

  // Business rules 4 & 5: Payment
  if (!record.payment) {
    // Rule 4: no Payment row exists — create one
    await prisma.payment.create({
      data: {
        sessionRecordId: record.id,
        amountPaid: 0,
        status: 'PENDENTE',
      },
    });

    const updated = await prisma.sessionRecord.findUnique({
      where: { id: record.id },
      include: { payment: true },
    });
    res.json(serializeRecord(updated!));
  } else {
    // Rule 5: Payment exists — expectedAmount already updated on SessionRecord,
    // do not touch amountPaid
    res.json(serializeRecord(record));
  }
});

export default router;
