# -*- coding: utf-8 -*-
"""Bateria do segmento de prazo da statusline. Falsificavel: cada caso diz o
rotulo esperado, e o teste FALHA se a implementacao devolver outra coisa."""
import datetime
import io
import os
import re
import sys
import tempfile

FONTE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "statusline.py"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# O `__file__` vai junto de proposito: o fonte resolve os vizinhos dele (o
# statusline-jornada.sh) por caminho relativo a si mesmo, e sem esta linha o
# `exec` roda num namespace sem `__file__` e estoura NameError na importacao.
# A bateria carrega o modulo A PARTIR de FONTE — mentir sobre isso faria o
# teste exercitar um modulo que nao e o que o harness carrega.
ns = {"__name__": "bateria", "__file__": FONTE}
exec(compile(open(FONTE, encoding="utf-8").read(), FONTE, "exec"), ns)

HOJE = datetime.date.today()


def d(delta):
    return (HOJE + datetime.timedelta(days=delta)).isoformat()


def rotulo(corpo):
    caminho = os.path.join(tempfile.gettempdir(), "foco-teste-prazo.md")
    with io.open(caminho, "w", encoding="utf-8") as fh:
        fh.write(corpo)
    ns["FOCO"] = caminho
    return ANSI.sub("", ns["segmento_prazo"]())


CASOS = [
    # (nome, corpo do FOCO.md, rotulo esperado)
    (
        "carimbo de avanco de hoje NAO e prazo",
        u"## Ativo\n- %s: **a Task 1 rodou** (o Luis executou o updater)\n" % d(0),
        u"",
    ),
    (
        "prazo real a 7 dias aparece como 7d",
        u"## Ativo\nPrioridade 00; prazo final %s (vespera das ferias).\n" % d(7),
        u"prazo 7d",
    ),
    (
        "carimbo de hoje + prazo real: vence o prazo real",
        u"## Ativo\n- %s: a Task 1 rodou\nprazo final %s (vespera das ferias).\n"
        % (d(0), d(7)),
        u"prazo 7d",
    ),
    (
        "compromisso que vence HOJE ainda acende vermelho",
        u"## Compromissos com prazo\n- **Telas entregues ate %s (terca)**\n" % d(0),
        u"prazo hoje",
    ),
    (
        "data de contexto sem marcador nao conta",
        u"## Ativo\nConversa com o gestor marcada, ele citou %s de passagem.\n" % d(1),
        u"",
    ),
    (
        "reuniao de marco conta como prazo",
        u"## Ativo\n- Projetos 2 - reuniao %s: funcionalidades ponta a ponta.\n"
        % (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
        u"prazo 2d",
    ),
    (
        "compromisso ja cumprido (check) nao acende",
        u"## Compromissos com prazo\n- Requisitos ate %s. **CUMPRIDO** \u2705\n" % d(1),
        u"",
    ),
    (
        "carimbo com prazo DENTRO da linha ainda conta",
        u"## Ativo\n- %s: fechado com o gestor, prazo do piloto e %s\n" % (d(0), d(3)),
        u"prazo 3d",
    ),
    (
        "data de contexto depois do compromisso nao antecipa o alarme",
        u"## Ativo\n- Entrega ate %s, conforme combinado na reuniao de %s\n"
        % (
            (HOJE + datetime.timedelta(days=10)).strftime("%d/%m"),
            (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
        ),
        u"prazo 10d",
    ),
    (
        "duas datas com marcador: a menor e o prazo",
        u"## Ativo\n- **Projetos 1 — reuniao %s, entregar ate %s (sex)**\n"
        % (
            (HOJE + datetime.timedelta(days=5)).strftime("%d/%m"),
            (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
        ),
        u"prazo 2d",
    ),
    (
        "clausula de contexto intercalada nao come o prazo",
        u"## Ativo\n- Prazo final, segundo o cliente, e %s.\n"
        % (HOJE + datetime.timedelta(days=5)).strftime("%d/%m"),
        u"prazo 5d",
    ),
    (
        "clausula intercalada com data de contexto dentro",
        u"## Ativo\n- Prazo final, conforme combinado na reuniao de %s, e %s.\n"
        % (
            (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
            (HOJE + datetime.timedelta(days=5)).strftime("%d/%m"),
        ),
        u"prazo 5d",
    ),
    (
        "conectivo estreito: conforme + reuniao",
        u"## Ativo\n- Entrega ate %s, conforme reuniao de %s.\n"
        % (
            (HOJE + datetime.timedelta(days=10)).strftime("%d/%m"),
            (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
        ),
        u"prazo 10d",
    ),
    (
        "conectivo novo: de acordo com",
        u"## Ativo\n- Entrega ate %s, de acordo com o alinhado em %s.\n"
        % (
            (HOJE + datetime.timedelta(days=10)).strftime("%d/%m"),
            (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
        ),
        u"prazo 10d",
    ),
    (
        "conectivo novo: definido",
        u"## Ativo\n- Entrega ate %s, definido na reuniao de %s.\n"
        % (
            (HOJE + datetime.timedelta(days=10)).strftime("%d/%m"),
            (HOJE + datetime.timedelta(days=2)).strftime("%d/%m"),
        ),
        u"prazo 10d",
    ),
    (
        "ordem inversa: data antes do marcador",
        u"## Ativo\n- %s e o prazo final de entrega do modulo.\n"
        % (HOJE + datetime.timedelta(days=10)).strftime("%d/%m"),
        u"prazo 10d",
    ),
]

falhas = 0
for nome, corpo, esperado in CASOS:
    obtido = rotulo(corpo)
    ok = obtido == esperado
    if not ok:
        falhas += 1
    print(u"%s %-52s esperado=%-11r obtido=%r"
          % (u"ok  " if ok else u"FALHA", nome, esperado, obtido))

print("")
print(u"%d/%d casos passaram" % (len(CASOS) - falhas, len(CASOS)))
sys.exit(1 if falhas else 0)
