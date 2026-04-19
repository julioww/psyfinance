/**
 * scripts/generate-secret.ts
 * Prints a cryptographically random 64-character hex string suitable for use
 * as JWT_SECRET.
 *
 * Usage:
 *   npx ts-node scripts/generate-secret.ts
 */

import { randomBytes } from 'crypto';

console.log(randomBytes(32).toString('hex'));
