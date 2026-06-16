import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { buildInviteOpenGraphHTML } from '../openGraph';

const projectRoot = resolve(__dirname, '../../..');

describe('Open Graph metadata', () => {
  it('ships a crawlable absolute image in the default HTML', () => {
    const html = readFileSync(resolve(projectRoot, 'web/index.html'), 'utf8');

    expect(html).toContain('property="og:image"');
    expect(html).toContain('content="https://0minping.vercel.app/app-icon.png"');
    expect(html).toContain('name="twitter:image"');
  });

  it('server-renders invite URLs for KakaoTalk before falling back to the SPA shell', () => {
    const vercel = JSON.parse(readFileSync(resolve(projectRoot, 'vercel.json'), 'utf8'));
    const inviteRewrites = vercel.rewrites.filter((rewrite: { source: string }) => rewrite.source === '/invite/:token');

    expect(inviteRewrites[0]).toMatchObject({
      source: '/invite/:token',
      destination: '/api/invite?token=:token',
    });
    expect(JSON.stringify(inviteRewrites[0].has)).toContain('kakaotalk');
    expect(inviteRewrites[1]).toMatchObject({
      source: '/invite/:token',
      destination: '/index.html',
    });
  });

  it('builds invite HTML with absolute Open Graph image metadata', () => {
    const html = buildInviteOpenGraphHTML('abc123');

    expect(html).toContain('property="og:title" content="Ping 초대 링크"');
    expect(html).toContain('property="og:url" content="https://0minping.vercel.app/invite/abc123"');
    expect(html).toContain('property="og:image" content="https://0minping.vercel.app/app-icon.png"');
    expect(html).toContain('name="twitter:image" content="https://0minping.vercel.app/app-icon.png"');
    expect(html).toContain('href="ping://invite/abc123"');
  });
});
