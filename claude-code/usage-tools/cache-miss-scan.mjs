// Attributes cache-write tokens to their likely cause, using only usage numbers and timestamps.
// Usage: node cache-miss-scan.mjs <sinceISO>
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const since = process.argv[2] || '1970-01-01';
const root = path.join(os.homedir(), '.claude', 'projects');
const files = [];
(function walk(d) {
  let ents; try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
  for (const e of ents) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.jsonl')) files.push(p); }
})(root);

const buckets = { main: {}, sub: {} };
const add = (kind, cause, n) => { buckets[kind][cause] = (buckets[kind][cause] || 0) + n; };
const gapHist = { sub: { '<1m': 0, '1-5m': 0, '5-60m': 0, '>60m': 0 }, main: { '<1m': 0, '1-5m': 0, '5-60m': 0, '>60m': 0 } };
const agentTypes = {};
let bigToolResults = { sub: 0, main: 0 };

for (const f of files) {
  const rel = path.relative(root, f);
  const kind = rel.includes('subagents') || path.basename(f).startsWith('agent-') ? 'sub' : 'main';
  let txt; try { txt = fs.readFileSync(f, 'utf8'); } catch { continue; }
  // agent type from sibling meta file, if any
  if (kind === 'sub') {
    const meta = f.replace(/\.jsonl$/, '.meta.json');
    try { const m = JSON.parse(fs.readFileSync(meta, 'utf8')); const t = m.agentType || m.subagent_type || m.type || 'unknown'; agentTypes[t] = (agentTypes[t] || 0) + 1; } catch { agentTypes['(no meta)'] = (agentTypes['(no meta)'] || 0) + 1; }
  }
  const seen = new Set();
  let prevTs = null, first = true;
  for (const line of txt.split('\n')) {
    if (!line.includes('"usage"')) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    const msg = o.message;
    if (!msg || !msg.usage || o.type !== 'assistant' || msg.model === '<synthetic>') continue;
    if ((o.timestamp || '') < since) { prevTs = Date.parse(o.timestamp); first = false; continue; }
    const id = (msg.id || '') + '|' + (o.requestId || '');
    if (seen.has(id)) continue; seen.add(id);
    const u = msg.usage;
    const cw = u.cache_creation_input_tokens || 0;
    const cr = u.cache_read_input_tokens || 0;
    const ts = Date.parse(o.timestamp);
    const gapMin = prevTs ? (ts - prevTs) / 60000 : null;
    if (gapMin != null) gapHist[kind][gapMin < 1 ? '<1m' : gapMin < 5 ? '1-5m' : gapMin < 60 ? '5-60m' : '>60m']++;
    let cause;
    if (first) cause = '1 session/agent start';
    else if (cw > 5000 && cw > cr) cause = gapMin != null && gapMin >= 60 ? '3 full re-write after >60m pause' : gapMin != null && gapMin >= 5 ? '2 full re-write after 5-60m pause' : '4 full re-write, no pause (cache broken / compaction / model or tool change)';
    else cause = cw > 20000 ? '5 big new content (large tool output/file read)' : '6 normal small increment';
    if (cause.startsWith('5')) bigToolResults[kind]++;
    add(kind, cause, cw);
    prevTs = ts; first = false;
  }
}
const M = n => (n / 1e6).toFixed(1) + 'M';
for (const kind of ['main', 'sub']) {
  const tot = Object.values(buckets[kind]).reduce((a, b) => a + b, 0);
  console.log(`--- ${kind === 'main' ? 'main sessions' : 'subagents'}: cache writes ${M(tot)}`);
  for (const [k, v] of Object.entries(buckets[kind]).sort()) console.log(`  ${k.padEnd(75)} ${M(v).padStart(7)}  ${(100 * v / (tot || 1)).toFixed(0)}%`);
  console.log('  gaps between turns:', JSON.stringify(gapHist[kind]), ' turns with >20k new tokens:', bigToolResults[kind]);
}
console.log('subagent types:', JSON.stringify(agentTypes));
