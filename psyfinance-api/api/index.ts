// Vercel serverless entry point.
// Imports the configured Express app and exports it — Vercel handles HTTP serving.
// app.listen() is intentionally NOT called here.
import app from '../src/app';

export default app;
