import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { prisma } from './lib/prisma';
import patientsRouter from './routes/patients';
import ratesRouter from './routes/rates';
import sessionsRouter from './routes/sessions';
import paymentsRouter from './routes/payments';
import monthlyRouter from './routes/monthly';
import dashboardRouter from './routes/dashboard';
import revenueShareRouter from './routes/revenue_share';
import exportRouter from './routes/export';

const app = express();
const PORT = process.env.PORT ?? 3000;

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (curl, Postman) or any localhost/127.0.0.1 port
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

app.use('/api/patients', patientsRouter);
app.use('/api/patients', ratesRouter);
app.use('/api/patients', revenueShareRouter);
app.use('/api/sessions', sessionsRouter);
app.use('/api/payments', paymentsRouter);
app.use('/api/monthly-view', monthlyRouter);
app.use('/api/dashboard', dashboardRouter);
app.use('/api/export', exportRouter);

app.get('/health', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok', database: 'connected', timestamp: new Date().toISOString() });
  } catch (err) {
    res.status(503).json({ status: 'error', database: 'disconnected', error: String(err) });
  }
});

app.listen(PORT, () => {
  console.log(`PsyFinance API running on http://localhost:${PORT}`);
});

export default app;
