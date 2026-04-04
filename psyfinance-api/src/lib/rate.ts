import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Returns the effective rate for a patient on a given date.
 * Finds the RateHistory entry where effectiveFrom <= date and
 * (effectiveTo is null OR effectiveTo >= date).
 *
 * Returns null if no rate is configured for that date.
 */
export async function getRateForDate(
  patientId: string,
  date: Date,
): Promise<number | null> {
  const normalizedDate = new Date(date);
  normalizedDate.setUTCHours(0, 0, 0, 0);

  const rateEntry = await prisma.rateHistory.findFirst({
    where: {
      patientId,
      effectiveFrom: { lte: normalizedDate },
      OR: [
        { effectiveTo: null },
        { effectiveTo: { gte: normalizedDate } },
      ],
    },
    orderBy: { effectiveFrom: 'desc' },
  });

  if (!rateEntry) return null;
  return Number(rateEntry.rate);
}

/**
 * Returns the effective rate for a patient in a given year/month.
 * Uses the first day of the month as the reference date.
 */
export async function getRateForMonth(
  patientId: string,
  year: number,
  month: number,
): Promise<number | null> {
  const date = new Date(Date.UTC(year, month - 1, 1));
  return getRateForDate(patientId, date);
}
