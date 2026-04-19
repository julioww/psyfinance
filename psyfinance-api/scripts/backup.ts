/**
 * scripts/backup.ts
 * Generates a timestamped, AES-256 encrypted PostgreSQL dump.
 *
 * Usage:
 *   npx ts-node scripts/backup.ts
 *
 * Requires:
 *   - pg_dump in PATH
 *   - DATABASE_URL env var
 *   - BACKUP_PASSWORD env var (used to encrypt with openssl)
 *
 * Output: backups/psyfinance-YYYY-MM-DD_HH-MM-SS.sql.gz.enc
 *
 * To decrypt:
 *   openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:<BACKUP_PASSWORD> \
 *     -in backup.sql.gz.enc | gunzip > backup.sql
 *
 * IMPORTANT: Store backup files in a different location from the application.
 */

import 'dotenv/config';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';

function parseDbUrl(url: string) {
  const u = new URL(url);
  return {
    host: u.hostname,
    port: u.port || '5432',
    user: u.username,
    password: u.password,
    dbname: u.pathname.replace(/^\//, '').split('?')[0]!,
  };
}

async function main() {
  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) {
    console.error('DATABASE_URL is not set');
    process.exit(1);
  }

  const backupPassword = process.env.BACKUP_PASSWORD;
  if (!backupPassword) {
    console.error('BACKUP_PASSWORD is not set');
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

  const filename = `psyfinance-${timestamp}.sql.gz.enc`;
  const outputPath = path.join(backupsDir, filename);
  const outStream = fs.createWriteStream(outputPath);

  const env = { ...process.env, PGPASSWORD: db.password };

  // Pipeline: pg_dump (plain SQL) | gzip | openssl enc → file
  await new Promise<void>((resolve, reject) => {
    const pgDump = spawn('pg_dump', [
      '-h', db.host,
      '-p', db.port,
      '-U', db.user,
      '-F', 'p', // plain SQL so we can pipe through gzip + openssl
      db.dbname,
    ], { env });

    const gzip = spawn('gzip', ['-c']);

    const openssl = spawn('openssl', [
      'enc', '-aes-256-cbc', '-pbkdf2',
      '-pass', `pass:${backupPassword}`,
    ]);

    pgDump.stdout.pipe(gzip.stdin);
    gzip.stdout.pipe(openssl.stdin);
    openssl.stdout.pipe(outStream);

    const errors: string[] = [];
    pgDump.stderr.on('data', (d: Buffer) => errors.push(`pg_dump: ${d}`));
    gzip.stderr.on('data', (d: Buffer) => errors.push(`gzip: ${d}`));
    openssl.stderr.on('data', (d: Buffer) => errors.push(`openssl: ${d}`));

    outStream.on('finish', () => {
      if (errors.length > 0) {
        // Log errors but don't expose them — caller checks exit code
        process.stderr.write(errors.join(''));
      }
      resolve();
    });
    outStream.on('error', reject);
    pgDump.on('error', reject);
    gzip.on('error', reject);
    openssl.on('error', reject);
  });

  // Print filename to stdout so the API route can capture it
  console.log(filename);
}

main().catch((err) => {
  console.error('Backup error:', err instanceof Error ? err.message : String(err));
  process.exit(1);
});
