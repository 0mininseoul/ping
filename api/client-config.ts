import type { VercelRequest, VercelResponse } from '@vercel/node';

/** Public client configuration only. Administrative credentials never leave Vercel. */
export function publicClientConfig(env: NodeJS.ProcessEnv) {
  const url = env.SUPABASE_URL;
  const anonKey = env.PING_SUPABASE_PUBLISHABLE_KEY;
  if (url !== 'https://qxjtprxvjmaxlbtljcjw.supabase.co' ||
      !anonKey?.startsWith('sb_publishable_')) return undefined;
  return { url, anonKey };
}

export default function handler(req: VercelRequest, res: VercelResponse): void {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).json({ error: 'method not allowed' });
    return;
  }
  const config = publicClientConfig(process.env);
  if (!config) {
    res.status(503).json({ error: 'client configuration unavailable' });
    return;
  }
  res.setHeader('Cache-Control', 'public, max-age=30, must-revalidate');
  if (req.method === 'HEAD') { res.status(200).end(); return; }
  res.status(200).json(config);
}
