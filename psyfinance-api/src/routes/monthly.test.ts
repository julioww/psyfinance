import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import { prisma } from '../lib/prisma';
import patientsRouter from './patients';
import monthlyRouter from './monthly';

const app = express();
app.use(express.json());
app.use('/api/patients', patientsRouter);
app.use('/api/monthly-view', monthlyRouter);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function cleanAll() {
  await prisma.payment.deleteMany({});
  await prisma.sessionRecord.deleteMany({});
  await prisma.revenueShareConfig.deleteMany({});
  await prisma.rateHistory.deleteMany({});
  await prisma.patient.deleteMany({});
}

let _emailSeq = 0;
async function createPatient(overrides: Record<string, unknown> = {}) {
  _emailSeq++;
  return request(app)
    .post('/api/patients')
    .send({
      name: 'Test Patient',
      email: `patient_${_emailSeq}@example.com`,
      location: 'Brasil',
      paymentModel: 'SESSAO',
      currency: 'BRL',
      initialRate: 200,
      rateEffectiveFrom: '2025-01-01',
      ...overrides,
    });
}

// ---------------------------------------------------------------------------
// Setup / teardown
// ---------------------------------------------------------------------------

beforeAll(() => cleanAll());

afterAll(async () => {
  await cleanAll();
  await prisma.$disconnect();
});

beforeEach(() => cleanAll());

// ---------------------------------------------------------------------------
// GET /api/monthly-view — LEFT JOIN: all active patients returned
// ---------------------------------------------------------------------------

describe('GET /api/monthly-view — LEFT JOIN behaviour', () => {
  it('returns all active patients with null sessionRecord and null payment for a month with no sessions', async () => {
    const p1 = await createPatient({ name: 'Alice', email: 'alice@example.com' });
    const p2 = await createPatient({ name: 'Bob', email: 'bob@example.com' });
    expect(p1.status).toBe(201);
    expect(p2.status).toBe(201);

    // January 2027 — no sessions created; should still return both patients
    const res = await request(app).get('/api/monthly-view?year=2027&month=1');

    expect(res.status).toBe(200);
    expect(res.body.patients).toHaveLength(2);

    for (const row of res.body.patients) {
      expect(row.sessionRecord).toBeNull();
      expect(row.payment).toBeNull();
    }
  });

  it('excludes soft-deleted (INATIVO) patients', async () => {
    const active = await createPatient({ name: 'Active', email: 'active@example.com' });
    const inactive = await createPatient({ name: 'Inactive', email: 'inactive@example.com' });
    expect(active.status).toBe(201);
    expect(inactive.status).toBe(201);

    // Soft-delete the second patient directly via Prisma
    await prisma.patient.update({
      where: { id: inactive.body.id },
      data: { status: 'INATIVO', deletedAt: new Date() },
    });

    const res = await request(app).get('/api/monthly-view?year=2027&month=1');

    expect(res.status).toBe(200);
    expect(res.body.patients).toHaveLength(1);
    expect(res.body.patients[0].patient.name).toBe('Active');
  });

  it('returns 400 for missing year param', async () => {
    const res = await request(app).get('/api/monthly-view?month=1');
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid month', async () => {
    const res = await request(app).get('/api/monthly-view?year=2027&month=13');
    expect(res.status).toBe(400);
  });
});
