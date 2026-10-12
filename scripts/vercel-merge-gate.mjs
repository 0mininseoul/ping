import {pathToFileURL} from 'node:url';

export function decision(prs, sha, environment) {
  if (environment === 'preview' || environment === 'development') return 'build';
  if (environment !== 'production') return 'skip';
  if (!/^[a-f0-9]{40}$/.test(sha ?? '')) return 'skip';
  const pr = prs.find(p => p.merged_at && p.merge_commit_sha === sha &&
    p.base?.ref === 'main' && p.base?.repo?.id === 1241650801);
  if (!pr?.merged_by?.id) return 'skip';
  return pr.merged_by.id === 229801971 ? 'skip' : 'build';
}

export async function main() {
  const sha = process.env.VERCEL_GIT_COMMIT_SHA;
  const environment = process.env.VERCEL_ENV;
  if (environment === 'preview' || environment === 'development') return 1;
  if (environment !== 'production') return 0;
  if (!/^[a-f0-9]{40}$/.test(sha ?? '')) return 0;
  try {
    const endpoint = `https://api.github.com/repos/0mininseoul/ping/commits/${sha}/pulls`;
    for (let attempt = 0; attempt < 4; attempt++) {
      const response = await fetch(endpoint, {headers:{Accept:'application/vnd.github+json'},signal:AbortSignal.timeout(10000)});
      if (!response.ok) return 0;
      const summaries = await response.json();
      const candidates = summaries.filter(p => p.merge_commit_sha === sha && p.base?.ref === 'main');
      const prs = await Promise.all(candidates.map(async p => {
        if (p.merged_by) return p;
        const r = await fetch(`https://api.github.com/repos/0mininseoul/ping/pulls/${p.number}`, {headers:{Accept:'application/vnd.github+json'},signal:AbortSignal.timeout(10000)});
        if (!r.ok) throw new Error('Cannot verify actual merger');
        return await r.json();
      }));
      if (prs.some(p => p.merged_at && p.merged_by?.id)) {
        const result = decision(prs, sha, environment);
        console.log(result === 'build' ? 'Non-owner merge: Vercel-only release.' : 'Owner merge: waiting for this Mac to verify migrations.');
        return result === 'build' ? 1 : 0;
      }
      if (attempt < 3) await new Promise(resolve => setTimeout(resolve, 1500));
    }
  } catch { /* Never release an unidentified production merge. */ }
  console.log('Production build held: merge identity could not be verified.');
  return 0;
}

if (!process.argv[1] || import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = await main();
