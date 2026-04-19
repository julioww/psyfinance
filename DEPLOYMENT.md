# Deployment Checklist — PsyFinance

Every item below must be verified before going live. Check off each item only after
confirming it manually.

---

## ENVIRONMENT

- [ ] `NODE_ENV=production` is set on the server
- [ ] All required env vars are present (the startup check will catch missing ones and exit)
- [ ] `JWT_SECRET` is at least 64 characters and randomly generated
      (`npx ts-node scripts/generate-secret.ts`)
- [ ] `DATABASE_URL` includes `?sslmode=require`
- [ ] `ALLOWED_ORIGIN` is set to the exact Flutter web app URL
      (no trailing slash, no wildcard — e.g. `https://psyfinance.example.com`)
- [ ] `BACKUP_PASSWORD` is set and stored separately from the backup files

---

## BACKEND

- [ ] Server is running behind HTTPS (valid TLS certificate, port 443)
- [ ] All `/api/*` routes return 401 without a valid JWT
      (run the auth middleware security test: `npm test`)
- [ ] Error responses in production do not contain stack traces
      (send an invalid request and verify the response body is `{ "error": "Internal server error" }`)
- [ ] Rate limiting is active on `POST /auth/login`
      (send 11 rapid requests and confirm the 11th returns 429)
- [ ] Helmet.js security headers are present in all responses
      (`curl -I https://your-domain.com/health` and verify `Content-Security-Policy`,
      `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`,
      `Strict-Transport-Security`)
- [ ] `X-Powered-By` header is **absent** from responses
- [ ] No `console.log` statements print patient data (run `grep -r 'console.log' src/`)

---

## DATABASE

- [ ] PostgreSQL data directory is on an encrypted volume (see SECURITY.md)
- [ ] Database is not publicly accessible (firewall: only the app server connects on port 5432)
- [ ] Database user has only the permissions Prisma needs (no superuser)
- [ ] Automated backups are scheduled and produce encrypted `.sql.gz.enc` files
- [ ] A test restore from backup has been performed and the data is intact

---

## FLUTTER WEB

- [ ] Built with:
      `flutter build web --release --dart-define=API_BASE_URL=https://your-api.example.com`
- [ ] No `localhost` URLs in the production build
      (`grep -r localhost psyfinance_app/build/web/`)
- [ ] JWT is **not** persisted in `localStorage`
      (open DevTools → Application → Storage → Local Storage — should be empty)
- [ ] Debug console output is suppressed
      (open DevTools → Console in the production build — no Flutter debug messages)

---

## ACCESS CONTROL

- [ ] The default/development password has been changed
      (`npx ts-node scripts/generate-password.ts <new-password>` → update `PSYFINANCE_PASSWORD_HASH`)
- [ ] The server is not accessible on any port other than 443 (HTTPS) and 22 (SSH)
- [ ] SSH access uses key-based authentication only (password auth disabled in `sshd_config`)
- [ ] The PostgreSQL port (5432) is firewalled from the public internet

---

## LGPD / GDPR

- [ ] A data processing record (ROPA) has been created documenting:
      - What personal data is stored (patient names, emails, CPFs, session dates, fees)
      - The legal basis (LGPD Art. 7 / Art. 11 — health professional records)
      - Who can access the data (only the practice operator)
      - Retention period (5 years from last activity per LGPD Art. 16)
- [ ] Patient consent for digital record-keeping has been obtained and documented
- [ ] A data breach response plan exists (see SECURITY.md — Incident response)
- [ ] ANPD contact information is on hand (https://www.gov.br/anpd/pt-br)

---

## POST-DEPLOYMENT SMOKE TEST

Run these checks immediately after deploying:

```bash
# 1. Health check
curl -s https://your-domain.com/health | jq .
# Expected: { "status": "ok", "timestamp": "..." }

# 2. Auth required on API
curl -s https://your-domain.com/api/patients
# Expected: 401

# 3. Valid login
curl -s -X POST https://your-domain.com/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"usuario":"<username>","senha":"<password>"}' | jq .
# Expected: { "token": "...", "expiresAt": "..." }

# 4. Rate limiter (run 11 times quickly)
for i in $(seq 1 11); do
  curl -s -o /dev/null -w "%{http_code}\n" -X POST https://your-domain.com/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"usuario":"wrong","senha":"wrong"}'
done
# Expected: first 10 → 401, 11th → 429

# 5. Security headers
curl -sI https://your-domain.com/health | grep -E 'Content-Security|X-Frame|X-Content|Referrer|Permissions|Strict-Transport|X-Powered'
# Expected: CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, HSTS present
# X-Powered-By must NOT appear
```
