/**
 * scripts/generate-password.ts
 * Generates a bcrypt hash for use as PSYFINANCE_PASSWORD_HASH in .env
 *
 * Usage:
 *   npx ts-node scripts/generate-password.ts <plain-text-password>
 *
 * Example:
 *   npx ts-node scripts/generate-password.ts mySecretPass123
 */

import bcrypt from 'bcrypt';

const SALT_ROUNDS = 12;

async function main() {
  const password = process.argv[2];
  if (!password) {
    console.error('Usage: npx ts-node scripts/generate-password.ts <password>');
    process.exit(1);
  }

  const hash = await bcrypt.hash(password, SALT_ROUNDS);
  console.log('\nCopy this value into your .env file:\n');
  console.log(`PSYFINANCE_PASSWORD_HASH=${hash}\n`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
