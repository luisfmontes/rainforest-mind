#!/usr/bin/env python3
r"""Token REAL do prompt de abertura, lido do transcript da sessao.

O problema que isto resolve: medir o custo da skill em CARACTERE e proxy,
e contar token de verdade exigia o endpoint count_tokens, que e gratuito
mas so responde com chave de API — e o Console exige compra antes de emitir
uma (2026-08-09). Ficamos uma sessao inteira decidindo no escuro.

A saida estava no proprio Claude Code: cada requisicao gravada no transcript
traz o `usage` devolvido pela API, com o tokenizador de verdade. O prompt de
abertura de uma sessao e:

    input_tokens + cache_read_input_tokens + cache_creation_input_tokens

Isso inclui TUDO (prompt do Claude Code, tools, CLAUDE.md, memoria, e a
injecao do hook), entao o numero absoluto nao isola a skill. O que isola e a
DIFERENCA entre duas sessoes em que so a injecao mudou — que e exatamente o
experimento de PT vs EN e de qualquer condensacao futura.

Uso:
  python scripts/medir-injecao.py                 # sessao mais recente
  python scripts/medir-injecao.py --ultimas 5     # compara as ultimas 5
  python scripts/medir-injecao.py <arquivo.jsonl>

Metodo: mudar a injecao -> abrir UMA sessao nova -> rodar isto. A diferenca
contra a medicao anterior e o efeito da mudanca, em token, de graca.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

RAIZ_TRANSCRIPTS = Path(os.environ.get("CLAUDE_CONFIG_DIR")
                        or Path(os.path.expanduser("~")) / ".claude") / "projects"


def transcripts_do_projeto(projeto: Path) -> list[Path]:
    # O Claude Code troca separadores por hifen no nome da pasta.
    slug = str(projeto.resolve()).replace(":", "-").replace("\\", "-").replace("/", "-")
    pasta = RAIZ_TRANSCRIPTS / slug
    if not pasta.is_dir():
        return []
    return sorted(pasta.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)


def abertura(caminho: Path) -> dict | None:
    """Primeira requisicao com usage: o prompt de abertura da sessao."""
    with caminho.open(encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            try:
                d = json.loads(linha)
            except json.JSONDecodeError:
                continue
            u = (d.get("message") or {}).get("usage") or d.get("usage")
            if not isinstance(u, dict) or u.get("input_tokens") is None:
                continue
            total = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) \
                + (u.get("cache_creation_input_tokens") or 0)
            return {"total": total, "quando": d.get("timestamp") or "?",
                    "arquivo": caminho.name}
    return None


def main() -> int:
    ap = argparse.ArgumentParser(prog="medir-injecao.py")
    ap.add_argument("arquivo", nargs="?")
    ap.add_argument("--ultimas", type=int, default=1)
    ap.add_argument("--projeto", default=".")
    a = ap.parse_args()

    if a.arquivo:
        alvos = [Path(a.arquivo)]
    else:
        alvos = transcripts_do_projeto(Path(a.projeto))[: a.ultimas]
    if not alvos:
        print(f"erro: nenhum transcript em {RAIZ_TRANSCRIPTS}", file=sys.stderr)
        return 1

    linhas = [m for c in alvos if (m := abertura(c))]
    if not linhas:
        print("erro: nenhum transcript com usage — sessao vazia?", file=sys.stderr)
        return 1

    linhas.sort(key=lambda m: m["quando"])
    print(f"{'quando':20s} {'tokens do prompt de abertura':>30s}   sessao")
    anterior = None
    for m in linhas:
        q = m["quando"][:19].replace("T", " ")
        delta = f"  ({m['total']-anterior:+d})" if anterior is not None else ""
        print(f"{q:20s} {m['total']:>30,d}{delta}   {m['arquivo'][:8]}")
        anterior = m["total"]
    if len(linhas) > 1:
        print("\nA coluna entre parenteses e o que interessa: so vale como medida da"
              "\ninjecao se NADA MAIS mudou entre as duas sessoes (mesmas tools,"
              "\nmesmo CLAUDE.md, mesmos MCPs). Na duvida, nao conclua.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
