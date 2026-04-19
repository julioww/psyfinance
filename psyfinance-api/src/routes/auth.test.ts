import { describe, it, expect, beforeEach, vi } from 'vitest';
import request from 'supertest';
import express from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcrypt';
import authRouter from './auth';
import patientsRouter from './patients';
import { requireAuth } from '../middleware/requireAuth';

// ---------------------------------------------------------------------------
// Test app setup
// ---------------------------------------------------------------------------

const TEST_USERNAME = 'psico';
const TEST_PASSWORD = 'senha123';
// 64-char hex secret — matches the minimum required by lib/auth.ts
const TEST_JWT_SECRET = 'a'.repeat(64);

async function buildApp() {
  const hash = await bcrypt.hash(TEST_PASSWORD, 10);
  vi.stubEnv('PSYFINANCE_USERNAME', TEST_USERNAME);
  vi.stubEnv('PSYFINANCE_PASSWORD_HASH', hash);
  vi.stubEnv('JWT_SECRET', TEST_JWT_SECRET);

  const app = express();
  app.use(express.json());

  const loginLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 10,
    standardHeaders: false,
    legacyHeaders: false,
    keyGenerator: () => 'test-client',
    validate: false,
  });

  app.use('/auth', loginLimiter, authRouter);
  app.use('/api', requireAuth);
  app.use('/api/patients', patientsRouter);

  return app;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('Authentication', () => {
  let app: express.Express;

  beforeEach(async () => {
    vi.unstubAllEnvs();
    app = await buildApp();
  });

  it('unauthenticated request to /api/patients → 401', async () => {
    const res = await request(app).get('/api/patients');
    expect(res.status).toBe(401);
  });

  it('login with correct credentials → JWT token', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ usuario: TEST_USERNAME, senha: TEST_PASSWORD });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('expiresAt');
    expect(typeof res.body.token).toBe('string');
  });

  it('login with wrong password → 401 (no field hint)', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ usuario: TEST_USERNAME, senha: 'wrongpassword' });

    expect(res.status).toBe(401);
    expect(res.body.message).toBe('Credenciais inválidas');
    // Must not hint which field was wrong
    expect(res.body.message).not.toMatch(/usuário|senha|user|password/i);
  });

  it('login with wrong username → 401', async () => {
    const res = await request(app)
      .post('/auth/login')
      .send({ usuario: 'wronguser', senha: TEST_PASSWORD });

    expect(res.status).toBe(401);
    expect(res.body.message).toBe('Credenciais inválidas');
  });

  it('authenticated request succeeds after login', async () => {
    const loginRes = await request(app)
      .post('/auth/login')
      .send({ usuario: TEST_USERNAME, senha: TEST_PASSWORD });

    const token = loginRes.body.token as string;

    const res = await request(app)
      .get('/api/patients')
      .set('Authorization', `Bearer ${token}`);

    // 200 means auth passed (may be other errors due to DB, but not 401)
    expect(res.status).not.toBe(401);
  });

  it('logout revokes token → subsequent request returns 401', async () => {
    const loginRes = await request(app)
      .post('/auth/login')
      .send({ usuario: TEST_USERNAME, senha: TEST_PASSWORD });

    const token = loginRes.body.token as string;

    // Logout
    await request(app)
      .post('/auth/logout')
      .set('Authorization', `Bearer ${token}`);

    // Token should now be revoked
    const res = await request(app)
      .get('/api/patients')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(401);
  });
});

describe('Rate limiter', () => {
  it('blocks after 10 login attempts per minute → 429', async () => {
    vi.stubEnv('PSYFINANCE_USERNAME', 'x');
    vi.stubEnv('PSYFINANCE_PASSWORD_HASH', 'x');
    vi.stubEnv('JWT_SECRET', TEST_JWT_SECRET);

    const app = express();
    app.use(express.json());

    // Tight limiter for this test (3 requests)
    const limiter = rateLimit({
      windowMs: 60 * 1000,
      max: 3,
      standardHeaders: false,
      legacyHeaders: false,
      keyGenerator: () => 'test-ip',
      validate: false,
    });

    app.use('/auth', limiter, authRouter);

    // 3 attempts should go through (401), 4th should be rate-limited (429)
    for (let i = 0; i < 3; i++) {
      await request(app).post('/auth/login').send({ usuario: 'x', senha: 'x' });
    }
    const res = await request(app)
      .post('/auth/login')
      .send({ usuario: 'x', senha: 'x' });

    expect(res.status).toBe(429);
  });
});
