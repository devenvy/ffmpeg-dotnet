#!/usr/bin/env python3
"""Summarise audit-*.jsonl into a defect matrix."""
import json, sys, collections
from pathlib import Path

rows = []
for f in sorted(Path(sys.argv[1] if len(sys.argv) > 1 else '.audit').glob('audit-*.jsonl')):
    for line in f.read_text().splitlines():
        if line.strip():
            rows.append(json.loads(line))

by_kind = collections.defaultdict(list)
for r in rows:
    for i in r['issues']:
        by_kind[i['kind']].append((r['tag'], r['artifact'], i))

print(f"{len(rows)} artifacts audited\n")
print("=" * 78)
for kind, hits in sorted(by_kind.items(), key=lambda kv: -len(kv[1])):
    arts = sorted({a for _, a, _ in hits})
    plats = sorted({a.rsplit('-', 1)[0] for a in arts})
    cells = sorted({a.rsplit('-', 1)[1] for a in arts})
    print(f"\n{kind}   ({len(hits)} occurrences, {len(arts)} artifacts)")
    print(f"  platforms: {', '.join(plats)}")
    print(f"  cells:     {', '.join(cells)}")
    seen = set()
    for _, a, i in hits:
        d = json.dumps(i['detail']) if not isinstance(i['detail'], str) else i['detail']
        key = (d[:80], i['file'].split('/')[-1][:24])
        if key in seen:
            continue
        seen.add(key)
        if len(seen) <= 3:
            print(f"    e.g. {i['file'] or '-'}: {d[:110]}")

print("\n" + "=" * 78)
print("\nPER-PLATFORM (union across cells):")
per = collections.defaultdict(set)
dup = {}
for r in rows:
    p = r['artifact'].rsplit('-', 1)[0]
    for i in r['issues']:
        per[p].add(i['kind'])
    if r.get('duplicated_mb'):
        dup[p] = max(dup.get(p, 0), r['duplicated_mb'])
for p in sorted(per):
    d = f"  [{dup[p]}MB dup]" if p in dup else ""
    print(f"  {p:<20} {', '.join(sorted(per[p])) or 'clean'}{d}")
for r in rows:
    p = r['artifact'].rsplit('-', 1)[0]
    if p not in per:
        per[p] = set()
clean = [p for p in sorted(per) if not per[p]]
if clean:
    print(f"\n  CLEAN: {', '.join(clean)}")
