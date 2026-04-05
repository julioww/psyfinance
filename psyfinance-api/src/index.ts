import 'dotenv/config';
import express from 'express';
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

const app = express();
const PORT = process.env.PORT ?? 3000;

// ---------------------------------------------------------------------------
// Security headers
// ---------------------------------------------------------------------------
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:'],
      connectSrc: ["'self'"],
      frameSrc: ["'none'"],
      objectSrc: ["'none'"],
    },
  },
  frameguard: { action: 'deny' },
  noSniff: true,
  hsts: { maxAge: 31536000, includeSubDomains: true },
}));

// ---------------------------------------------------------------------------
// CORS — localhost only
// ---------------------------------------------------------------------------
app.use(cors({
  origin: (origin, callback) => {
    if (!origin || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin not allowed — ${origin}`));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

app.use(express.json());

// ---------------------------------------------------------------------------
// Rate limiter for login — max 10 attempts/minute/IP
// ---------------------------------------------------------------------------
const loginLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Muitas tentativas. Aguarde um minuto.' },
});

// ---------------------------------------------------------------------------
// Public routes
// ---------------------------------------------------------------------------
app.use('/auth', loginLimiter, authRouter);

app.get('/health', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok', database: 'connected', timestamp: new Date().toISOString() });
  } catch (err) {
    res.status(503).json({ status: 'error', database: 'disconnected', error: String(err) });
  }
});

// ---------------------------------------------------------------------------
// Protected API routes — require valid Bearer token
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

app.listen(PORT, () => {
  console.log(`PsyFinance API running on http://localhost:${PORT}`);
});

export default app;
