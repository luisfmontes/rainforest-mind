#!/usr/bin/env python3
"""advpl-graph v0.2 — multi-fonte: resolve U_*, namespaces TLPP e tabelas compartilhadas."""
import re, json, sys, os
from collections import defaultdict

files = sys.argv[1:-1]; OUT = sys.argv[-1]
os.makedirs(OUT, exist_ok=True)

FUNC_RE = re.compile(r'^\s*(user\s+function|static\s+function|function|wsmethod|method)\s+(\w+)', re.I)
NS_RE   = re.compile(r'^\s*namespace\s+([\w\.]+)', re.I | re.M)
USING_RE= re.compile(r'^\s*using\s+namespace\s+([\w\.]+)', re.I | re.M)
TBL_RE  = re.compile(r'RetSqlName\(\s*["\'](\w{3})["\']\s*\)|DbSelectArea\(\s*["\'](\w{3})["\']\s*\)|\b([A-Z]\w{2})->')
MV_RE   = re.compile(r'(?:SuperGetMV|GetMV|GetNewPar)\(\s*["\']([\w_]+)["\']', re.I)
EXEC_NAME = re.compile(r'MSExecAuto\(\s*\{\|\s*[\w,\s]*\|\s*(\w+)', re.I)
QUALIF_RE = re.compile(r'\b([\w]+(?:\.[\w]+)+)\.u_(\w+)\s*\(', re.I)
U_RE      = re.compile(r'\bU_(\w+)\s*\(', re.I)
CALL_RE   = re.compile(r'\b(\w+)\s*\(')
TBL_SKIP  = {"STR","VAL","LEN","IIF","MAX","MIN","ABS","POS","CHR","QRY","TMP","AUX","OBJ"}

sources = {}
for path in files:
    txt = open(path, encoding="utf-8", errors="replace").read()
    lines = txt.splitlines()
    name = os.path.basename(path)
    ns = NS_RE.search(txt); using = USING_RE.findall(txt)
    funcs = []
    for i, ln in enumerate(lines, 1):
        m = FUNC_RE.match(ln)
        if m:
            funcs.append({"name": m.group(2), "kind": re.sub(r'\s+',' ',m.group(1).lower()),
                          "line": i, "source": name})
    for idx, f in enumerate(funcs):
        f["end"] = funcs[idx+1]["line"]-1 if idx+1 < len(funcs) else len(lines)
        f["body"] = "\n".join(lines[f["line"]-1:f["end"]])
    sources[name] = {"ns": ns.group(1).lower() if ns else None, "using": [u.lower() for u in using],
                     "funcs": funcs, "lines": len(lines)}

# índice global de user functions: nome_uc -> (source, func)
uf_index = {}          # por nome simples
ns_index = {}          # (namespace, nome_uc) -> (source, func)
local_names = {}       # source -> {nome_uc: nome}
for src, s in sources.items():
    local_names[src] = {}
    for f in s["funcs"]:
        local_names[src][f["name"].upper()] = f["name"]
        if f["kind"] == "user function":
            uf_index.setdefault(f["name"].upper(), (src, f["name"]))
            if s["ns"]:
                ns_index[(s["ns"], f["name"].upper())] = (src, f["name"])

def nid(src, fn): return f"{src}::{fn}"

edges = []; tables = defaultdict(set); mvs = defaultdict(set); execautos = defaultdict(set)
unresolved = set()

for src, s in sources.items():
    visible_ns = ([s["ns"]] if s["ns"] else []) + s["using"]
    for f in s["funcs"]:
        me = nid(src, f["name"]); body = f["body"]
        # 1. chamadas qualificadas: ns.path.u_func(
        for m in QUALIF_RE.finditer(body):
            ns, fn = m.group(1).lower(), m.group(2).upper()
            tgt = ns_index.get((ns, fn))
            if tgt:
                edges.append({"from": me, "to": nid(*tgt), "type": "CALLS_CROSS_SOURCE", "via": "namespace", "tag": "EXTRACTED"})
            else:
                unresolved.add(f"{ns}.u_{m.group(2)}")
        # 2. chamadas U_: resolve no próprio fonte, depois namespaces visíveis, depois global
        for m in U_RE.finditer(body):
            fn = m.group(1).upper()
            tgt = None
            if fn in local_names[src] :
                tgt = (src, local_names[src][fn])
            else:
                for v in visible_ns:
                    if (v, fn) in ns_index: tgt = ns_index[(v, fn)]; break
                if not tgt and fn in uf_index: tgt = uf_index[fn]
            if tgt and tgt[0] != src:
                edges.append({"from": me, "to": nid(*tgt), "type": "CALLS_CROSS_SOURCE", "via": "U_", "tag": "EXTRACTED"})
            elif tgt:
                edges.append({"from": me, "to": nid(*tgt), "type": "CALLS", "tag": "EXTRACTED"})
            else:
                unresolved.add(f"U_{m.group(1)}")
        # 3. chamadas locais diretas
        for m in CALL_RE.finditer(body):
            cu = m.group(1).upper()
            if cu in local_names[src] and cu != f["name"].upper():
                edges.append({"from": me, "to": nid(src, local_names[src][cu]), "type": "CALLS", "tag": "EXTRACTED"})
        # 4. tabelas / MVs / execautos
        for m in TBL_RE.finditer(body):
            t = m.group(1) or m.group(2) or m.group(3)
            if t and re.match(r'^[A-Z]\w{2}$', t) and t not in TBL_SKIP: tables[t].add(me)
        for m in MV_RE.finditer(body): mvs[m.group(1).upper()].add(me)
        for m in EXEC_NAME.finditer(body): execautos[m.group(1).upper()].add(me)

seen=set(); edges=[e for e in edges if not (tuple(sorted(e.items())) in seen or seen.add(tuple(sorted(e.items()))))]
for t,fs in tables.items():
    for fn in fs: edges.append({"from": fn, "to": f"TABLE:{t}", "type": "READS_WRITES", "tag": "EXTRACTED"})

# tabelas-ponte: usadas por >1 fonte
bridge = {t: sorted({f.split("::")[0] for f in fs}) for t,fs in tables.items() if len({f.split("::")[0] for f in fs})>1}

cross = [e for e in edges if e["type"]=="CALLS_CROSS_SOURCE"]
graph = {"sources": {k: {"namespace": v["ns"], "lines": v["lines"], "functions": len(v["funcs"])} for k,v in sources.items()},
         "cross_source_calls": cross, "bridge_tables": bridge,
         "unresolved_external": sorted(unresolved),
         "edges": edges,
         "nodes": [{"id": nid(s,f["name"]), "kind": f["kind"], "line": f["line"], "end": f["end"]} for s in sources for f in sources[s]["funcs"]]}
json.dump(graph, open(f"{OUT}/graph.json","w",encoding="utf-8"), ensure_ascii=False, indent=1)

with open(f"{OUT}/INDEX.md","w",encoding="utf-8") as w:
    w.write("# Módulo Fechamento Financeiro — grafo multi-fonte\n\n## Fontes\n")
    for k,v in sources.items():
        w.write(f"- **{k}** — {v['lines']} linhas, {len(v['funcs'])} funções" + (f", namespace `{v['ns']}`" if v['ns'] else "") + "\n")
    w.write("\n## Vínculos entre fontes (EXTRACTED)\n")
    for e in cross:
        w.write(f"- `{e['from']}` → `{e['to']}` _(via {e['via']})_\n")
    w.write("\n## Tabelas-ponte (compartilhadas entre fontes)\n")
    for t, srcs in sorted(bridge.items()):
        w.write(f"- **{t}**: {', '.join(srcs)}\n")
    w.write("\n## Externos não resolvidos (fontes fora deste conjunto)\n")
    for u in sorted(unresolved): w.write(f"- `{u}`\n")
print(json.dumps({"cross_calls": len(cross), "bridge_tables": len(bridge), "unresolved": len(unresolved), "edges": len(edges)}, indent=1))
