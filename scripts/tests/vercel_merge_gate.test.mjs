import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const modulePath = new URL('../vercel-merge-gate.mjs', import.meta.url);
const sha = 'a'.repeat(40);
const pr = (id=229801971) => ({merged_at:'2026-10-12T00:00:00Z',merge_commit_sha:sha,base:{ref:'main',repo:{id:1241650801}},merged_by:{id}});
async function implementation() {
  assert.ok(fs.existsSync(modulePath), 'The Vercel merge gate does not exist yet');
  return await import(modulePath);
}
test('owner merge is held for the Mac migration runner',async()=>{const m=await implementation();assert.equal(m.decision([pr()],sha,'production'),'skip');});
test('other actual merger builds independently of commit author',async()=>{const m=await implementation();assert.equal(m.decision([pr(7)],sha,'production'),'build');});
test('unknown, unmerged, unrelated or directly pushed commits are held',async()=>{const m=await implementation();for(const prs of [[],[{...pr(),merged_at:null}],[{...pr(),merge_commit_sha:'b'.repeat(40)}],[{...pr(),merged_by:null}],[{...pr(),base:{ref:'other',repo:{id:1241650801}}}]])assert.equal(m.decision(prs,sha,'production'),'skip');});
test('preview builds never apply a migration',async()=>{const m=await implementation();assert.equal(m.decision([pr()],sha,'preview'),'build');});

test('missing environment cannot bypass the production hold',async()=>{const m=await implementation();assert.equal(m.decision([pr()],sha,undefined),'skip');});
