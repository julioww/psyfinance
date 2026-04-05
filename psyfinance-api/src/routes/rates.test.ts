import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import { prisma } from '../lib/prisma';
import patientsRouter from './patients';
import ratesRouter from './rates';
import { getRateForDate } from '../lib/rate';

const app = express();
app.use(express.json());
app.use('/api/patients', patientsRouter);
app.use('/api/patients', ratesRouter);

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

async function createPatient(overrides: Record<string, unknown> = {}) {
  return request(app)
    .post('/api/patients')
    .send({
      name: 'Ana Silva',
      email: 'ana@example.com',
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
// GET /api/patients/:id/rates
// ---------------------------------------------------------------------------

describe('GET /api/patients/:id/rates', () => {
  it('returns rate history ordered by effectiveFrom desc', async () => {
    const patient = await createPatient();
    const id = patient.body.id;

    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 250, effectiveFrom: '2025-08-01' });

    const res = await request(app).get(`/api/patients/${id}/rates`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
    expect(res.body[0].effectiveFrom).toBe('2025-08-01');
    expect(res.body[1].effectiveFrom).toBe('2025-01-01');
  });

  it('returns 404 for unknown patient', async () => {
    const res = await request(app).get('/api/patients/non-existent-id/rates');
    expect(res.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// POST /api/patients/:id/rates — closes effectiveTo on previous rate
// ---------------------------------------------------------------------------

describe('POST /api/patients/:id/rates — close previous rate', () => {
  it('sets effectiveTo on the previous rate to new effectiveFrom − 1 day', async () => {
    const patient = await createPatient({ rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 250, effectiveFrom: '2025-08-01' });

    const history = await prisma.rateHistory.findMany({
      where: { patientId: id },
      orderBy: { effectiveFrom: 'asc' },
    });

    expect(history).toHaveLength(2);
    // Previous rate is closed at 2025-07-31
    expect(history[0].effectiveTo).not.toBeNull();
    expect(history[0].effectiveTo!.toISOString().split('T')[0]).toBe('2025-07-31');
    // New rate is open
    expect(history[1].effectiveTo).toBeNull();
  });

  it('creates new rate entry without modifying previous closed rows', async () => {
    const patient = await createPatient({ rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    // Add a second rate
    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 250, effectiveFrom: '2025-08-01' });

    // Add a third rate
    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 300, effectiveFrom: '2025-10-01' });

    const history = await prisma.rateHistory.findMany({
      where: { patientId: id },
      orderBy: { effectiveFrom: 'asc' },
    });

    expect(history).toHaveLength(3);
    // First rate was closed by the second — its effectiveTo must not change after the third POST
    expect(history[0].effectiveTo!.toISOString().split('T')[0]).toBe('2025-07-31');
    // Second rate is now closed by the third
    expect(history[1].effectiveTo!.toISOString().split('T')[0]).toBe('2025-09-30');
    // Third rate is open
    expect(history[2].effectiveTo).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// POST /api/patients/:id/rates — 409 for past effectiveFrom
// ---------------------------------------------------------------------------

describe('POST /api/patients/:id/rates — 409 for non-strictly-after date', () => {
  it('returns 409 when effectiveFrom equals current rate start', async () => {
    const patient = await createPatient({ rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    const res = await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 250, effectiveFrom: '2025-01-01' });

    expect(res.status).toBe(409);
  });

  it('returns 409 when effectiveFrom is before current rate start', async () => {
    const patient = await createPatient({ rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    const res = await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 250, effectiveFrom: '2024-12-31' });

    expect(res.status).toBe(409);
  });

  it('409 message contains the current rate start date', async () => {
    const patient = await createPatient({ rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    const res = await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 250, effectiveFrom: '2025-01-01' });

    expect(res.status).toBe(409);
    expect(res.body.message).toMatch(/2025-01-01/);
  });

  it('accepts effectiveFrom strictly after current rate start', async () => {
    const patient = await createPatient({ rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    const res = await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 300, effectiveFrom: '2025-09-01' });

    expect(res.status).toBe(201);
    expect(res.body.rate).toBe(300);
    expect(res.body.effectiveTo).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// lib/rate — getRateForDate returns correct rate before and after a change
// ---------------------------------------------------------------------------

describe('lib/rate — getRateForDate', () => {
  it('returns the original rate for a date before the change', async () => {
    const patient = await createPatient({ initialRate: 200, rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 300, effectiveFrom: '2025-08-01' });

    const rate = await getRateForDate(id, new Date('2025-07-15'));
    expect(rate).toBe(200);
  });

  it('returns the new rate for a date after the change', async () => {
    const patient = await createPatient({ initialRate: 200, rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 300, effectiveFrom: '2025-08-01' });

    const rate = await getRateForDate(id, new Date('2025-09-01'));
    expect(rate).toBe(300);
  });

  it('returns the new rate on the exact change date', async () => {
    const patient = await createPatient({ initialRate: 200, rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 300, effectiveFrom: '2025-08-01' });

    const rate = await getRateForDate(id, new Date('2025-08-01'));
    expect(rate).toBe(300);
  });

  it('returns the old rate on the last day of the previous period', async () => {
    const patient = await createPatient({ initialRate: 200, rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    await request(app)
      .post(`/api/patients/${id}/rates`)
      .send({ rate: 300, effectiveFrom: '2025-08-01' });

    const rate = await getRateForDate(id, new Date('2025-07-31'));
    expect(rate).toBe(200);
  });

  it('returns the current rate for a future year with no session records (carry-forward)', async () => {
    // Patient has a rate set in 2025 (effectiveTo IS NULL); no sessions exist in 2027.
    const patient = await createPatient({ initialRate: 200, rateEffectiveFrom: '2025-01-01' });
    const id = patient.body.id;

    // Query for January 2027 — no additional rates or sessions created
    const rate = await getRateForDate(id, new Date('2027-01-01'));
    expect(rate).toBe(200);
  });
});
