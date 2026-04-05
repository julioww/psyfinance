# PsyFinance API

Node.js + TypeScript REST API for PsyFinance — financial management for a solo psychology practice.

## Stack

- **Runtime:** Node.js 20+ / TypeScript
- **Framework:** Express
- **Database:** PostgreSQL 15+
- **ORM:** Prisma
- **Testing:** Vitest

## Environment Variables

Copy `.env.example` to `.env` and fill in your values:

```
DATABASE_URL="postgresql://<user>:<password>@localhost:5432/psyfinance?schema=psyfinance"
PORT=3000

# Authentication (required for production)
PSYFINANCE_USERNAME=psico
PSYFINANCE_PASSWORD_HASH=   # bcrypt hash — generate with: npx ts-node scripts/generate-password.ts <password>
JWT_SECRET=                  # random secret — generate with: node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

### Generating credentials

```bash
# 1. Generate a bcrypt hash for your password
npx ts-node scripts/generate-password.ts mySecretPassword

# 2. Generate a JWT secret
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Copy the outputs into `.env`.

> **Note:** The `?schema=psyfinance` suffix is required. The database user needs CREATE privilege
> on the `psyfinance` schema. If you're using a restricted user, run as a superuser:
> ```sql
> GRANT CREATE ON SCHEMA psyfinance TO <user>;
> ```

## Setup

```bash
npm install

# Push schema to database (no shadow DB required)
npm run db:generate
npx prisma db push

# Or, with full migrations (requires shadow DB / superuser):
npm run db:migrate

# Seed with sample data
npm run db:seed
```

## Running

```bash
# Development (with ts-node, auto-reload)
npm run dev

# Production
npm run build
npm start
```

API will be available at `http://localhost:3000`.

## Endpoints

| Method | Path      | Description              |
|--------|-----------|--------------------------|
| GET    | /health   | DB connectivity check    |

## Testing

```bash
npm test
```

## Database Management

```bash
# Open Prisma Studio (visual DB browser)
npm run db:studio
```

## Data Model

```
Patient
  ├── RateHistory[]   (rate per period)
  └── SessionRecord[]
        └── Payment   (one-to-one)
```

- **Patient:** name, email, CPF, location (free string), paymentModel (SESSAO|MENSAL), currency (BRL|EUR)
- **RateHistory:** rate effective date ranges per patient
- **SessionRecord:** sessions per patient/month, with session dates as JSON array of "DD/MM" strings
- **Payment:** payment status and amount for each session record

All entities support soft delete via `deletedAt`.

## Migração de dados

Ferramenta de migração única para importar dados históricos do Google Sheets
("Financeiro Psicologia") dos anos 2023–2026.

### Formato do CSV

Exporte cada aba de ano como CSV no Google Sheets (**Arquivo → Fazer download → CSV**).

O arquivo deve seguir este layout (GROUP_SIZE = 5 colunas por paciente):

```
Paciente,Nome1,,,,,Nome2,,,,,Nome3,,,,
Email,email1@…,,,,,email2@…,,,,,email3@…,,,,
CPF,CPF1,,,,,CPF2,,,,,CPF3,,,,
Local,Brasil,,,,,Alemanha,,,,,Brasil,,,,
Pagamento,SESSAO,,,,,SESSAO,,,,,MENSAL,,,,
Moeda,BRL,,,,,EUR,,,,,BRL,,,,
Taxa,"R$70 / Mar 2024 - R$75",,,,,€60,,,,,R$350,,,,
Mês,Datas,Qtd,Esperado,Recebido,Obs,Datas,Qtd,Esperado,Recebido,Obs,Datas,Qtd,Esperado,Recebido,Obs
Jan/2024,"03/01 10/01 17/01",3,210,210,,07/01,1,60,60,,"08/01 15/01",2,350,350,
…
Total recebido Brasil,1200,,,,,,,,,,,,,,,,
Total recebido Alemanha,180,,,,,,,,,,,,,,,,
```

Notação de taxa: `"R$70 / Mar 2024 - R$75"` cria dois registros de
`RateHistory` — R$70 vigente até fev/2024, R$75 a partir de mar/2024.

### CLI

Execute a partir do diretório `psyfinance-api/`:

```bash
# Simulação (dry-run) — valida sem gravar no banco
npx ts-node scripts/import.ts --file scripts/sample-import.csv --year 2024 --dry-run

# Importação real
npx ts-node scripts/import.ts --file ~/Downloads/2026.csv --year 2026

# Ajuda
npx ts-node scripts/import.ts --help
```

**Opções:**

| Flag | Descrição |
|------|-----------|
| `--file <path>` | Caminho para o arquivo CSV |
| `--year <ano>` | Ano de referência (ex: 2024) |
| `--dry-run` | Valida sem gravar dados no banco |

### HTTP endpoint

```
POST /api/import?year=2024&dryRun=true
Content-Type: text/csv

<conteúdo do CSV>
```

Resposta: `application/x-ndjson` — stream de linhas JSON:

```json
{"level":"info","message":"CSV carregado: 15 linhas"}
{"level":"ok","message":"Paciente criado: Ana Lima"}
{"level":"warn","message":"Conciliação BRL: divergência=5"}
{"level":"info","message":"Resumo: 3 paciente(s), 4 taxa(s), 9 registro(s), 9 pagamento(s), 0 erro(s)"}
```

Níveis: `info` · `ok` · `warn` · `err`

### Idempotência

- **Patient**: upsert por `email`
- **RateHistory**: upsert por `(patientId, effectiveFrom)`
- **SessionRecord**: upsert por `(patientId, year, month)` — índice único no schema
- **Payment**: upsert por `sessionRecordId` — relação 1-para-1

Rodar o script múltiplas vezes com o mesmo CSV é seguro.
