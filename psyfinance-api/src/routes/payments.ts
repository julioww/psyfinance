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
