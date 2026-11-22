// Per main session: context size per turn (percentiles), compactions, turns. Numbers only.
// Usage: node context-scan.mjs <sinceISO>
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const since = process.argv[2] || '1970-01-01';
const root = path.join(os.homedir(), '.claude', 'projects');
const out = [];
for (const proj of fs.readdirSync(root)) {
  const pdir = path.join(root, proj);
  let ents; try { ents = fs.readdirSync(pdir); } catch { continue; }
  for (const f of ents) {
    if (!f.endsWith('.jsonl')) continue;
    const txt = fs.readFileSync(path.join(pdir, f), 'utf8');
    const sizes = []; let compactions = 0; const seen = new Set(); let model = '';
    for (const line of txt.split('\n')) {
      if (line.includes('"compact_boundary"')) compactions++;
      if (!line.includes('"usage"')) continue;
      let o; try { o = JSON.parse(line); } catch { continue; }
      const m = o.message;
      if (!m || !m.usage || o.type !== 'assistant' || m.model === '<synthetic>') continue;
      if ((o.timestamp || '') < since) continue;
      const id = (m.id || '') + '|' + (o.requestId || '');
      if (seen.has(id)) continue; seen.add(id);
      const u = m.usage;
      sizes.push((u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0));
      model = m.model;
    }
    if (sizes.length < 40) continue;
    const s = [...sizes].sort((a, b) => a - b);
    const p = q => Math.round(s[Math.min(s.length - 1, Math.floor(q * s.length))] / 1000) + 'k';
    const over = n => sizes.filter(x => x > n).length;
    out.push({ key: proj.slice(0, 40) + ' ' + f.slice(0, 8), model, turns: sizes.length, p50: p(0.5), p90: p(0.9), max: p(0.999), compactions, over300: over(300000), over500: over(500000), sum: sizes.reduce((a, b) => a + b, 0) });
  }
}
out.sort((a, b) => b.sum - a.sum);
for (const r of out.slice(0, 8)) console.log(`${r.key.padEnd(50)} ${r.model.padEnd(18)} turns=${r.turns} p50=${r.p50} p90=${r.p90} max=${r.max} >300k=${r.over300} >500k=${r.over500} compactions=${r.compactions}`);
