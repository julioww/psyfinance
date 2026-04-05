/**
 * scripts/backup.ts
 * Generates a timestamped PostgreSQL dump of the PsyFinance database.
 *
 * Usage:
 *   npx ts-node scripts/backup.ts
 *
 * Requires pg_dump to be in PATH and DATABASE_URL to be set in environment.
 * Output: backups/psyfinance-YYYY-MM-DD_HH-MM-SS.dump
 */

import 'dotenv/config';
import { execFile } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';
import path from 'path';

const execFileAsync = promisify(execFile);

function parseDbUrl(url: string) {
  // postgresql://user:password@host:port/dbname?schema=...
  const u = new URL(url);
  return {
    host: u.hostname,
    port: u.port || '5432',
    user: u.username,
    password: u.password,
    dbname: u.pathname.replace(/^\//, ''),
  };
}

async function main() {
  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) {
    console.error('DATABASE_URL is not set');
    process.exit(1);
  }

  const db = parseDbUrl(dbUrl);

  const timestamp = new Date()
    .toISOString()
    .replace(/T/, '_')
    .replace(/:/g, '-')
    .replace(/\..+/, '');

  const backupsDir = path.resolve(__dirname, '../backups');
  if (!fs.existsSync(backupsDir)) {
    fs.mkdirSync(backupsDir, { recursive: true });
  }

  const filename = `psyfinance-${timestamp}.dump`;
  const outputPath = path.join(backupsDir, filename);

  const env = { ...process.env, PGPASSWORD: db.password };

  await execFileAsync(
    'pg_dump',
    [
      '-h', db.host,
      '-p', db.port,
      '-U', db.user,
      '-F', 'c',          // custom format (compressed)
      '-f', outputPath,
      db.dbname,
    ],
    { env },
  );

  // Print filename to stdout so the API route can capture it
  console.log(filename);
}

main().catch((err) => {
  console.error('Backup error:', err.message ?? err);
  process.exit(1);
});
