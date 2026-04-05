/**
 * One-shot script: recalculates expectedAmount (and revenueShareAmount) for
 * every SessionRecord that currently has expectedAmount = 0 but has at least
 * one session date — i.e. records that were written while the timezone bug was
 * present in the POST /api/sessions route.
 *
 * Run with:
 *   npx ts-node src/scripts/recalculate-expected-amounts.ts
 */

import { prisma } from '../lib/prisma';

async function main() {
  // Load all session records with expectedAmount = 0 that have dates
  const records = await prisma.sessionRecord.findMany({
    where: {
      expectedAmount: 0,
      deletedAt: null,
    },
    include: {
      patient: {
        include: {
          rateHistory: { orderBy: { effectiveFrom: 'asc' } },
          revenueShareConfig: true,
        },
      },
      payment: true,
    },
  });

  if (records.length === 0) {
    console.log('No records with expectedAmount = 0 found. Nothing to do.');
    return;
  }

  console.log(`Found ${records.length} record(s) to recalculate.\n`);
  let fixed = 0;
  let skipped = 0;

  for (const record of records) {
    const { patient, year, month } = record;
    const sessionDates = record.sessionDates as string[];

    if (sessionDates.length === 0) {
      console.log(`  SKIP  ${patient.name} ${year}/${month} — no session dates`);
      skipped++;
      continue;
    }

    // Find rate effective on the 1st of the month (local midnight, same as
    // the corrected sessions route).
    const firstOfMonth = new Date(year, month - 1, 1);

    const effectiveRateEntry = patient.rateHistory.find((r) => {
      return (
        r.effectiveFrom <= firstOfMonth &&
        (r.effectiveTo === null || r.effectiveTo >= firstOfMonth)
      );
    });

    if (!effectiveRateEntry) {
      console.log(
        `  SKIP  ${patient.name} ${year}/${month} — no effective rate found for that month`,
      );
      skipped++;
      continue;
    }

    const rate = Number(effectiveRateEntry.rate);
    const sessionCount = sessionDates.length;
    const expectedAmount =
      patient.paymentModel === 'MENSAL' ? rate : sessionCount * rate;

    // Compute revenue share
    const activeShare = patient.revenueShareConfig?.active
      ? patient.revenueShareConfig
      : null;
    let revenueShareAmount: number | null = null;
    if (activeShare) {
      revenueShareAmount =
        activeShare.shareType === 'PERCENTAGE'
          ? expectedAmount * (Number(activeShare.shareValue) / 100)
          : sessionCount * Number(activeShare.shareValue);
    }

    // Update session record
    await prisma.sessionRecord.update({
      where: { id: record.id },
      data: { expectedAmount },
    });

    // Update revenueShareAmount on the payment if it exists
    if (record.payment) {
      await prisma.payment.update({
        where: { sessionRecordId: record.id },
        data: { revenueShareAmount },
      });
    }

    console.log(
      `  FIXED ${patient.name} ${year}/${month} — ` +
        `${sessionCount} sess × ${rate} = ${expectedAmount}`,
    );
    fixed++;
  }

  console.log(`\nDone. Fixed: ${fixed}  Skipped: ${skipped}`);
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
