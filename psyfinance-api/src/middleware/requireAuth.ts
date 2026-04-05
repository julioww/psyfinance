import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '../lib/auth';

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ message: 'Unauthorized' });
    return;
  }
  const token = authHeader.slice(7);
  try {
    verifyToken(token);
    next();
  } catch {
    res.status(401).json({ message: 'Unauthorized' });
  }
}
