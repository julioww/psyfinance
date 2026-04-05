#!/usr/bin/env ts-node
/**
 * F11 — Google Sheets data migration CLI
 *
 * Usage:
 *   node scripts/import.ts --file 2026.csv --year 2026 [--dry-run]
 *
 * Or with ts-node (from psyfinance-api/):
 *   npx ts-node scripts/import.ts --file scripts/sample-import.csv --year 2024 --dry-run
 */

import 'dotenv/config';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { runImport, LogEntry } from '../src/lib/importer';

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArgs(): { file: string; year: number; dryRun: boolean } {
  const argv = process.argv.slice(2);
  let file = '';
  let year = new Date().getFullYear();
  let dryRun = false;

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--file':
        file = argv[++i] ?? '';
        break;
      case '--year':
        year = parseInt(argv[++i] ?? '', 10);
        break;
      case '--dry-run':
        dryRun = true;
        break;
      case '--help':
      case '-h':
        printUsage();
        process.exit(0);
    }
  }

  return { file, year, dryRun };
}

function printUsage() {
  console.log(`
PsyFinance — Importador de dados do Google Sheets

Uso:
  npx ts-node scripts/import.ts --file <arquivo.csv> --year <ano> [--dry-run]

Opções:
  --file <path>   Caminho para o arquivo CSV exportado do Google Sheets
  --year <ano>    Ano de referência dos dados (ex: 2024)
  --dry-run       Valida sem gravar dados no banco
  --help          Mostra esta ajuda

Exemplo:
  npx ts-node scripts/import.ts --file scripts/sample-import.csv --year 2024 --dry-run
  npx ts-node scripts/import.ts --file ~/Downloads/2026.csv --year 2026
`);
}

// ---------------------------------------------------------------------------
// ANSI color helpers
// ---------------------------------------------------------------------------

const RESET = '\x1b[0m';
const COLORS: Record<string, string> = {
  info: '\x1b[36m',  // cyan
  ok:   '\x1b[32m',  // green
  warn: '\x1b[33m',  // yellow
  err:  '\x1b[31m',  // red
};

function colorize(entry: LogEntry): string {
  const color = COLORS[entry.level] ?? '';
  const tag = `[${entry.level.toUpperCase().padEnd(4)}]`;
  return `${color}${tag}${RESET} ${entry.message}`;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const { file, year, dryRun } = parseArgs();

  if (!file) {
    console.error('Erro: --file é obrigatório');
    printUsage();
    process.exit(1);
  }

  if (isNaN(year) || year < 2000 || year > 2100) {
    console.error(`Erro: --year inválido: ${year}`);
    process.exit(1);
  }

  const filePath = path.resolve(file);
  if (!fs.existsSync(filePath)) {
    console.error(`Erro: arquivo não encontrado: ${filePath}`);
    process.exit(1);
  }

  const csvContent = fs.readFileSync(filePath, 'utf-8');

  console.log(`\nPsyFinance Importador — ano ${year}${dryRun ? ' [SIMULAÇÃO]' : ''}`);
  console.log(`Arquivo: ${filePath}`);
  console.log('─'.repeat(60));

  let warnCount = 0;
  let errCount = 0;

  const summary = await runImport({
    csvContent,
    year,
    dryRun,
    logger: (entry) => {
      console.log(colorize(entry));
      if (entry.level === 'warn') warnCount++;
      if (entry.level === 'err') errCount++;
    },
  });

  console.log('─'.repeat(60));

  if (summary.reconciliation.length > 0) {
    console.log('\nConciliação:');
    for (const r of summary.reconciliation) {
      const icon = r.ok ? '✓' : '✗';
      console.log(`  ${icon} ${r.currency}: planilha=${r.spreadsheetTotal} banco=${r.dbTotal} diff=${r.diff}`);
    }
  }

  console.log('\nResumo final:');
  console.log(`  Pacientes:  ${summary.patientsUpserted}`);
  console.log(`  Taxas:      ${summary.ratesCreated}`);
  console.log(`  Registros:  ${summary.sessionRecordsUpserted}`);
  console.log(`  Pagamentos: ${summary.paymentsUpserted}`);
  console.log(`  Avisos:     ${warnCount}`);
  console.log(`  Erros:      ${errCount}`);

  if (dryRun) {
    console.log('\n[SIMULAÇÃO] Nenhum dado foi gravado no banco.');
  }

  process.exit(errCount > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error('\x1b[31m[FATAL]\x1b[0m', err);
  process.exit(1);
});
