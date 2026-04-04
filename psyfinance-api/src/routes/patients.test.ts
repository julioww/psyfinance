import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import { prisma } from '../lib/prisma';
import patientsRouter from './patients';

const app = express();
app.use(express.json());
app.use('/api/patients', patientsRouter);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function cleanPatients() {
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

beforeAll(async () => {
  await cleanPatients();
});

afterAll(async () => {
  await cleanPatients();
  await prisma.$disconnect();
});

beforeEach(async () => {
  await cleanPatients();
});

// ---------------------------------------------------------------------------
// GET /api/patients — filter by location
// ---------------------------------------------------------------------------

describe('GET /api/patients — location filter', () => {
  it('returns only patients from the specified location', async () => {
    await createPatient({ name: 'Brazil Patient', location: 'Brasil' });
    await createPatient({ name: 'Germany Patient', email: 'de@example.com', location: 'Alemanha', currency: 'EUR' });

    const res = await request(app).get('/api/patients?location=Brasil');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0].location).toBe('Brasil');
  });

  it('returns all ATIVO patients when no location filter is given', async () => {
    await createPatient({ name: 'P1', location: 'Brasil' });
    await createPatient({ name: 'P2', email: 'p2@example.com', location: 'Alemanha', currency: 'EUR' });

    const res = await request(app).get('/api/patients');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
  });

  it('returns empty array when no patients match the location', async () => {
    await createPatient({ location: 'Brasil' });

    const res = await request(app).get('/api/patients?location=Portugal');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(0);
  });

  it('filters by paymentModel', async () => {
    await createPatient({ name: 'Sessao', paymentModel: 'SESSAO' });
    await createPatient({ name: 'Mensal', email: 'm@example.com', paymentModel: 'MENSAL' });

    const res = await request(app).get('/api/patients?paymentModel=SESSAO');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0].paymentModel).toBe('SESSAO');
  });

  it('filters by currency', async () => {
    await createPatient({ name: 'BRL', currency: 'BRL' });
    await createPatient({ name: 'EUR', email: 'eur@example.com', currency: 'EUR' });

    const res = await request(app).get('/api/patients?currency=EUR');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0].currency).toBe('EUR');
  });

  it('free-text search on name is case-insensitive', async () => {
    await createPatient({ name: 'Maria Fernanda' });
    await createPatient({ name: 'João Pedro', email: 'joao@example.com' });

    const res = await request(app).get('/api/patients?q=maria');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0].name).toBe('Maria Fernanda');
  });
});

// ---------------------------------------------------------------------------
// POST /api/patients — validation
// ---------------------------------------------------------------------------

describe('POST /api/patients — validation', () => {
  it('rejects when required fields are missing', async () => {
    const res = await request(app).post('/api/patients').send({ name: 'Only Name' });
    expect(res.status).toBe(400);
    expect(res.body.message).toBeTruthy();
  });

  it('rejects invalid email', async () => {
    const res = await createPatient({ email: 'not-an-email' });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/email/i);
  });

  it('rejects non-positive initialRate', async () => {
    const res = await createPatient({ initialRate: -50 });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/taxa/i);
  });

  it('rejects initialRate of zero', async () => {
    const res = await createPatient({ initialRate: 0 });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/taxa/i);
  });

  it('creates patient successfully and returns currentRate', async () => {
    const res = await createPatient();
    expect(res.status).toBe(201);
    expect(res.body.id).toBeTruthy();
    expect(res.body.currentRate).toBe(200);
    expect(res.body.rateHistory).toBeUndefined(); // stripped from response
  });

  it('creates first RateHistory row on patient creation', async () => {
    const res = await createPatient({ initialRate: 350 });
    const history = await prisma.rateHistory.findMany({ where: { patientId: res.body.id } });
    expect(history).toHaveLength(1);
    expect(Number(history[0].rate)).toBe(350);
  });
});

// ---------------------------------------------------------------------------
// DELETE /api/patients/:id — soft-delete
// ---------------------------------------------------------------------------

describe('DELETE /api/patients/:id — soft-delete', () => {
  it('marks patient as INATIVO', async () => {
    const created = await createPatient();
    const id = created.body.id;

    const del = await request(app).delete(`/api/patients/${id}`);
    expect(del.status).toBe(204);

    const patient = await prisma.patient.findUnique({ where: { id } });
    expect(patient?.status).toBe('INATIVO');
    expect(patient?.deletedAt).toBeTruthy();
  });

  it('preserves historical data after soft-delete', async () => {
    const created = await createPatient();
    const id = created.body.id;

    await request(app).delete(`/api/patients/${id}`);

    const history = await prisma.rateHistory.findMany({ where: { patientId: id } });
    expect(history).toHaveLength(1);

    const patient = await prisma.patient.findUnique({ where: { id } });
    expect(patient).not.toBeNull();
  });

  it('returns 404 for unknown id', async () => {
    const res = await request(app).delete('/api/patients/non-existent-id');
    expect(res.status).toBe(404);
  });

  it('soft-deleted patient appears with status=INATIVO filter', async () => {
    const created = await createPatient();
    await request(app).delete(`/api/patients/${created.body.id}`);

    const list = await request(app).get('/api/patients?status=INATIVO');
    expect(list.body).toHaveLength(1);
    expect(list.body[0].status).toBe('INATIVO');
  });

  it('soft-deleted patient does NOT appear in default (ATIVO) list', async () => {
    const created = await createPatient();
    await request(app).delete(`/api/patients/${created.body.id}`);

    const list = await request(app).get('/api/patients');
    expect(list.body).toHaveLength(0);
  });
});
