import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

function serializeRate(r: {
  id: string;
  patientId: string;
  rate: unknown;
  effectiveFrom: Date;
  effectiveTo: Date | null;
}) {
  return {
    id: r.id,
    patientId: r.patientId,
    rate: Number(r.rate),
    effectiveFrom: r.effectiveFrom.toISOString().split('T')[0],
    effectiveTo: r.effectiveTo ? r.effectiveTo.toISOString().split('T')[0] : null,
  };
}

// ---------------------------------------------------------------------------
// GET /api/patients/:id/rates
// ---------------------------------------------------------------------------
router.get('/:id/rates', async (req: Request, res: Response) => {
  const id = req.params.id as string;

  const patient = await prisma.patient.findUnique({ where: { id } });
  if (!patient) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  const rates = await prisma.rateHistory.findMany({
    where: { patientId: id },
    orderBy: { effectiveFrom: 'desc' },
  });

  res.json(rates.map(serializeRate));
});

// ---------------------------------------------------------------------------
// POST /api/patients/:id/rates
// ---------------------------------------------------------------------------
router.post('/:id/rates', async (req: Request, res: Response) => {
  const id = req.params.id as string;
  const { rate, effectiveFrom } = req.body;

  const patient = await prisma.patient.findUnique({ where: { id } });
  if (!patient) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  const errors: string[] = [];
  if (rate === undefined || rate === null) errors.push('Taxa é obrigatória');
  else if (Number(rate) <= 0) errors.push('Taxa deve ser maior que zero');
  if (!effectiveFrom) errors.push('Data de vigência é obrigatória');

  if (errors.length > 0) {
    res.status(400).json({ message: errors.join('. ') });
    return;
  }

  const newEffectiveFrom = new Date(effectiveFrom as string);

  // Find current open rate (effectiveTo = null)
  const current = await prisma.rateHistory.findFirst({
    where: { patientId: id, effectiveTo: null },
    orderBy: { effectiveFrom: 'desc' },
  });

  // Business rule 1: new effectiveFrom must be strictly after current rate's effectiveFrom
  if (current && newEffectiveFrom <= current.effectiveFrom) {
    res.status(409).json({
      message: `A data deve ser posterior a ${current.effectiveFrom.toISOString().split('T')[0]}`,
      currentRateStart: current.effectiveFrom.toISOString().split('T')[0],
    });
    return;
  }

  // Business rule 2: close previous rate — effectiveTo = new effectiveFrom − 1 day
  if (current) {
    const closingDate = new Date(newEffectiveFrom);
    closingDate.setUTCDate(closingDate.getUTCDate() - 1);
    await prisma.rateHistory.update({
      where: { id: current.id },
      data: { effectiveTo: closingDate },
    });
  }

  // Business rule 3: new rate with effectiveTo = null
  const newRate = await prisma.rateHistory.create({
    data: {
      patientId: id,
      rate: Number(rate),
      effectiveFrom: newEffectiveFrom,
      effectiveTo: null,
    },
  });

  res.status(201).json(serializeRate(newRate));
});

export default router;
