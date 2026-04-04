import { Router, Request, Response } from 'express';
import { PaymentModel, Currency, Status } from '@prisma/client';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function computeCurrentRate(
  rateHistory: Array<{ rate: unknown; effectiveFrom: Date; effectiveTo: Date | null }>,
): number | null {
  if (!rateHistory || rateHistory.length === 0) return null;

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // prefer entries whose effectiveFrom <= today and effectiveTo is null or >= today
  const active = rateHistory
    .filter((r) => r.effectiveFrom <= today && (r.effectiveTo === null || r.effectiveTo >= today))
    .sort((a, b) => b.effectiveFrom.getTime() - a.effectiveFrom.getTime());

  if (active.length > 0) return Number(active[0].rate);

  // fallback: most-recent rate regardless of dates
  const sorted = [...rateHistory].sort(
    (a, b) => b.effectiveFrom.getTime() - a.effectiveFrom.getTime(),
  );
  return sorted.length > 0 ? Number(sorted[0].rate) : null;
}

function serialize(patient: Record<string, unknown> & { rateHistory?: unknown[] }): object {
  const { rateHistory, ...rest } = patient;
  return {
    ...rest,
    currentRate: rateHistory
      ? computeCurrentRate(
          rateHistory as Array<{ rate: unknown; effectiveFrom: Date; effectiveTo: Date | null }>,
        )
      : null,
  };
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// ---------------------------------------------------------------------------
// GET /api/patients
// ---------------------------------------------------------------------------
router.get('/', async (req: Request, res: Response) => {
  const { status, location, paymentModel, currency, q } = req.query as Record<string, string>;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const where: Record<string, any> = {};

  if (status === 'all') {
    // no status filter
  } else if (status === 'INATIVO') {
    where.status = 'INATIVO';
  } else {
    where.status = 'ATIVO'; // default
  }

  if (location) where.location = { contains: location, mode: 'insensitive' };
  if (paymentModel && ['SESSAO', 'MENSAL'].includes(paymentModel)) {
    where.paymentModel = paymentModel;
  }
  if (currency && ['BRL', 'EUR'].includes(currency)) {
    where.currency = currency;
  }
  if (q) where.name = { contains: q, mode: 'insensitive' };

  const patients = await prisma.patient.findMany({
    where,
    include: { rateHistory: true },
    orderBy: { name: 'asc' },
  });

  res.json(patients.map((p) => serialize(p as unknown as Record<string, unknown> & { rateHistory: unknown[] })));
});

// ---------------------------------------------------------------------------
// POST /api/patients
// ---------------------------------------------------------------------------
router.post('/', async (req: Request, res: Response) => {
  const { name, email, location, paymentModel, currency, initialRate, rateEffectiveFrom, cpf, notes } = req.body;

  const errors: string[] = [];
  if (!name) errors.push('Nome é obrigatório');
  if (!email) errors.push('Email é obrigatório');
  else if (!EMAIL_RE.test(email)) errors.push('Email inválido');
  if (!location) errors.push('País/localização é obrigatório');
  if (!paymentModel || !['SESSAO', 'MENSAL'].includes(paymentModel))
    errors.push('Forma de pagamento inválida (SESSAO ou MENSAL)');
  if (!currency || !['BRL', 'EUR'].includes(currency)) errors.push('Moeda inválida (BRL ou EUR)');
  if (initialRate === undefined || initialRate === null) errors.push('Taxa inicial é obrigatória');
  else if (Number(initialRate) <= 0) errors.push('Taxa inicial deve ser maior que zero');
  if (!rateEffectiveFrom) errors.push('Data de vigência da taxa é obrigatória');

  if (errors.length > 0) {
    res.status(400).json({ message: errors.join('. ') });
    return;
  }

  const patient = await prisma.patient.create({
    data: {
      name,
      email,
      cpf: cpf || null,
      location,
      paymentModel: paymentModel as PaymentModel,
      currency: currency as Currency,
      notes: notes || null,
      rateHistory: {
        create: {
          rate: Number(initialRate),
          effectiveFrom: new Date(rateEffectiveFrom),
        },
      },
    },
    include: { rateHistory: true },
  });

  res.status(201).json(serialize(patient as unknown as Record<string, unknown> & { rateHistory: unknown[] }));
});

// ---------------------------------------------------------------------------
// GET /api/patients/:id/summary
// ---------------------------------------------------------------------------
router.get('/:id/summary', async (req: Request, res: Response) => {
  const id = req.params.id as string;
  const year = parseInt(
    (req.query['year'] as string) || String(new Date().getFullYear()),
    10,
  );

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const patient = (await prisma.patient.findUnique({
    where: { id },
    include: { rateHistory: { orderBy: { effectiveFrom: 'desc' } } },
  })) as any;

  if (!patient) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sessionRecords = (await prisma.sessionRecord.findMany({
    where: { patientId: id, year },
    include: { payment: true },
  })) as any[];

  const months = Array.from({ length: 12 }, (_, i) => {
    const month = i + 1;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const record: any = sessionRecords.find((r: any) => r.month === month);
    if (!record) {
      return {
        month,
        sessionRecordId: null,
        sessionCount: null,
        expectedAmount: null,
        amountPaid: null,
        balance: null,
        status: null,
        observations: null,
      };
    }
    const expectedAmount = Number(record.expectedAmount);
    const amountPaid = record.payment ? Number(record.payment.amountPaid) : 0;
    return {
      month,
      sessionRecordId: record.id,
      sessionCount: record.sessionCount,
      expectedAmount,
      amountPaid,
      balance: expectedAmount - amountPaid,
      status: record.payment?.status ?? null,
      observations: record.observations ?? null,
    };
  });

  res.json({
    patient: serialize(patient),
    rates: patient.rateHistory.map((r: any) => ({
      id: r.id,
      patientId: r.patientId,
      rate: Number(r.rate),
      effectiveFrom: r.effectiveFrom.toISOString().split('T')[0],
      effectiveTo: r.effectiveTo ? r.effectiveTo.toISOString().split('T')[0] : null,
    })),
    months,
  });
});

// ---------------------------------------------------------------------------
// GET /api/patients/:id
// ---------------------------------------------------------------------------
router.get('/:id', async (req: Request, res: Response) => {
  const id = req.params.id as string;
  const patient = await prisma.patient.findUnique({
    where: { id },
    include: { rateHistory: { orderBy: { effectiveFrom: 'desc' } } },
  });

  if (!patient) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  res.json(serialize(patient as unknown as Record<string, unknown> & { rateHistory: unknown[] }));
});

// ---------------------------------------------------------------------------
// PUT /api/patients/:id
// ---------------------------------------------------------------------------
router.put('/:id', async (req: Request, res: Response) => {
  const id = req.params.id as string;
  const { name, email, cpf, location, paymentModel, currency, notes, status } = req.body;

  const errors: string[] = [];
  if (email !== undefined && !EMAIL_RE.test(email)) errors.push('Email inválido');
  if (paymentModel !== undefined && !['SESSAO', 'MENSAL'].includes(paymentModel))
    errors.push('Forma de pagamento inválida (SESSAO ou MENSAL)');
  if (currency !== undefined && !['BRL', 'EUR'].includes(currency))
    errors.push('Moeda inválida (BRL ou EUR)');
  if (status !== undefined && !['ATIVO', 'INATIVO'].includes(status))
    errors.push('Status inválido (ATIVO ou INATIVO)');

  if (errors.length > 0) {
    res.status(400).json({ message: errors.join('. ') });
    return;
  }

  const existing = await prisma.patient.findUnique({ where: { id } });
  if (!existing) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  const updated = await prisma.patient.update({
    where: { id },
    data: {
      ...(name !== undefined && { name }),
      ...(email !== undefined && { email }),
      ...(cpf !== undefined && { cpf }),
      ...(location !== undefined && { location }),
      ...(paymentModel !== undefined && { paymentModel: paymentModel as PaymentModel }),
      ...(currency !== undefined && { currency: currency as Currency }),
      ...(notes !== undefined && { notes }),
      ...(status !== undefined && { status: status as Status }),
    },
    include: { rateHistory: true },
  });

  res.json(serialize(updated as unknown as Record<string, unknown> & { rateHistory: unknown[] }));
});

// ---------------------------------------------------------------------------
// DELETE /api/patients/:id  — soft-delete (status → INATIVO)
// ---------------------------------------------------------------------------
router.delete('/:id', async (req: Request, res: Response) => {
  const id = req.params.id as string;
  const existing = await prisma.patient.findUnique({ where: { id } });
  if (!existing) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  await prisma.patient.update({
    where: { id },
    data: { status: 'INATIVO', deletedAt: new Date() },
  });

  res.status(204).send();
});

export default router;
