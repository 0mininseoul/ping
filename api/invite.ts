import type { VercelRequest, VercelResponse } from '@vercel/node';
import { buildInviteOpenGraphHTML } from './_lib/openGraph';

export default function handler(req: VercelRequest, res: VercelResponse): void {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).json({ error: 'method not allowed' });
    return;
  }

  const token = queryValue(req.query.token);
  if (!token) {
    res.status(404).send('not found');
    return;
  }

  const html = buildInviteOpenGraphHTML(token);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
  res.status(200);
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  res.send(html);
}

function queryValue(value: string | string[] | undefined): string | undefined {
  if (Array.isArray(value)) return value[0];
  return value;
}
