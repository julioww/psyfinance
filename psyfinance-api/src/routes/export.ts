import { Router, Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import PDFDocument from 'pdfkit';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const MONTHS_PT = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

function buildCsv(rows: (string | number)[][]): string {
  return rows
    .map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(','))
    .join('\n');
}

function sendCsv(res: Response, filename: string, rows: (string | number)[][]): void {
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.send(buildCsv(rows));
}

function sendPdf(
  res: Response,
  filename: string,
  buildFn: (doc: PDFKit.PDFDocument) => void,
): void {
  const doc = new PDFDocument({ margin: 40, size: 'A4' });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  doc.pipe(res);
  buildFn(doc);
  doc.end();
}

function pdfHeader(doc: PDFKit.PDFDocument, subtitle: string): void {
  doc.fontSize(20).font('Helvetica-Bold').fillColor('#1A6B5A').text('PsyFinance', { align: 'center' });
  doc.fontSize(12).font('Helvetica').fillColor('#333333').text(subtitle, { align: 'center' });
  doc.moveDown(0.8);
  doc
    .moveTo(doc.page.margins.left, doc.y)
    .lineTo(doc.page.width - doc.page.margins.right, doc.y)
    .strokeColor('#CCCCCC')
    .stroke();
  doc.moveDown(0.6);
}

function pdfSectionHeader(doc: PDFKit.PDFDocument, label: string): void {
  doc.moveDown(0.4);
  doc.fontSize(12).font('Helvetica-Bold').fillColor('#1A6B5A').text(label);
  doc.moveDown(0.2);
}

function pdfFooter(doc: PDFKit.PDFDocument): void {
  const date = new Date().toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  });
  doc.moveDown(1.5);
  doc
    .moveTo(doc.page.margins.left, doc.y)
    .lineTo(doc.page.width - doc.page.margins.right, doc.y)
    .strokeColor('#CCCCCC')
    .stroke();
  doc.moveDown(0.3);
  doc.fontSize(8).font('Helvetica').fillColor('#888888').text(`Gerado em ${date}`, { align: 'right' });
}

// ---------------------------------------------------------------------------
// GET /api/export/monthly?year=2026&format=csv|pdf
// ---------------------------------------------------------------------------

router.get('/monthly', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  const format = ((req.query['format'] as string) ?? 'csv').toLowerCase();

  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const records = await prisma.sessionRecord.findMany({
    where: { year, deletedAt: null, patient: { status: 'ATIVO', deletedAt: null } },
    include: {
      patient: { select: { name: true, currency: true, location: true } },
      payment: { select: { amountPaid: true, status: true, revenueShareAmount: true } },
    },
    orderBy: [{ month: 'asc' }, { patient: { name: 'asc' } }],
  });

  if (format === 'pdf') {
    sendPdf(res, `psyfinance-mensal-${year}.pdf`, (doc) => {
      pdfHeader(doc, `Relatório Mensal — ${year}`);

      const brlRecs = records.filter((r) => r.patient.currency === 'BRL');
      const eurRecs = records.filter((r) => r.patient.currency === 'EUR');

      for (const [label, recs] of [
        ['BRL — Real brasileiro', brlRecs],
        ['EUR — Euro', eurRecs],
      ] as [string, typeof records][]) {
        if (recs.length === 0) continue;
        pdfSectionHeader(doc, label);

        for (const r of recs) {
          const avg = r.sessionCount > 0 ? Number(r.expectedAmount) / r.sessionCount : 0;
          const paid = r.payment ? Number(r.payment.amountPaid) : 0;
          const balance = Number(r.expectedAmount) - paid;
          const repass = r.payment?.revenueShareAmount
            ? Number(r.payment.revenueShareAmount)
            : 0;

          doc
            .fontSize(9)
            .font('Helvetica-Bold')
            .fillColor('#333333')
            .text(
              `${r.patient.name}  •  ${MONTHS_PT[r.month - 1]}  •  ${r.sessionCount} sess.`,
              { continued: false },
            );
          doc
            .fontSize(9)
            .font('Helvetica')
            .fillColor('#555555')
            .text(
              `  Médio: ${avg.toFixed(2)}  |  Esperado: ${Number(r.expectedAmount).toFixed(2)}  |  Pago: ${paid.toFixed(2)}  |  Saldo: ${balance.toFixed(2)}  |  Repasse: ${repass.toFixed(2)}  |  ${r.payment?.status ?? 'PENDENTE'}`,
            );
          if (r.observations) {
            doc
              .fontSize(8)
              .fillColor('#888888')
              .text(`  Obs: ${r.observations}`);
          }
          doc.moveDown(0.1);
        }
      }

      pdfFooter(doc);
    });
    return;
  }

  const header = [
    'Nome', 'Localização', 'Moeda', 'Mês', 'Sessões',
    'Preço Médio/Sessão', 'Valor Esperado', 'Valor Pago', 'Saldo',
    'Status', 'Repasse', 'Observações',
  ];
  const rows = records.map((r) => {
    const avg = r.sessionCount > 0 ? Number(r.expectedAmount) / r.sessionCount : 0;
    const paid = r.payment ? Number(r.payment.amountPaid) : 0;
    const repass = r.payment?.revenueShareAmount
      ? Number(r.payment.revenueShareAmount)
      : 0;
    return [
      r.patient.name,
      r.patient.location,
      r.patient.currency,
      MONTHS_PT[r.month - 1]!,
      r.sessionCount,
      avg.toFixed(2),
      Number(r.expectedAmount).toFixed(2),
      paid.toFixed(2),
      (Number(r.expectedAmount) - paid).toFixed(2),
      r.payment?.status ?? 'PENDENTE',
      repass.toFixed(2),
      r.observations ?? '',
    ];
  });

  sendCsv(res, `psyfinance-mensal-${year}.csv`, [header, ...rows]);
});

// ---------------------------------------------------------------------------
// GET /api/export/annual?year=2026&format=csv|pdf
// ---------------------------------------------------------------------------

router.get('/annual', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  const format = ((req.query['format'] as string) ?? 'csv').toLowerCase();

  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      sessionRecords: {
        where: { year, deletedAt: null },
        include: {
          payment: { select: { amountPaid: true, revenueShareAmount: true } },
        },
      },
    },
    orderBy: [{ location: 'asc' }, { name: 'asc' }],
  });

  const rows = patients.map((p) => {
    const totalSessions = p.sessionRecords.reduce((a, r) => a + r.sessionCount, 0);
    const totalExpected = p.sessionRecords.reduce(
      (a, r) => a + Number(r.expectedAmount),
      0,
    );
    const totalReceived = p.sessionRecords.reduce(
      (a, r) => a + (r.payment ? Number(r.payment.amountPaid) : 0),
      0,
    );
    const totalRepass = p.sessionRecords.reduce(
      (a, r) =>
        a + (r.payment?.revenueShareAmount ? Number(r.payment.revenueShareAmount) : 0),
      0,
    );
    const avgPrice = totalSessions > 0 ? totalExpected / totalSessions : 0;
    return {
      name: p.name,
      location: p.location,
      currency: p.currency,
      totalSessions,
      avgPrice,
      totalExpected,
      totalReceived,
      balance: totalExpected - totalReceived,
      totalRepass,
    };
  });

  if (format === 'pdf') {
    sendPdf(res, `psyfinance-anual-${year}.pdf`, (doc) => {
      pdfHeader(doc, `Relatório Anual — ${year}`);

      const brlRows = rows.filter((r) => r.currency === 'BRL');
      const eurRows = rows.filter((r) => r.currency === 'EUR');

      for (const [label, recs] of [
        ['BRL — Real brasileiro', brlRows],
        ['EUR — Euro', eurRows],
      ] as [string, typeof rows][]) {
        if (recs.length === 0) continue;
        pdfSectionHeader(doc, label);

        for (const r of recs) {
          doc
            .fontSize(9)
            .font('Helvetica-Bold')
            .fillColor('#333333')
            .text(`${r.name}  •  ${r.location}  •  ${r.totalSessions} sess.`);
          doc
            .fontSize(9)
            .font('Helvetica')
            .fillColor('#555555')
            .text(
              `  Médio: ${r.avgPrice.toFixed(2)}  |  Esperado: ${r.totalExpected.toFixed(2)}  |  Recebido: ${r.totalReceived.toFixed(2)}  |  Saldo: ${r.balance.toFixed(2)}  |  Repasse: ${r.totalRepass.toFixed(2)}`,
            );
          doc.moveDown(0.1);
        }
      }

      pdfFooter(doc);
    });
    return;
  }

  const header = [
    'Nome', 'Localização', 'Moeda', 'Total Sessões',
    'Preço Médio/Sessão', 'Total Esperado', 'Total Recebido',
    'Saldo Total', 'Repasse Total',
  ];
  const csvRows = rows.map((r) => [
    r.name,
    r.location,
    r.currency,
    r.totalSessions,
    r.avgPrice.toFixed(2),
    r.totalExpected.toFixed(2),
    r.totalReceived.toFixed(2),
    r.balance.toFixed(2),
    r.totalRepass.toFixed(2),
  ]);

  sendCsv(res, `psyfinance-anual-${year}.csv`, [header, ...csvRows]);
});

// ---------------------------------------------------------------------------
// GET /api/export/summary?year=2026&format=csv|pdf
// ---------------------------------------------------------------------------

router.get('/summary', async (req: Request, res: Response) => {
  const year = parseInt(req.query['year'] as string, 10);
  const format = ((req.query['format'] as string) ?? 'csv').toLowerCase();

  if (isNaN(year)) {
    res.status(400).json({ message: 'year é obrigatório' });
    return;
  }

  const patients = await prisma.patient.findMany({
    where: { status: 'ATIVO', deletedAt: null },
    include: {
      sessionRecords: {
        where: { year, deletedAt: null },
        include: {
          payment: { select: { amountPaid: true, revenueShareAmount: true } },
        },
      },
    },
    orderBy: [{ location: 'asc' }, { name: 'asc' }],
  });

  const rows = patients
    .map((p) => {
      const totalSessions = p.sessionRecords.reduce((a, r) => a + r.sessionCount, 0);
      const totalExpected = p.sessionRecords.reduce(
        (a, r) => a + Number(r.expectedAmount),
        0,
      );
      const totalReceived = p.sessionRecords.reduce(
        (a, r) => a + (r.payment ? Number(r.payment.amountPaid) : 0),
        0,
      );
      const totalRepass = p.sessionRecords.reduce(
        (a, r) =>
          a + (r.payment?.revenueShareAmount ? Number(r.payment.revenueShareAmount) : 0),
        0,
      );
      const avgPrice = totalSessions > 0 ? totalExpected / totalSessions : 0;
      return {
        name: p.name,
        location: p.location,
        currency: p.currency,
        totalSessions,
        avgPrice,
        totalExpected,
        totalReceived,
        balance: totalExpected - totalReceived,
        totalRepass,
      };
    })
    .filter((r) => r.totalSessions > 0);

  if (format === 'pdf') {
    sendPdf(res, `psyfinance-resumo-${year}.pdf`, (doc) => {
      pdfHeader(doc, `Resumo Anual — ${year}`);

      const brlRows = rows.filter((r) => r.currency === 'BRL');
      const eurRows = rows.filter((r) => r.currency === 'EUR');

      for (const [label, recs] of [
        ['BRL — Real brasileiro', brlRows],
        ['EUR — Euro', eurRows],
      ] as [string, typeof rows][]) {
        if (recs.length === 0) continue;
        pdfSectionHeader(doc, label);

        for (const r of recs) {
          doc
            .fontSize(9)
            .font('Helvetica-Bold')
            .fillColor('#333333')
            .text(`${r.name}  •  ${r.location}  •  ${r.totalSessions} sess.`);
          doc
            .fontSize(9)
            .font('Helvetica')
            .fillColor('#555555')
            .text(
              `  Médio: ${r.avgPrice.toFixed(2)}  |  Esperado: ${r.totalExpected.toFixed(2)}  |  Recebido: ${r.totalReceived.toFixed(2)}  |  Saldo: ${r.balance.toFixed(2)}`,
            );
          doc.moveDown(0.1);
        }
      }

      pdfFooter(doc);
    });
    return;
  }

  const header = [
    'Nome', 'Localização', 'Moeda', 'Total Sessões',
    'Preço Médio/Sessão', 'Total Esperado', 'Total Recebido',
    'Saldo Total', 'Repasse Total',
  ];
  const csvRows = rows.map((r) => [
    r.name,
    r.location,
    r.currency,
    r.totalSessions,
    r.avgPrice.toFixed(2),
    r.totalExpected.toFixed(2),
    r.totalReceived.toFixed(2),
    r.balance.toFixed(2),
    r.totalRepass.toFixed(2),
  ]);

  sendCsv(res, `psyfinance-resumo-${year}.csv`, [header, ...csvRows]);
});

export default router;
