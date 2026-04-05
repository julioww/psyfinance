/**
 * POST /api/import
 *
 * Accepts a CSV file (Content-Type: text/csv or application/octet-stream) as
 * the request body, plus query parameters:
 *   ?year=2024        — reference year (required)
 *   &dryRun=true      — parse and report without writing (optional, default false)
 *
 * Streams results back as newline-delimited JSON (NDJSON):
 *   {"level":"info","message":"CSV carregado: 15 linhas"}
 *   {"level":"ok","message":"Paciente criado: Ana Lima"}
 *   {"level":"warn","message":"Conciliação BRL: divergência=5"}
 *   ...
 *   {"level":"info","message":"Resumo: 3 paciente(s), ..."}
 */

import { Router, Request, Response } from 'express';
import { runImport } from '../lib/importer';

const router = Router();

// Accept any content type so Flutter can post raw bytes as text/csv
router.post(
  '/',
  (req: Request, res: Response, next) => {
    let raw = Buffer.alloc(0);
    req.on('data', (chunk: Buffer) => {
      raw = Buffer.concat([raw, chunk]);
    });
    req.on('end', () => {
      (req as Request & { rawBody: Buffer }).rawBody = raw;
      next();
    });
    req.on('error', next);
  },
  async (req: Request, res: Response) => {
    const year = parseInt((req.query['year'] as string) ?? '', 10);
    const dryRun = (req.query['dryRun'] as string) === 'true';

    if (isNaN(year) || year < 2000 || year > 2100) {
      res.status(400).json({ message: 'Parâmetro "year" inválido ou ausente (ex: ?year=2024)' });
      return;
    }

    const csvContent = (req as Request & { rawBody: Buffer }).rawBody.toString('utf-8');
    if (!csvContent.trim()) {
      res.status(400).json({ message: 'Corpo da requisição vazio — envie o CSV como body' });
      return;
    }

    // Stream NDJSON response
    res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
    res.setHeader('Transfer-Encoding', 'chunked');
    res.setHeader('X-Accel-Buffering', 'no');     // disable nginx buffering
    res.setHeader('Cache-Control', 'no-cache');
    res.flushHeaders();

    const write = (obj: object) => {
      res.write(JSON.stringify(obj) + '\n');
    };

    try {
      await runImport({
        csvContent,
        year,
        dryRun,
        logger: (entry) => write(entry),
      });
    } catch (err) {
      write({ level: 'err', message: `Erro interno: ${String(err)}` });
    }

    res.end();
  },
);

export default router;
