import jwt from 'jsonwebtoken';
import { randomUUID } from 'crypto';

// In-memory denylist for revoked token IDs (jti).
// On process restart the denylist is cleared, but tokens will expire naturally.
const denylist = new Set<string>();

// Read JWT_SECRET dynamically so tests can override via vi.stubEnv.
// In production the startup check in index.ts enforces minimum length before
// any request arrives. In development a short secret is allowed with a warning.
function secret(): string {
  const s = process.env.JWT_SECRET;
  if (!s) throw new Error('JWT_SECRET is not set');
  if (s.length < 64 && process.env.NODE_ENV === 'production') {
    throw new Error('JWT_SECRET must be at least 64 characters');
  }
  return s;
}

export interface TokenPayload {
  sub: string;
  jti: string;
  iat: number;
  exp: number;
}

export function signToken(username: string, expiresIn: string | number): string {
  const jti = randomUUID();
  return jwt.sign({ sub: username, jti }, secret(), { expiresIn } as jwt.SignOptions);
}

export function verifyToken(token: string): TokenPayload {
  const payload = jwt.verify(token, secret()) as TokenPayload;
  if (denylist.has(payload.jti)) {
    throw new Error('Token revoked');
  }
  return payload;
}

export function revokeToken(token: string): void {
  try {
    // Decode without verifying expiry so we can revoke expired tokens too
    const payload = jwt.verify(token, secret(), { ignoreExpiration: true }) as TokenPayload;
    denylist.add(payload.jti);
  } catch {
    // Ignore malformed tokens
  }
}
