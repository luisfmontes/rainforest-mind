"""scripts/jornada.py — mede a jornada efetiva pelos intervalos entre mensagens do usuario.

Uso:
    python scripts/jornada.py                          # hoje, todas as janelas
    python scripts/jornada.py --dia 2026-08-09
    python scripts/jornada.py --transcript <arquivo.jsonl>
    python scripts/jornada.py --corte 90               # outro limiar de lacuna
    python scripts/jornada.py --sem-descarte           # MUTACAO: nao descarta lacuna

POR QUE ESTE SCRIPT EXISTE
--------------------------
A regra 8 vinha inferindo jornada de CARIMBO DE COMMIT. Carimbo marca o instante em
que o codigo foi salvo, nunca a duracao do trabalho: uma lista de commits e evidencia
de atividade em pontos, jamais no intervalo entre eles. Em 2026-08-09 isso produziu
"8 horas seguidas" a partir de um intervalo que continha 5h24 de sono no meio.

O sinal certo e o intervalo entre mensagens HUMANAS consecutivas: cada prompt do usuario
prova que ele estava ali naquele instante. Lacuna acima do corte e pausa, nao trabalho,
e sai da conta.

DUAS ARMADILHAS, as duas medidas neste repo em 2026-08-09
----------------------------------------------------------
1. `type == "user"` NAO significa mensagem humana. No transcript 5dd841be sao 377
   entradas "user" e apenas 42 sao do usuario — as outras 327 sao `toolUseResult`, mais
   6 `isMeta` e 2 `isCompactSummary`. Contar as 377 mede o ritmo das FERRAMENTAS e da
   um numero sem relacao com jornada. O filtro e obrigatorio.

2. Os carimbos do transcript sao UTC (terminam em Z). A regra 8 decide por relogio
   LOCAL — ler UTC como local adianta 3h no fuso de Brasilia. A conversao acontece
   aqui, uma vez, e o resto do script so ve hora local.

CALIBRACAO DO CORTE (medida, nao arbitrada)
-------------------------------------------
2.352 lacunas em 165 transcripts reais desta maquina:

    p50 = 5,0 min      corte  60 min -> descarta 4,5% das lacunas
    p90 = 23,8 min     corte  75 min -> descarta 3,7%   <- default
    p95 = 49,8 min     corte  90 min -> descarta 3,0%
    p99 = 265,2 min

95% das lacunas ficam abaixo de 50 min: e o ritmo normal de trabalho. Corte mais
baixo desinfla a jornada (descarta pausa curta legitima); mais alto infla (engole
pausa e vira aviso falso). Entre os dois erros, inflar e o pior: aviso falso
ensina a ignorar o aviso.

REVISADO EM 2026-08-11: era 75, virou 55.
O 75 foi escolhido por um criterio so - ficar acima do ritmo de trabalho (p95) e
abaixo de cochilo. O ponto cego: ALMOCO. Uma hora de mesa e a pausa mais comum
que existe, cai bem no meio do vao entre p95 e 75, e entrava na conta como
trabalho. Medido no dia real do usuario, com ele confirmando o intervalo:

    corte 75 -> 9h43, "nenhuma lacuna acima de 75 min"
    corte 55 -> 7h41, duas lacunas de ~1h (07:53->08:53 e 11:59->13:01)

Duas horas de pausa contadas como trabalho, 26% a mais, e o aviso da regra 8
disparando com quase duas horas de antecedencia. 55 continua acima do p95 de
49,8 min - o ritmo normal de trabalho nao e tocado - e fica abaixo de um almoco.

A licao vale alem deste numero: limiar calibrado contra UM cenario (sono) nao
serve para outro (pausa) so porque a unidade e a mesma. Todo limiar precisa ser
confrontado com o caso real que vai encontrar, e quem tem esse caso e o usuario.
"""
import argparse
import glob
import json
import os
import sys
from datetime import datetime, timedelta

CORTE_PADRAO_MIN = 55


def transcripts_disponiveis():
    base = os.path.expandvars(r"%USERPROFILE%")
    achados = []
    for config_dir in (".claude-personal", ".claude"):
        achados += glob.glob(os.path.join(base, config_dir, "projects", "*", "*.jsonl"))
    return achados


def mensagens_humanas(caminho):
    """Carimbos das mensagens do usuario, em hora LOCAL, ordenados.

    Descarta retorno de ferramenta (`toolUseResult`), meta e resumo de compactacao —
    os tres chegam como type "user" e nao provam presenca humana nenhuma.
    """
    fora = datetime.now().astimezone().tzinfo
    carimbos = []
    try:
        with open(caminho, encoding="utf-8", errors="ignore") as f:
            for linha in f:
                try:
                    d = json.loads(linha)
                except json.JSONDecodeError:
                    continue
                if d.get("type") != "user":
                    continue
                if "toolUseResult" in d or d.get("isMeta") or d.get("isCompactSummary"):
                    continue
                ts = d.get("timestamp")
                if not ts:
                    continue
                utc = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                carimbos.append((utc.astimezone(fora), caminho))
    except OSError:
        return []
    return carimbos


def hhmm(minutos):
    h, m = divmod(int(round(minutos)), 60)
    return f"{h}h{m:02d}" if h else f"{m} min"


def medir(carimbos, corte_min, descartar=True):
    """Devolve (efetiva_min, bruto_min, lacunas_descartadas, primeiro, ultimo)."""
    if len(carimbos) < 2:
        return 0.0, 0.0, [], (carimbos[0][0] if carimbos else None), None

    momentos = [c[0] for c in carimbos]
    efetiva = 0.0
    descartadas = []
    for a, b in zip(momentos, momentos[1:]):
        gap = (b - a).total_seconds() / 60
        if descartar and gap > corte_min:
            descartadas.append((a, b, gap))
        else:
            efetiva += gap
    bruto = (momentos[-1] - momentos[0]).total_seconds() / 60
    return efetiva, bruto, descartadas, momentos[0], momentos[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dia", help="AAAA-MM-DD (padrao: hoje, hora local)")
    ap.add_argument("--transcript", help="mede um transcript especifico, ignorando --dia")
    ap.add_argument("--corte", type=float, default=CORTE_PADRAO_MIN,
                    help=f"lacuna em minutos acima da qual e pausa (padrao: {CORTE_PADRAO_MIN})")
    ap.add_argument("--sem-descarte", action="store_true",
                    help="MUTACAO: nao descarta lacuna nenhuma. So para provar o teste — "
                         "o numero deve saltar para o intervalo bruto de ponta a ponta")
    ap.add_argument("--json", action="store_true", help="saida em JSON, para consumo por hook")
    args = ap.parse_args()

    if args.transcript:
        carimbos = mensagens_humanas(args.transcript)
        escopo = os.path.basename(args.transcript)
    else:
        dia = args.dia or datetime.now().astimezone().strftime("%Y-%m-%d")
        carimbos = []
        for t in transcripts_disponiveis():
            carimbos += [c for c in mensagens_humanas(t) if c[0].strftime("%Y-%m-%d") == dia]
        escopo = f"dia {dia}, todas as janelas"

    carimbos.sort(key=lambda c: c[0])

    if not carimbos:
        saida = {"escopo": escopo, "mensagens": 0, "erro": "nenhuma mensagem humana encontrada"}
        print(json.dumps(saida) if args.json else
              f"{escopo}: nenhuma mensagem humana encontrada.\n"
              "Sem medicao, a regra 8 PERGUNTA — nunca afirma jornada por outro sinal.")
        return 2

    efetiva, bruto, descartadas, primeiro, ultimo = medir(
        carimbos, args.corte, descartar=not args.sem_descarte)

    if args.json:
        print(json.dumps({
            "escopo": escopo,
            "mensagens": len(carimbos),
            "efetiva_min": round(efetiva, 1),
            "bruto_min": round(bruto, 1),
            "primeiro": primeiro.isoformat(),
            "ultimo": ultimo.isoformat(),
            "corte_min": args.corte,
            "descartadas": [{"de": a.isoformat(), "ate": b.isoformat(), "min": round(g, 1)}
                            for a, b, g in descartadas],
        }, ensure_ascii=False))
        return 0

    print(f"escopo ................. {escopo}")
    print(f"mensagens do usuario ...... {len(carimbos)}")
    print(f"primeiro sinal humano .. {primeiro.strftime('%H:%M')} (local)")
    print(f"ultimo sinal humano .... {ultimo.strftime('%H:%M')} (local)")
    print(f"intervalo bruto ........ {hhmm(bruto)}  <- ponta a ponta, NAO e jornada")
    if args.sem_descarte:
        print(f"JORNADA (SEM DESCARTE) . {hhmm(efetiva)}  <- MUTACAO ativa, numero invalido")
    else:
        print(f"JORNADA EFETIVA ........ {hhmm(efetiva)}")
    if descartadas:
        print(f"\nlacunas descartadas (> {int(args.corte)} min): {len(descartadas)}")
        for a, b, g in descartadas:
            print(f"  {a.strftime('%H:%M')} -> {b.strftime('%H:%M')}   {hhmm(g)}")
    elif not args.sem_descarte:
        print(f"\nnenhuma lacuna acima de {int(args.corte)} min.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
