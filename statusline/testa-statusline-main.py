# -*- coding: utf-8 -*-
"""Bateria de ponta a ponta do `main()` da statusline.

Existe por um defeito real: em 1.8.1 o `main()` chamou
`segmento_escada_intensidade()` sem o `cwd` que a funcao exige, estourou
TypeError e a barra SUMIU dos dois perfis de uma vez — exit 1 faz o harness
engolir a linha inteira, nao so o segmento quebrado.

As baterias por segmento nao pegariam isso: cada uma chama a sua funcao
direto, com os argumentos certos. O que ninguem exercitava era a chamada que
o harness faz — processo de verdade, JSON de verdade por stdin, codigo de
saida de verdade.

Falsificavel: cada caso diz o exit esperado (0) e FALHA se o processo sair
diferente ou sujar o stderr com traceback.
"""
import json
import os
import subprocess
import sys

FONTE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "statusline.py"
)

# Cada caso e um payload plausivel do harness. O terceiro e o mais cru de
# todos de proposito: o harness ja mandou objeto vazio, e a barra tem de
# sobreviver a isso sem argumento nenhum para se apoiar.
CASOS = [
    (
        u"payload completo",
        {
            "session_id": "00000000-0000-0000-0000-000000000000",
            "cwd": os.getcwd(),
            "workspace": {"current_dir": os.getcwd()},
            "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
            "transcript_path": "",
            "context_window": {"used_percentage": 12},
            "rate_limits": {"five_hour": {"used_percentage": 30}},
        },
    ),
    (
        u"sem cwd (harness antigo)",
        {"model": {"display_name": "Opus 5"}},
    ),
    (
        u"objeto vazio",
        {},
    ),
]

falhas = 0
for nome, payload in CASOS:
    proc = subprocess.Popen(
        [sys.executable, FONTE],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    saida, erro = proc.communicate(json.dumps(payload).encode("utf-8"))
    erro = erro.decode("utf-8", "replace")
    if proc.returncode != 0:
        falhas += 1
        print(u"FALHA [%s]: exit %d, esperava 0" % (nome, proc.returncode))
        print(erro.strip())
    elif "Traceback" in erro:
        falhas += 1
        print(u"FALHA [%s]: exit 0 mas traceback no stderr" % nome)
        print(erro.strip())
    else:
        print(u"ok [%s]" % nome)

if falhas:
    print(u"\nFALHA: %d de %d casos do main() reprovaram" % (falhas, len(CASOS)))
    sys.exit(1)

print(u"\nos %d casos do main() passaram" % len(CASOS))
