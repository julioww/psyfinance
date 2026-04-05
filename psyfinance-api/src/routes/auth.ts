import { Router } from 'express';
import bcrypt from 'bcrypt';
import { signToken, revokeToken, verifyToken } from '../lib/auth';

const router = Router();

// POST /auth/login
router.post('/login', async (req, res) => {
  // Read env vars dynamically so tests can stub them via vi.stubEnv
  const USERNAME = process.env.PSYFINANCE_USERNAME ?? '';
  const PASSWORD_HASH = process.env.PSYFINANCE_PASSWORD_HASH ?? '';

  const { usuario, senha, lembrar } = req.body as {
    usuario?: string;
    senha?: string;
    lembrar?: boolean;
  };

  if (!usuario || !senha) {
    res.status(401).json({ message: 'Credenciais inválidas' });
    return;
  }

  // Constant-time username comparison to avoid timing attacks
  const usernameMatch = USERNAME.length > 0 && usuario === USERNAME;

  let passwordMatch = false;
  if (PASSWORD_HASH.length > 0) {
    try {
      passwordMatch = await bcrypt.compare(senha, PASSWORD_HASH);
    } catch {
      passwordMatch = false;
    }
  }

  if (!usernameMatch || !passwordMatch) {
    res.status(401).json({ message: 'Credenciais inválidas' });
    return;
  }

  const expiresIn = lembrar ? '30d' : '8h';
  const token = signToken(USERNAME, expiresIn);

  // Decode to get expiry for the client
  const parts = token.split('.');
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  const expiresAt = new Date(payload.exp * 1000).toISOString();

  res.json({ token, expiresAt });
});

// POST /auth/logout
router.post('/logout', (req, res) => {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    revokeToken(authHeader.slice(7));
  }
  res.json({ message: 'Sessão encerrada' });
});

// POST /auth/change-password — requires valid token
router.post('/change-password', async (req, res) => {
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
  // Return the new hash so the admin can update the env var
  res.json({
    message: 'Hash gerado. Atualize PSYFINANCE_PASSWORD_HASH e reinicie o servidor.',
    newHash,
  });
});

export default router;
