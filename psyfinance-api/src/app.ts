import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { prisma } from './lib/prisma';
import { requireAuth } from './middleware/requireAuth';
import authRouter from './routes/auth';
import patientsRouter from './routes/patients';
import ratesRouter from './routes/rates';
import sessionsRouter from './routes/sessions';
import paymentsRouter from './routes/payments';
import monthlyRouter from './routes/monthly';
import dashboardRouter from './routes/dashboard';
import revenueShareRouter from './routes/revenue_share';
import exportRouter from './routes/export';
import importRouter from './routes/import';
import backupRouter from './routes/backup';
import agendaRouter from './routes/agenda';

// ---------------------------------------------------------------------------
// Startup environment validation
// ---------------------------------------------------------------------------

const REQUIRED_ALWAYS = [
  'DATABASE_URL',
  'JWT_SECRET',
  'PSYFINANCE_USERNAME',
  'PSYFINANCE_PASSWORD_HASH',
] as const;

const REQUIRED_IN_PRODUCTION = [
  'ALLOWED_ORIGIN',
  'BACKUP_PASSWORD',
] as const;

function validateEnv(): void {
  const isProd = process.env.NODE_ENV === 'production';
  const required = isProd
    ? [...REQUIRED_ALWAYS, ...REQUIRED_IN_PRODUCTION]
    : REQUIRED_ALWAYS;

  let missing = false;
  for (const name of required) {
    if (!process.env[name]) {
      console.error(`Missing required env var: ${name}`);
      missing = true;
    }
  }
  if (missing) process.exit(1);

  const secret = process.env.JWT_SECRET!;
  if (secret.length < 64) {
    if (isProd) {
      console.error('JWT_SECRET must be at least 64 characters. Generate one with: npx ts-node scripts/generate-secret.ts');
      process.exit(1);
    } else {
      console.warn('Warning: JWT_SECRET is shorter than 64 characters. Use a full-length secret in production.');
    }
  }

  if (isProd) {
    const dbUrl = process.env.DATABASE_URL!;
    if (!dbUrl.includes('sslmode=require')) {
      console.error('DATABASE_URL must include ?sslmode=require in production');
      process.exit(1);
    }
  }
}

// Skip validation in test environments so vitest can stub env vars
if (process.env.NODE_ENV !== 'test') {
  validateEnv();
}

// ---------------------------------------------------------------------------
// Express app
// ---------------------------------------------------------------------------

const app = express();

app.disable('x-powered-by');

// ---------------------------------------------------------------------------
// Security headers
// ---------------------------------------------------------------------------
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'wasm-unsafe-eval'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:'],
      fontSrc: ["'self'", 'data:'],
      connectSrc: ["'self'", 'https://calendar.google.com'],
      frameSrc: ["'none'"],
      objectSrc: ["'none'"],
    },
  },
  frameguard: { action: 'deny' },
  noSniff: true,
  referrerPolicy: { policy: 'no-referrer' },
  hsts: { maxAge: 31536000, includeSubDomains: true },
}));

app.use((_req: Request, res: Response, next: NextFunction) => {
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  next();
});

// ---------------------------------------------------------------------------
// CORS
// ---------------------------------------------------------------------------
const allowedOrigin = process.env.ALLOWED_ORIGIN;

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);
    if (allowedOrigin) {
      if (origin === allowedOrigin) return callback(null, true);
      return callback(new Error(`CORS: origin not allowed — ${origin}`));
    }
    if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
      return callback(null, true);
    }
    return callback(new Error(`CORS: origin not allowed — ${origin}`));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ---------------------------------------------------------------------------
// Body parsing
// ---------------------------------------------------------------------------
app.use(express.json({ limit: '100kb' }));

// ---------------------------------------------------------------------------
// Rate limiter — login only
// ---------------------------------------------------------------------------
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: false,
  handler: (_req: Request, res: Response) => {
    res.status(429).end();
  },
});

// ---------------------------------------------------------------------------
// Public routes
// ---------------------------------------------------------------------------
app.use('/auth', loginLimiter, authRouter);

app.get('/health', async (_req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  } catch {
    res.status(503).json({ status: 'error' });
  }
});

// ---------------------------------------------------------------------------
// Protected routes
// ---------------------------------------------------------------------------
app.use('/api', requireAuth);

app.use('/api/patients', patientsRouter);
app.use('/api/patients', ratesRouter);
app.use('/api/patients', revenueShareRouter);
app.use('/api/sessions', sessionsRouter);
app.use('/api/payments', paymentsRouter);
app.use('/api/monthly-view', monthlyRouter);
app.use('/api/dashboard', dashboardRouter);
app.use('/api/export', exportRouter);
app.use('/api/import', importRouter);
app.use('/api/backup', backupRouter);
app.use('/api/agenda', agendaRouter);

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------
// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  if (process.env.NODE_ENV === 'production') {
    res.status(500).json({ error: 'Internal server error' });
  } else {
    res.status(500).json({ error: err.message, stack: err.stack });
  }
});

export default app;
