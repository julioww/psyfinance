/**
 * F11 — Google Sheets data import (shared logic used by CLI and HTTP route)
 *
 * CSV format (exported from "Financeiro Psicologia"):
 *
 *   Row 0:  "Paciente", Name1, ×(GROUP-1 blank), Name2, ×(GROUP-1 blank), ...
 *   Rows 1-6: label in col 0 (Email|CPF|Local|Pagamento|Moeda|Taxa), value at
 *             col 1 + n*GROUP for each patient n
 *   Row 7:  "Mês", "Datas", "Qtd", "Esperado", "Recebido", "Obs", (repeat ×patients)
 *   Rows 8…: month data — col 0 = "Jan/2024", then 5 cols per patient
 *   Total rows (col 0 starts with "Total recebido"): used for reconciliation
 *
 * GROUP_SIZE = 5 (Datas, Qtd, Esperado, Recebido, Obs), auto-detected from
 * the "Mês" header row.
 */

import { PrismaClient, PaymentModel, Currency } from '@prisma/client';

const prisma = new PrismaClient();

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type LogLevel = 'info' | 'ok' | 'warn' | 'err';

export interface LogEntry {
  level: LogLevel;
  message: string;
}

export type Logger = (entry: LogEntry) => void | Promise<void>;

export interface ImportOptions {
  csvContent: string;
  year: number;
  dryRun: boolean;
  logger: Logger;
}

export interface ImportSummary {
  patientsUpserted: number;
  ratesCreated: number;
  sessionRecordsUpserted: number;
  paymentsUpserted: number;
  errors: number;
  reconciliation: Array<{
    currency: string;
    spreadsheetTotal: number;
    dbTotal: number;
    diff: number;
    ok: boolean;
  }>;
}

// ---------------------------------------------------------------------------
// CSV parser (handles quoted fields with embedded commas/newlines)
// ---------------------------------------------------------------------------

function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  let i = 0;

  while (i <= normalized.length) {
    const cols: string[] = [];

    while (i <= normalized.length) {
      if (i === normalized.length || normalized[i] === '\n') {
        // end of row
        i++;
        break;
      }

      if (normalized[i] === '"') {
        // Quoted field
        i++; // skip opening quote
        let field = '';
        while (i < normalized.length) {
          if (normalized[i] === '"') {
            if (normalized[i + 1] === '"') {
              field += '"';
              i += 2;
            } else {
              i++; // skip closing quote
              break;
            }
          } else {
            field += normalized[i++];
          }
        }
        cols.push(field);
        if (normalized[i] === ',') i++;
      } else {
        // Unquoted field
        let field = '';
        while (i < normalized.length && normalized[i] !== ',' && normalized[i] !== '\n') {
          field += normalized[i++];
        }
        cols.push(field.trim());
        if (normalized[i] === ',') i++;
      }
    }

    if (cols.length > 0 && !(cols.length === 1 && cols[0] === '')) {
      rows.push(cols);
    }
  }

  return rows;
}

// ---------------------------------------------------------------------------
// Amount parser  ("R$70", "€60", "70", "70,50")
// ---------------------------------------------------------------------------

function parseAmount(str: string): number | null {
  const cleaned = str.replace(/[R$€\s]/g, '').replace(',', '.');
  const n = parseFloat(cleaned);
  return isNaN(n) ? null : n;
}

// ---------------------------------------------------------------------------
// Month-name date parser  ("Jan 2024", "Jan/2024")
// ---------------------------------------------------------------------------

const MONTH_ABBR: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6,
  jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
};

function parseMonthDate(str: string): Date | null {
  const m = str.trim().match(/^([A-Za-záéíóúâêîôûãõç]+)[/\s](\d{4})$/i);
  if (!m) return null;
  const key = m[1].slice(0, 3).toLowerCase();
  const month = MONTH_ABBR[key];
  if (!month) return null;
  return new Date(`${m[2]}-${String(month).padStart(2, '0')}-01`);
}

// ---------------------------------------------------------------------------
// Rate-string parser
//
//   "R$70"                        → [{rate:70, from:year-01-01, to:null}]
//   "R$70 / Mar 2024 - R$80"     → [{rate:70, from:year-01-01, to:2024-02-29},
//                                    {rate:80, from:2024-03-01, to:null}]
//   "R$70 / Mar 2024 - R$80 / Jul 2024 - R$90"  → three segments
// ---------------------------------------------------------------------------

interface RateSegment {
  rate: number;
  effectiveFrom: Date;
  effectiveTo: Date | null;
}

function parseRateStr(rateStr: string, defaultYear: number): RateSegment[] {
  // Split on " - " to get segments separated by change boundaries
  const parts = rateStr.split(' - ').map((s) => s.trim()).filter(Boolean);
  if (parts.length === 0) return [];

  const segments: RateSegment[] = [];
  let currentFrom = new Date(`${defaultYear}-01-01`);

  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    const slashIdx = part.indexOf(' / ');

    if (slashIdx !== -1) {
      // "AMOUNT / Mon YYYY"  — rate changes at that date
      const amountStr = part.substring(0, slashIdx).trim();
      const dateStr = part.substring(slashIdx + 3).trim();
      const amount = parseAmount(amountStr);
      const changeDate = parseMonthDate(dateStr);

      if (amount !== null && changeDate) {
        // This rate runs from currentFrom up to (changeDate - 1 day)
        const effectiveTo = new Date(changeDate);
        effectiveTo.setDate(effectiveTo.getDate() - 1);
        segments.push({ rate: amount, effectiveFrom: currentFrom, effectiveTo });
        currentFrom = changeDate;
      }
    } else {
      // Plain amount — current rate with no known end date
      const amount = parseAmount(part);
      if (amount !== null) {
        segments.push({ rate: amount, effectiveFrom: currentFrom, effectiveTo: null });
      }
    }
  }

  return segments;
}

// ---------------------------------------------------------------------------
// Month-row parser  "Jan/2024" → {month:1, year:2024}
// ---------------------------------------------------------------------------

function parseMonthRow(str: string): { month: number; year: number } | null {
  const m = str.trim().match(/^([A-Za-záéíóúâêîôûãõç]+)\/(\d{4})$/i);
  if (!m) return null;
  const key = m[1].slice(0, 3).toLowerCase();
  const month = MONTH_ABBR[key];
  if (!month) return null;
  return { month, year: parseInt(m[2], 10) };
}

// ---------------------------------------------------------------------------
// Payment status helper (mirrors payments.ts logic)
// ---------------------------------------------------------------------------

type PaymentStatus = 'PENDENTE' | 'PARCIAL' | 'PAGO' | 'ATRASADO';

function computePaymentStatus(
  amountPaid: number,
  expectedAmount: number,
  year: number,
  month: number,
): PaymentStatus {
  if (amountPaid >= expectedAmount && expectedAmount > 0) return 'PAGO';
  const now = new Date();
  const isPast =
    year < now.getFullYear() ||
    (year === now.getFullYear() && month < now.getMonth() + 1);
  if (isPast && amountPaid < expectedAmount) return 'ATRASADO';
  if (amountPaid > 0) return 'PARCIAL';
  return 'PENDENTE';
}

// ---------------------------------------------------------------------------
// Main import function
// ---------------------------------------------------------------------------

export async function runImport(options: ImportOptions): Promise<ImportSummary> {
  const { csvContent, year, dryRun, logger } = options;
  const log = (level: LogLevel, message: string) => logger({ level, message });

  const summary: ImportSummary = {
    patientsUpserted: 0,
    ratesCreated: 0,
    sessionRecordsUpserted: 0,
    paymentsUpserted: 0,
    errors: 0,
    reconciliation: [],
  };

  // ---- 1. Parse CSV --------------------------------------------------------

  const rows = parseCSV(csvContent);
  if (rows.length === 0) {
    log('err', 'CSV vazio ou inválido');
    summary.errors++;
    return summary;
  }

  log('info', `CSV carregado: ${rows.length} linhas`);

  // ---- 2. Find key rows ----------------------------------------------------

  // Find the "Mês" header row (col 0 == "Mês" and col 1 == "Datas")
  const headerRowIdx = rows.findIndex(
    (r) => r[0]?.trim() === 'Mês' && r[1]?.trim() === 'Datas',
  );
  if (headerRowIdx === -1) {
    log('err', 'Linha de cabeçalho "Mês / Datas" não encontrada no CSV');
    summary.errors++;
    return summary;
  }

  // Find the "Paciente" row (col 0 == "Paciente")
  const patientRowIdx = rows.findIndex((r) => r[0]?.trim() === 'Paciente');
  if (patientRowIdx === -1) {
    log('err', 'Linha "Paciente" não encontrada no CSV');
    summary.errors++;
    return summary;
  }

  // ---- 3. Detect GROUP_SIZE from "Mês" header row --------------------------

  const headerRow = rows[headerRowIdx];
  // Positions where "Datas" appears
  const datasPositions: number[] = [];
  for (let c = 1; c < headerRow.length; c++) {
    if (headerRow[c]?.trim() === 'Datas') datasPositions.push(c);
  }

  if (datasPositions.length === 0) {
    log('err', 'Coluna "Datas" não encontrada no cabeçalho');
    summary.errors++;
    return summary;
  }

  const GROUP_SIZE =
    datasPositions.length > 1
      ? datasPositions[1] - datasPositions[0]
      : 5; // default

  log('info', `Detectado GROUP_SIZE=${GROUP_SIZE}, ${datasPositions.length} paciente(s)`);

  // ---- 4. Extract patient info ---------------------------------------------

  const patientRow = rows[patientRowIdx];
  const metaRows: Record<string, string[]> = {};
  const META_LABELS = ['Email', 'CPF', 'Local', 'Pagamento', 'Moeda', 'Taxa'];

  for (const label of META_LABELS) {
    const row = rows.find((r) => r[0]?.trim() === label);
    metaRows[label] = row ?? [];
  }

  interface PatientMeta {
    colStart: number;
    name: string;
    email: string;
    cpf: string;
    location: string;
    paymentModel: PaymentModel;
    currency: Currency;
    rateStr: string;
  }

  const patients: PatientMeta[] = [];

  for (const colStart of datasPositions) {
    // patient name is one column before "Datas" — actually at colStart itself
    // in the patientRow, names appear at the same column as Datas
    const name = patientRow[colStart]?.trim() ?? '';
    if (!name) continue;

    const email = metaRows['Email']?.[colStart]?.trim() ?? '';
    const cpf = metaRows['CPF']?.[colStart]?.trim() ?? '';
    const location = metaRows['Local']?.[colStart]?.trim() ?? '';
    const paymentModelStr = metaRows['Pagamento']?.[colStart]?.trim() ?? 'SESSAO';
    const currencyStr = metaRows['Moeda']?.[colStart]?.trim() ?? 'BRL';
    const rateStr = metaRows['Taxa']?.[colStart]?.trim() ?? '';

    if (!email) {
      log('warn', `Paciente "${name}" sem e-mail — ignorado`);
      continue;
    }

    const paymentModel: PaymentModel =
      paymentModelStr === 'MENSAL' ? 'MENSAL' : 'SESSAO';
    const currency: Currency = currencyStr.toUpperCase() === 'EUR' ? 'EUR' : 'BRL';

    patients.push({ colStart, name, email, cpf, location, paymentModel, currency, rateStr });
    log('info', `Paciente detectado: ${name} <${email}>`);
  }

  if (patients.length === 0) {
    log('err', 'Nenhum paciente detectado no CSV');
    summary.errors++;
    return summary;
  }

  // ---- 5. Parse month data rows -------------------------------------------

  interface MonthEntry {
    month: number;
    year: number;
    perPatient: Array<{
      colStart: number;
      sessionDates: string[];
      sessionCount: number;
      expectedAmount: number;
      amountPaid: number;
      observations: string;
    }>;
  }

  const monthEntries: MonthEntry[] = [];

  // Collect total rows for reconciliation
  const spreadsheetTotals: Array<{ label: string; value: number }> = [];

  for (let r = headerRowIdx + 1; r < rows.length; r++) {
    const row = rows[r];
    const col0 = row[0]?.trim() ?? '';
    if (!col0) continue;

    // Total reconciliation row
    if (col0.toLowerCase().startsWith('total recebido')) {
      const val = parseAmount(row[1] ?? '');
      if (val !== null) spreadsheetTotals.push({ label: col0, value: val });
      continue;
    }

    // Month row
    const monthInfo = parseMonthRow(col0);
    if (!monthInfo) continue;
    // Only process months for the target year
    if (monthInfo.year !== year) continue;

    const entry: MonthEntry = { month: monthInfo.month, year: monthInfo.year, perPatient: [] };

    for (const p of patients) {
      const c = p.colStart;
      const datesStr = row[c]?.trim() ?? '';
      const qtyStr = row[c + 1]?.trim() ?? '';
      const espStr = row[c + 2]?.trim() ?? '';
      const recStr = row[c + 3]?.trim() ?? '';
      const obs = row[c + 4]?.trim() ?? '';

      // Parse session dates: "03/01 10/01 17/01" → ISO strings for year/month
      const sessionDates: string[] = datesStr
        .split(/\s+/)
        .filter((d) => /^\d{2}\/\d{2}$/.test(d))
        .map((d) => {
          const [day, mon] = d.split('/');
          return `${monthInfo.year}-${mon.padStart(2, '0')}-${day.padStart(2, '0')}`;
        });

      const sessionCount = parseInt(qtyStr, 10) || sessionDates.length;
      const expectedAmount = parseAmount(espStr) ?? 0;
      const amountPaid = parseAmount(recStr) ?? 0;

      entry.perPatient.push({ colStart: c, sessionDates, sessionCount, expectedAmount, amountPaid, observations: obs });
    }

    monthEntries.push(entry);
  }

  log('info', `${monthEntries.length} mês(es) para importar no ano ${year}`);

  // ---- 6. Upsert patients and rates ---------------------------------------

  const patientIdMap = new Map<string, string>(); // email → DB id

  for (const p of patients) {
    try {
      const rateSegments = parseRateStr(p.rateStr, year);
      const initialRate = rateSegments[0]?.rate ?? 0;
      const initialFrom = rateSegments[0]?.effectiveFrom ?? new Date(`${year}-01-01`);

      if (!dryRun) {
        // Upsert patient by email
        let patient = await prisma.patient.findFirst({ where: { email: p.email } });

        if (!patient) {
          patient = await prisma.patient.create({
            data: {
              name: p.name,
              email: p.email,
              cpf: p.cpf || null,
              location: p.location || 'Brasil',
              paymentModel: p.paymentModel,
              currency: p.currency,
              status: 'ATIVO',
            },
          });
          log('ok', `Paciente criado: ${p.name}`);
        } else {
          await prisma.patient.update({
            where: { id: patient.id },
            data: {
              name: p.name,
              cpf: p.cpf || patient.cpf,
              location: p.location || patient.location,
              paymentModel: p.paymentModel,
              currency: p.currency,
            },
          });
          log('info', `Paciente atualizado: ${p.name}`);
        }

        patientIdMap.set(p.email, patient.id);
        summary.patientsUpserted++;

        // Upsert rate history segments
        for (const seg of rateSegments) {
          const existingRate = await prisma.rateHistory.findFirst({
            where: { patientId: patient.id, effectiveFrom: seg.effectiveFrom },
          });

          if (existingRate) {
            await prisma.rateHistory.update({
              where: { id: existingRate.id },
              data: { rate: seg.rate, effectiveTo: seg.effectiveTo },
            });
          } else {
            await prisma.rateHistory.create({
              data: {
                patientId: patient.id,
                rate: seg.rate,
                effectiveFrom: seg.effectiveFrom,
                effectiveTo: seg.effectiveTo,
              },
            });
            summary.ratesCreated++;
          }
        }

        log('ok', `Taxa(s) processada(s) para ${p.name}: ${rateSegments.map((s) => s.rate).join(' → ')}`);
      } else {
        // Dry-run: just log what would happen
        const existing = await prisma.patient.findFirst({ where: { email: p.email } });
        const action = existing ? 'atualizar' : 'criar';
        log('info', `[simulação] Vai ${action} paciente: ${p.name} (taxa inicial: ${initialRate}, vigência: ${initialFrom.toISOString().slice(0, 10)})`);
        patientIdMap.set(p.email, existing?.id ?? `dry-${p.email}`);
        summary.patientsUpserted++;
        summary.ratesCreated += rateSegments.length;
      }
    } catch (err) {
      log('err', `Erro ao processar paciente ${p.name}: ${String(err)}`);
      summary.errors++;
    }
  }

  // ---- 7. Upsert session records and payments ------------------------------

  for (const entry of monthEntries) {
    for (let i = 0; i < patients.length; i++) {
      const p = patients[i];
      const pd = entry.perPatient[i];
      if (!pd) continue;

      // Skip if no sessions and no payment for SESSAO patients
      if (p.paymentModel === 'SESSAO' && pd.sessionCount === 0 && pd.amountPaid === 0) {
        continue;
      }

      const patientId = patientIdMap.get(p.email);
      if (!patientId) continue;

      try {
        const { month, year: entryYear } = entry;
        const expectedAmount = pd.expectedAmount;
        const amountPaid = pd.amountPaid;
        const status = computePaymentStatus(amountPaid, expectedAmount, entryYear, month);

        if (!dryRun) {
          // Upsert SessionRecord
          const record = await prisma.sessionRecord.upsert({
            where: { patientId_year_month: { patientId, year: entryYear, month } },
            create: {
              patientId,
              year: entryYear,
              month,
              sessionDates: pd.sessionDates,
              sessionCount: pd.sessionCount,
              expectedAmount,
              observations: pd.observations || null,
            },
            update: {
              sessionDates: pd.sessionDates,
              sessionCount: pd.sessionCount,
              expectedAmount,
              observations: pd.observations || null,
              deletedAt: null,
            },
          });
          summary.sessionRecordsUpserted++;

          // Upsert Payment
          const existingPayment = await prisma.payment.findUnique({
            where: { sessionRecordId: record.id },
          });

          if (existingPayment) {
            await prisma.payment.update({
              where: { sessionRecordId: record.id },
              data: { amountPaid, status },
            });
          } else {
            await prisma.payment.create({
              data: { sessionRecordId: record.id, amountPaid, status },
            });
          }
          summary.paymentsUpserted++;

          log(
            amountPaid >= expectedAmount && expectedAmount > 0 ? 'ok' : 'warn',
            `${p.name} ${entryYear}/${String(month).padStart(2, '0')}: ${pd.sessionCount} sessão(ões), pago ${amountPaid}/${expectedAmount} [${status}]`,
          );
        } else {
          log(
            'info',
            `[simulação] ${p.name} ${entryYear}/${String(month).padStart(2, '0')}: ${pd.sessionCount} sessão(ões), pago ${amountPaid}/${expectedAmount} → status ${status}`,
          );
          summary.sessionRecordsUpserted++;
          summary.paymentsUpserted++;
        }
      } catch (err) {
        log('err', `Erro em ${p.name} ${entry.year}/${entry.month}: ${String(err)}`);
        summary.errors++;
      }
    }
  }

  // ---- 8. Reconciliation ---------------------------------------------------

  if (!dryRun) {
    // Compute DB totals per currency
    const dbTotals: Record<string, number> = { BRL: 0, EUR: 0 };

    for (const p of patients) {
      const patientId = patientIdMap.get(p.email);
      if (!patientId) continue;

      const payments = await prisma.payment.findMany({
        where: {
          sessionRecord: { patientId, year, deletedAt: null },
          deletedAt: null,
        },
      });
      const total = payments.reduce((sum, pay) => sum + Number(pay.amountPaid), 0);
      dbTotals[p.currency] = (dbTotals[p.currency] ?? 0) + total;
    }

    // Match against spreadsheet totals
    const currencyMap: Record<string, string> = { brasil: 'BRL', alemanha: 'EUR' };

    for (const st of spreadsheetTotals) {
      const key = Object.keys(currencyMap).find((k) => st.label.toLowerCase().includes(k));
      const currency = key ? currencyMap[key] : 'BRL';
      const dbTotal = dbTotals[currency] ?? 0;
      const diff = Math.round((st.value - dbTotal) * 100) / 100;
      const ok = Math.abs(diff) < 0.01;
      summary.reconciliation.push({ currency, spreadsheetTotal: st.value, dbTotal, diff, ok });
      if (ok) {
        log('ok', `Conciliação ${st.label}: planilha=${st.value} DB=${dbTotal} ✓`);
      } else {
        log('warn', `Conciliação ${st.label}: planilha=${st.value} DB=${dbTotal} DIVERGÊNCIA=${diff}`);
      }
    }
  }

  // ---- 9. Final summary ----------------------------------------------------

  const mode = dryRun ? '[SIMULAÇÃO] ' : '';
  log('info', `${mode}Resumo: ${summary.patientsUpserted} paciente(s), ${summary.ratesCreated} taxa(s), ${summary.sessionRecordsUpserted} registro(s), ${summary.paymentsUpserted} pagamento(s), ${summary.errors} erro(s)`);

  return summary;
}
