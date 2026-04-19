import { Router } from 'express';
import { execFile } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const router = Router();
const execFileAsync = promisify(execFile);

// POST /api/backup — trigger a timestamped, encrypted pg_dump
router.post('/', async (_req, res) => {
  const scriptPath = path.resolve(__dirname, '../../scripts/backup.ts');
  try {
    const { stdout } = await execFileAsync(
      'npx',
      ['ts-node', scriptPath],
      { cwd: path.resolve(__dirname, '../..') },
    );
    const filename = stdout.trim();
    res.json({ message: 'Backup concluído', filename });
  } catch {
    // Do not expose internal error details to the client
    res.status(500).json({ message: 'Backup falhou' });
  }
});

export default router;
