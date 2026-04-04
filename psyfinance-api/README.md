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
```

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
