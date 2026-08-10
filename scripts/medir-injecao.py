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
  python scripts/medir-injecao.py --entrega       # o que o hook emitiu vs. o que CHEGOU
  python scripts/medir-injecao.py <arquivo.jsonl>

Metodo: mudar a injecao -> abrir UMA sessao nova -> rodar isto. A diferenca
contra a medicao anterior e o efeito da mudanca, em token, de graca.

DOIS MODOS, E ELES RESPONDEM PERGUNTAS DIFERENTES
-------------------------------------------------
O modo padrao (acima) mede o TOTAL do prompt de abertura. Ele responde
"quanto custa", e nao responde "a regra chegou" — pior: em 2026-08-10
descobriu-se que ele PREMIA visualmente o modo de falha que deveria
denunciar, porque um payload cortado aparece como um total menor, que era
exatamente o objetivo declarado da condensacao. E o piso de ruido dele
(+-10,7k tokens entre sessoes consecutivas, com a injecao constante) e maior
que a mudanca tipica que se quer medir.

O modo --entrega le, para cada hook, os DOIS campos que o transcript guarda:
`stdout` (o que o hook escreveu) e `content` (o que foi entregue ao modelo).
Quando o harness passa do limite dele, grava o stdout num arquivo e injeta um
preview de ~2 KB — e o exit code continua 0, indistinguivel de sucesso. Foi
assim em 50 de 50 sessoes registradas do rainforest-mind, desde a primeira que
existe: as regras 4 a 17 nunca chegaram a sessao nenhuma. Este modo e a tabela
de 15 linhas que teria mostrado isso no primeiro dia.
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


def _varrer(no, achados: list) -> None:
    """Desce no JSON atras de qualquer dict que descreva a execucao de um hook.

    A posicao do registro no transcript nao e contrato — ela ja mudou entre
    versoes do Claude Code. O que identifica o registro e ter os dois campos
    que interessam, entao a busca e por FORMA, nao por caminho.
    """
    if isinstance(no, dict):
        if "hookEvent" in no and "stdout" in no:
            achados.append(no)
        for v in no.values():
            _varrer(v, achados)
    elif isinstance(no, list):
        for v in no:
            _varrer(v, achados)


def entregas(caminho: Path) -> list[dict]:
    """Por hook de SessionStart: o que foi escrito vs. o que foi entregue."""
    linhas: list[dict] = []
    vistos: set[tuple] = set()
    with caminho.open(encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            try:
                d = json.loads(linha)
            except json.JSONDecodeError:
                continue
            quando = d.get("timestamp") or "?"
            achados: list = []
            _varrer(d, achados)
            for h in achados:
                if not str(h.get("hookEvent", "")).startswith("SessionStart"):
                    continue
                emitido = len(h.get("stdout") or "")
                chegou = len(h.get("content") or "")
                # O harness anuncia o corte no proprio texto entregue. Sem esse
                # marcador, `chegou < emitido` ainda pode ser truncamento, entao
                # a comparacao de tamanho e o segundo sinal, nao o unico.
                marcado = "<persisted-output>" in (h.get("content") or "")
                chave = (h.get("command"), emitido, chegou)
                if chave in vistos:
                    continue
                vistos.add(chave)
                cmd = str(h.get("command") or h.get("hookName") or "?")
                # Basta o executavel/script para identificar quem emitiu.
                nome = cmd.replace("\\", "/").split("/")[-1].split('"')[0][:28]
                linhas.append({
                    "quando": quando, "hook": nome, "emitido": emitido,
                    "chegou": chegou, "exit": h.get("exitCode"),
                    "truncado": marcado or (0 < chegou < emitido),
                    "marcado": marcado, "arquivo": caminho.name,
                    "json": (h.get("stdout") or "").lstrip()[:1] == "{",
                })
    return linhas


def relatar_entrega(alvos: list[Path]) -> int:
    linhas = [m for c in alvos for m in entregas(c)]
    if not linhas:
        print("erro: nenhum registro de hook de SessionStart nos transcripts lidos.\n"
              "      Sessao sem hook, ou o transcript nao guarda o campo `stdout`.",
              file=sys.stderr)
        return 1

    linhas.sort(key=lambda m: (m["quando"], m["hook"]))
    print(f"{'quando':20s} {'hook':28s} {'emitiu':>8s} {'chegou':>8s} {'%':>5s}  estado")
    truncados = 0
    for m in linhas:
        q = m["quando"][:19].replace("T", " ")
        if m["truncado"]:
            truncados += 1
            pct = (100.0 * m["chegou"] / m["emitido"]) if m["emitido"] else 0.0
            chegou, pcts, estado = f"{m['chegou']:,d}", f"{pct:.0f}%", "TRUNCADO"
        else:
            # `content` vazio nao significa "chegou zero": significa que o harness
            # nao registrou corte nenhum e entregou por outro caminho. Imprimir 0
            # aqui seria inventar uma medicao — o campo e desconhecido, e diz-se isso.
            chegou, pcts, estado = "-", "-", "sem corte"
        print(f"{q:20s} {m['hook']:28s} {m['emitido']:>8,d} {chegou:>8s} "
              f"{pcts:>5s}  {estado}")

    print(f"\n{len(linhas)} entrega(s) de hook | truncadas: {truncados} | "
          f"sem corte registrado: {len(linhas) - truncados}")
    print("\n'chegou' e '%' so existem para o hook truncado: e o unico caso em que o\n"
          "transcript guarda os dois numeros. 'sem corte' = o harness nao registrou\n"
          "truncamento; nao e prova de que o texto todo virou contexto, e por isso\n"
          "nao se imprime 100% ali.")

    # So hook de TEXTO CRU serve de referencia para o orcamento. Hook que emite
    # JSON (hookSpecificOutput.additionalContext) entrega so o campo de dentro:
    # o claude-mem escreve 22 KB de stdout e entrega ~7 KB, e nao e truncado por
    # isso. Contar o stdout dele como "passou 22 KB" daria um teto falso e generoso
    # — o erro exato que este modo existe para nao cometer.
    cru = [m for m in linhas if not m["json"]]
    maior_passe = max((m["emitido"] for m in cru if not m["truncado"]), default=0)
    menor_corte = min((m["emitido"] for m in cru if m["truncado"]), default=0)
    if menor_corte and maior_passe:
        print(f"\nFaixa observada do limite (so hooks de texto cru): passou {maior_passe:,d} B,\n"
              f"cortou a partir de {menor_corte:,d} B. O limite exato do harness nao esta\n"
              "documentado — dimensione com folga abaixo do maior passe, nunca perto\n"
              "do menor corte. Hooks que emitem JSON ficam fora desta conta.")
    if truncados:
        print("\nTRUNCADO = o modelo NAO leu o que o hook escreveu. O exit code do hook\n"
              "continua 0 nesses casos: o sucesso do processo nao diz nada sobre a\n"
              "entrega. Regra que ficou fora do pedaco entregue nao esta valendo —\n"
              "trate como regra bloqueada pelo ambiente (regra 14).")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="medir-injecao.py")
    ap.add_argument("arquivo", nargs="?")
    ap.add_argument("--ultimas", type=int, default=1)
    ap.add_argument("--projeto", default=".")
    ap.add_argument("--entrega", action="store_true",
                    help="mede o que CHEGOU ao modelo por hook, nao o total da abertura")
    a = ap.parse_args()

    if a.arquivo:
        alvos = [Path(a.arquivo)]
    else:
        alvos = transcripts_do_projeto(Path(a.projeto))[: a.ultimas]
    if not alvos:
        print(f"erro: nenhum transcript em {RAIZ_TRANSCRIPTS}", file=sys.stderr)
        return 1

    if a.entrega:
        return relatar_entrega(alvos)

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
