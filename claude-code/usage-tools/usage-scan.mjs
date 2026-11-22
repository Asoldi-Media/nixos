// Sums Claude Code token usage from local transcript logs. Prints numbers only, never message content.
// Usage: node usage-scan.mjs <sinceISO, e.g. 2026-11-15>
// Cost is an API-price stand-in ($): Anthropic does not publish how the plan meters tokens.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const since = process.argv[2] || '1970-01-01';
const root = path.join(os.homedir(), '.claude', 'projects');

// $ per million tokens, Opus 5.5 list prices; other models scaled by their price ratio.
const W = { input: 4, out: 20, cr: 0.2, cw5: 5, cw1h: 8 };
const scale = m => (/haiku-5/.test(m) ? 0.025 : /haiku/.test(m) ? 0.25 : /sonnet/.test(m) ? 0.5 : /fable|mythos/.test(m) ? 2 : 1);

const files = [];
(function walk(d) {
  let ents; try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
  for (const e of ents) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.jsonl')) files.push(p); }
})(root);

const blank = () => ({ msgs: 0, input: 0, out: 0, cr: 0, cw5: 0, cw1h: 0, cost: 0, c: { input: 0, out: 0, cr: 0, cw5: 0, cw1h: 0 } });
const byModel = {}, bySession = {}, byDay = {}, tot = blank();
const seen = new Set();
let subCost = 0;

for (const f of files) {
  let txt; try { txt = fs.readFileSync(f, 'utf8'); } catch { continue; }
  const rel = path.relative(root, f);
  const isSub = rel.includes('subagents') || path.basename(f).startsWith('agent-');
  const sessKey = rel.split(path.sep)[0] + ' | ' + (isSub ? 'subagent ' : '') + path.basename(f).slice(0, 14);
  for (const line of txt.split('\n')) {
    if (!line.includes('"usage"')) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    const msg = o.message;
    if (!msg || !msg.usage || o.type !== 'assistant' || msg.model === '<synthetic>') continue;
    if ((o.timestamp || '') < since) continue;
    const id = (msg.id || '') + '|' + (o.requestId || '');
    if (seen.has(id)) continue; seen.add(id);
    const u = msg.usage, cc = u.cache_creation || {};
    const cw1h = cc.ephemeral_1h_input_tokens || 0;
    const r = { input: u.input_tokens || 0, out: u.output_tokens || 0, cr: u.cache_read_input_tokens || 0, cw1h,
      cw5: cc.ephemeral_5m_input_tokens ?? Math.max(0, (u.cache_creation_input_tokens || 0) - cw1h) };
    const s = scale(msg.model || '');
    const parts = Object.fromEntries(Object.keys(W).map(k => [k, s * r[k] * W[k] / 1e6]));
    const cost = Object.values(parts).reduce((a, b) => a + b, 0);
    if (isSub) subCost += cost;
    for (const [bag, k] of [[byModel, msg.model || 'unknown'], [bySession, sessKey], [byDay, (o.timestamp || '').slice(0, 10)], [null, null]]) {
      const b = bag ? (bag[k] ||= blank()) : tot;
      b.msgs++; for (const x of Object.keys(W)) { b[x] += r[x]; b.c[x] += parts[x]; } b.cost += cost;
    }
  }
}

const M = n => (n / 1e6).toFixed(1) + 'M';
const pct = x => (100 * x / (tot.cost || 1)).toFixed(0) + '%';
const row = (k, b) => `${k.padEnd(60).slice(0, 60)} msgs=${String(b.msgs).padStart(6)} out=${M(b.out).padStart(7)} cacheRead=${M(b.cr).padStart(8)} cacheWrite=${M(b.cw5 + b.cw1h).padStart(7)} (1h ${M(b.cw1h)}) uncached=${M(b.input).padStart(6)} ~$${b.cost.toFixed(0).padStart(5)} ${pct(b.cost)}`;
console.log(`files=${files.length} since=${since}`);
console.log(row('TOTAL', tot));
console.log(`share of cost: output ${pct(tot.c.out)}, cache reads ${pct(tot.c.cr)}, cache writes 5m ${pct(tot.c.cw5)}, cache writes 1h ${pct(tot.c.cw1h)}, uncached input ${pct(tot.c.input)}; sub-agents ${pct(subCost)}`);
console.log('--- by model');
for (const [k, b] of Object.entries(byModel).sort((a, b) => b[1].cost - a[1].cost)) console.log(row(k, b));
console.log('--- by day');
for (const [k, b] of Object.entries(byDay).sort()) console.log(row(k, b));
console.log('--- top 15 sessions');
for (const [k, b] of Object.entries(bySession).sort((a, b) => b[1].cost - a[1].cost).slice(0, 15)) console.log(row(k, b));
