import { Router, Request, Response } from 'express';
import { $Enums } from '@prisma/client';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function serializeConfig(config: {
  id: string;
  patientId: string;
  shareType: $Enums.ShareType;
  shareValue: unknown;
  beneficiaryName: string;
  active: boolean;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: config.id,
    patientId: config.patientId,
    shareType: config.shareType,
    shareValue: Number(config.shareValue),
    beneficiaryName: config.beneficiaryName,
    active: config.active,
    createdAt: config.createdAt.toISOString(),
    updatedAt: config.updatedAt.toISOString(),
  };
}

// ---------------------------------------------------------------------------
// GET /api/patients/:id/revenue-share
// ---------------------------------------------------------------------------

router.get('/:id/revenue-share', async (req: Request, res: Response) => {
  const { id } = req.params as { id: string };

  const config = await prisma.revenueShareConfig.findUnique({
    where: { patientId: id },
  });

  if (!config || !config.active) {
    res.status(404).json({ message: 'Configuração de repasse não encontrada' });
    return;
  }

  res.json(serializeConfig(config));
});

// ---------------------------------------------------------------------------
// POST /api/patients/:id/revenue-share  — create or update
// ---------------------------------------------------------------------------

router.post('/:id/revenue-share', async (req: Request, res: Response) => {
  const { id } = req.params as { id: string };
  const { shareType, shareValue, beneficiaryName } = req.body as {
    shareType: string;
    shareValue: number;
    beneficiaryName: string;
  };

  if (!['PERCENTAGE', 'FIXED_PER_SESSION'].includes(shareType)) {
    res.status(400).json({ message: 'shareType inválido. Use PERCENTAGE ou FIXED_PER_SESSION' });
    return;
  }

  if (typeof shareValue !== 'number' || shareValue <= 0) {
    res.status(400).json({ message: 'shareValue deve ser um número positivo' });
    return;
  }

  if (typeof beneficiaryName !== 'string' || !beneficiaryName.trim()) {
    res.status(400).json({ message: 'beneficiaryName é obrigatório' });
    return;
  }

  const patient = await prisma.patient.findUnique({ where: { id } });
  if (!patient || patient.deletedAt) {
    res.status(404).json({ message: 'Paciente não encontrado' });
    return;
  }

  const config = await prisma.revenueShareConfig.upsert({
    where: { patientId: id },
    create: {
      patientId: id,
      shareType: shareType as $Enums.ShareType,
      shareValue,
      beneficiaryName: beneficiaryName.trim(),
      active: true,
    },
    update: {
      shareType: shareType as $Enums.ShareType,
      shareValue,
      beneficiaryName: beneficiaryName.trim(),
      active: true,
    },
  });

  res.json(serializeConfig(config));
});

// ---------------------------------------------------------------------------
// DELETE /api/patients/:id/revenue-share  — deactivate (active = false)
// ---------------------------------------------------------------------------

router.delete('/:id/revenue-share', async (req: Request, res: Response) => {
  const { id } = req.params as { id: string };

  const existing = await prisma.revenueShareConfig.findUnique({
    where: { patientId: id },
  });

  if (!existing) {
    res.status(404).json({ message: 'Configuração de repasse não encontrada' });
    return;
  }

  await prisma.revenueShareConfig.update({
    where: { patientId: id },
    data: { active: false },
  });

  res.status(204).send();
});

export default router;
