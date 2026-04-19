import { Router, Request, Response } from 'express';
import bcrypt from 'bcrypt';
import { signToken, revokeToken, verifyToken } from '../lib/auth';

const router = Router();

// ---------------------------------------------------------------------------
// Account lockout — in-memory Map<ip, LockoutEntry>
// After MAX_FAILURES failures from the same IP within LOCKOUT_WINDOW_MS,
// block that IP for LOCKOUT_DURATION_MS.
// ---------------------------------------------------------------------------
interface LockoutEntry {
  count: number;
  firstFailAt: number;
  lockedUntil: number | null;
}

export const lockoutMap = new Map<string, LockoutEntry>();

const LOCKOUT_WINDOW_MS = 15 * 60 * 1000;  // 15 minutes
const LOCKOUT_DURATION_MS = 60 * 60 * 1000; // 1 hour
const MAX_FAILURES = 10;

function getClientIp(req: Request): string {
  return req.ip ?? 'unknown';
}

function isLockedOut(ip: string): boolean {
  const entry = lockoutMap.get(ip);
  if (!entry || entry.lockedUntil === null) return false;
  if (Date.now() < entry.lockedUntil) return true;
  lockoutMap.delete(ip); // lock expired
  return false;
}

function recordFailure(ip: string): void {
  const now = Date.now();
  const entry = lockoutMap.get(ip);

  if (!entry || now - entry.firstFailAt > LOCKOUT_WINDOW_MS) {
    lockoutMap.set(ip, { count: 1, firstFailAt: now, lockedUntil: null });
    return;
  }

  entry.count += 1;
  if (entry.count >= MAX_FAILURES) {
    entry.lockedUntil = now + LOCKOUT_DURATION_MS;
    // Log IP only — never log attempted username or password
    console.warn(`[auth] IP locked out after ${MAX_FAILURES} failed login attempts: ${ip}`);
  }
}

function clearFailures(ip: string): void {
  lockoutMap.delete(ip);
}

// ---------------------------------------------------------------------------
// Dummy hash used for constant-time bcrypt comparison when the username is
// wrong. Prevents timing-based username enumeration.
// ---------------------------------------------------------------------------
const DUMMY_HASH = '$2b$12$invalidhashfortimingprotection000000000000000000000000';

// ---------------------------------------------------------------------------
// POST /auth/login
// ---------------------------------------------------------------------------
router.post('/login', async (req: Request, res: Response) => {
  const ip = getClientIp(req);

  if (isLockedOut(ip)) {
    res.status(429).end();
    return;
  }

  // Read env vars dynamically so tests can stub them via vi.stubEnv
  const USERNAME = process.env.PSYFINANCE_USERNAME ?? '';
  const PASSWORD_HASH = process.env.PSYFINANCE_PASSWORD_HASH ?? '';

  const { usuario, senha } = req.body as {
    usuario?: string;
    senha?: string;
    lembrar?: boolean; // accepted but ignored — 30d tokens are not issued for web
  };

  if (!usuario || !senha) {
    res.status(401).json({ message: 'Credenciais inválidas' });
    return;
  }

  // Always run bcrypt.compare regardless of whether the username matches,
  // so the response time is constant and cannot reveal whether the username exists.
  const usernameMatch = USERNAME.length > 0 && usuario === USERNAME;
  const hash = usernameMatch && PASSWORD_HASH.length > 0 ? PASSWORD_HASH : DUMMY_HASH;

  let passwordMatch = false;
  try {
    passwordMatch = await bcrypt.compare(senha, hash);
  } catch {
    passwordMatch = false;
  }

  if (!usernameMatch || !passwordMatch) {
    // Log IP only — never log the attempted username or password
    console.warn(`[auth] Failed login attempt from ${ip}`);
    recordFailure(ip);
    res.status(401).json({ message: 'Credenciais inválidas' });
    return;
  }

  clearFailures(ip);

  // Always 8-hour expiry — no "remember me" / 30d tokens on web
  const token = signToken(USERNAME, '8h');

  const parts = token.split('.');
  const payload = JSON.parse(Buffer.from(parts[1]!, 'base64url').toString());
  const expiresAt = new Date(payload.exp * 1000).toISOString();

  res.json({ token, expiresAt });
});

// ---------------------------------------------------------------------------
// POST /auth/logout
// ---------------------------------------------------------------------------
router.post('/logout', (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    revokeToken(authHeader.slice(7));
  }
  res.json({ message: 'Sessão encerrada' });
});

// ---------------------------------------------------------------------------
// POST /auth/change-password — requires valid token
// ---------------------------------------------------------------------------
router.post('/change-password', async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ message: 'Unauthorized' });
    return;
  }
  try {
    verifyToken(authHeader.slice(7));
  } catch {
    res.status(401).json({ message: 'Unauthorized' });
    return;
  }

  const PASSWORD_HASH = process.env.PSYFINANCE_PASSWORD_HASH ?? '';

  const { senhaAtual, novaSenha } = req.body as {
    senhaAtual?: string;
    novaSenha?: string;
  };

  if (!senhaAtual || !novaSenha) {
    res.status(400).json({ message: 'Campos obrigatórios ausentes' });
    return;
  }

  if (PASSWORD_HASH.length === 0) {
    res.status(500).json({ message: 'Servidor não configurado com senha' });
    return;
  }

  const currentMatch = await bcrypt.compare(senhaAtual, PASSWORD_HASH);
  if (!currentMatch) {
    res.status(401).json({ message: 'Senha atual incorreta' });
    return;
  }

  const newHash = await bcrypt.hash(novaSenha, 12);
  res.json({
    message: 'Hash gerado. Atualize PSYFINANCE_PASSWORD_HASH e reinicie o servidor.',
    newHash,
  });
});

export default router;
