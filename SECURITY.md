# Security Policy — PsyFinance

## Data processed

PsyFinance processes **special-category personal data** under both LGPD (Brazil) and
GDPR (Europe), specifically health-related data generated in the context of psychological
therapy:

| Data category | Examples | Legal basis |
|---|---|---|
| Patient identity | Name, email, CPF | LGPD Art. 7 § 1 (legitimate interest of the controller for professional records); LGPD Art. 11 (health data, informed consent) |
| Financial records | Session dates, fees paid, payment status | LGPD Art. 7 § V (performance of a contract with the data subject) |
| Therapy metadata | Session count per month, observations | LGPD Art. 11 (health data, controller is a healthcare professional) |

All data is stored exclusively on infrastructure controlled by the practice operator.
No data is shared with third parties.

---

## Security controls

### Authentication
- Single-user credential model: username + bcrypt-hashed password (cost 12).
- JWT tokens signed with HMAC-SHA256; minimum 64-character random secret.
- Tokens expire after **8 hours**; no "remember me" / persistent tokens.
- Token denylist: logout revokes the specific token's JTI, which is checked on every
  request for the token's remaining TTL.
- Constant-time login: `bcrypt.compare` is always called regardless of whether the
  username matches, preventing timing-based username enumeration.
- Rate limiting: maximum 10 login attempts per 15 minutes per IP.
- Account lockout: after 10 failed login attempts within 15 minutes, the IP is blocked
  for 1 hour. Lockout state is in-memory only (resets on server restart).

### Transport
- All production traffic must be served over HTTPS (TLS 1.2+).
- `Strict-Transport-Security: max-age=31536000; includeSubDomains` is set on all responses.

### API
- All `/api/*` routes require a valid JWT Bearer token.
- `/health` and `/auth/login` are the only public endpoints.
- Helmet.js sets `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer`, `Permissions-Policy`, and CSP on all responses.
- `X-Powered-By` is suppressed to prevent server fingerprinting.
- Request body size is capped at 100 KB to prevent large-payload attacks.
- CORS is restricted to the exact `ALLOWED_ORIGIN` configured in the environment.
- Production error responses never include stack traces, file paths, or database errors.

### Database
- All queries use Prisma's parameterized query API. No raw SQL interpolation.
- The PostgreSQL data directory **must** reside on an encrypted volume in production
  (see Encryption at rest below).
- The database port (5432) must be firewalled from the public internet; only the
  application server should be able to connect.
- `DATABASE_URL` must include `?sslmode=require` in production; the server validates
  this at startup and refuses to start without it.
- The database user should have only the permissions required by Prisma
  (SELECT, INSERT, UPDATE, DELETE on application tables; no superuser).

### Flutter web client
- The JWT is stored in Riverpod in-memory state only — never in `localStorage` or
  `sessionStorage`. A page refresh requires the user to log in again.
- The production build must be compiled with `--release` (disables `debugPrint` and
  asserts). `debugPrint` is additionally suppressed in `main.dart` via `kReleaseMode`.
- The API base URL is injected at build time via `--dart-define=API_BASE_URL=...`;
  no production URL is hardcoded in source.

### Logging
Log lines must never contain:
- Patient name, email, or CPF
- Payment amounts linked to a named individual
- Session dates linked to a named individual

Patient UUIDs may appear in logs for debugging. Failed login attempts are logged
with the source IP only.

---

## Encryption at rest

The PostgreSQL data directory should be stored on an encrypted volume. Recommended options:

**Linux (LUKS):**
```bash
# Create encrypted volume
cryptsetup luksFormat /dev/sdX
cryptsetup open /dev/sdX psyfinance-data
mkfs.ext4 /dev/mapper/psyfinance-data
mount /dev/mapper/psyfinance-data /var/lib/postgresql
```

**PostgreSQL column-level encryption (optional, defense-in-depth):**
```sql
-- Enable pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Encrypt a column at insert time
INSERT INTO patients (cpf) VALUES (pgp_sym_encrypt('123.456.789-00', 'key'));
```

Filesystem-level encryption is the minimum requirement; column-level encryption is
recommended for CPF fields as an additional defense-in-depth measure.

---

## Backup security

Backups are encrypted with AES-256-CBC (via `openssl enc -aes-256-cbc -pbkdf2`) using
`BACKUP_PASSWORD` before being written to disk.

**Backup files must be stored in a different physical location from the application.**

To decrypt:
```bash
openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:<BACKUP_PASSWORD> \
  -in backup.sql.gz.enc | gunzip > backup.sql
```

---

## Data retention (LGPD Art. 16)

Patient data should be reviewed annually. Patients who have been inactive for more than
**5 years** should be archived or deleted per LGPD Article 16 (data must be eliminated
after the purpose is fulfilled, unless retention is required by law).

PsyFinance uses soft-delete (`status: INATIVO`, `deletedAt`). A manual review process
is recommended to identify and remove data beyond the retention period.

---

## Reporting a security issue

Please report security vulnerabilities privately. Do **not** open a public GitHub issue.

Contact: **[practice operator email — fill in before deployment]**

Include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact

You will receive an acknowledgement within 48 hours.

---

## Incident response

If a breach is suspected:

1. **Isolate**: Immediately take the server offline or block public access.
2. **Preserve**: Take a snapshot of logs, database state, and running processes
   before making changes.
3. **Assess**: Determine which data was exposed (patient names, CPFs, session records).
4. **Notify (LGPD Art. 48)**: Notify the ANPD (Autoridade Nacional de Proteção de Dados)
   within **72 hours** of becoming aware of the breach.
   Notify affected patients without undue delay if the breach poses a significant risk.
5. **Remediate**: Rotate all secrets (JWT_SECRET, BACKUP_PASSWORD, database password).
   Invalidate all active sessions (restart the server to clear the in-memory denylist,
   which forces all users to log in again).
6. **Document**: Record the timeline, scope, and remediation actions taken.

ANPD contact: https://www.gov.br/anpd/pt-br
