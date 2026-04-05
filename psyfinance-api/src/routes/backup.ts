import { Router } from 'express';
import { execFile } from 'child_process';
import { promisify } from 'util';
import path from 'path';

const router = Router();
const execFileAsync = promisify(execFile);

// POST /api/backup — trigger a timestamped pg_dump
router.post('/', async (_req, res) => {
  const scriptPath = path.resolve(__dirname, '../../scripts/backup.ts');
  try {
    const { stdout, stderr } = await execFileAsync(
      'npx',
      ['ts-node', scriptPath],
      { cwd: path.resolve(__dirname, '../..') },
    );
    if (stderr && !stdout) {
      res.status(500).json({ message: 'Backup falhou', detail: stderr });
      return;
    }
    // stdout contains the backup filename
    const filename = stdout.trim();
    res.json({ message: 'Backup concluído', filename });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    res.status(500).json({ message: 'Backup falhou', detail: msg });
  }
});

export default router;
