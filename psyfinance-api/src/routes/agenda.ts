import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';

const router = Router();

// ---------------------------------------------------------------------------
// GET /api/agenda?year=2026&month=3
//
// Returns all session dates for the given month, expanded from
// SessionRecord.sessionDates. Each date in each patient's sessionDates array
// becomes one entry. Sorted by date asc, then patient name asc.
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response) => {
  const year  = parseInt(req.query['year']  as string, 10);
  const month = parseInt(req.query['month'] as string, 10);

  if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
    res.status(400).json({ message: 'year e month são obrigatórios e devem ser válidos' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      rateHistory: {
        where: { effectiveTo: null },
        take: 1,
      },
      sessionRecords: {
        where: { year, month, deletedAt: null },
      },
    },
    orderBy: { name: 'asc' },
  });

  const sessions: Array<{
    date: string;
    dayOfWeek: number;
    patient: {
      id: string;
      name: string;
      currency: string;
      currentRate: number | null;
      location: string;
    };
    sessionRecord: {
      id: string;
      observations: string | null;
      isReposicao: boolean;
    };
  }> = [];

  for (const patient of patients) {
    const currentRate =
      patient.rateHistory.length > 0
        ? Number(patient.rateHistory[0]!.rate)
        : null;

    for (const record of patient.sessionRecords) {
      const dates = record.sessionDates as string[];

      for (const dateStr of dates) {
        // dayOfWeek: 1=Mon … 7=Sun (ISO weekday)
        const d = new Date(dateStr + 'T00:00:00');
        const jsDay = d.getDay(); // 0=Sun … 6=Sat
        const isoDay = jsDay === 0 ? 7 : jsDay;

        sessions.push({
          date: dateStr,
          dayOfWeek: isoDay,
          patient: {
            id: patient.id,
            name: patient.name,
            currency: patient.currency,
            currentRate,
            location: patient.location,
          },
          sessionRecord: {
            id: record.id,
            observations: record.observations,
            isReposicao: record.isReposicao,
          },
        });
      }
    }
  }

  // Sort: date asc, then patient name asc within same date
  sessions.sort((a, b) => {
    if (a.date !== b.date) return a.date < b.date ? -1 : 1;
    return a.patient.name.localeCompare(b.patient.name, 'pt-BR');
  });

  res.json({ sessions });
});

export default router;
