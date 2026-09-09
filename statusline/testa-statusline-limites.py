# -*- coding: utf-8 -*-
"""Bateria do segmento de limites (5h/7d) da statusline: percentual usado e
tempo ate o reset. Falsificavel: cada caso diz o texto esperado, e o teste
FALHA se a implementacao devolver outra coisa.

O `resets_at` vem do harness em epoch de SEGUNDOS (doc do status line). Os casos
fixam `agora` de proposito: a bateria nao pode depender do relogio da maquina."""
import io
import json
import os
import re
import subprocess
import sys

FONTE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "statusline.py"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# `__file__` vai junto: o fonte resolve os vizinhos dele por caminho relativo a
# si mesmo (ver testa-statusline-prazo.py).
ns = {"__name__": "bateria", "__file__": FONTE}
exec(compile(io.open(FONTE, encoding="utf-8").read(), FONTE, "exec"), ns)

AGORA = 1_800_000_000  # epoch fixo; so a diferenca importa
H = 3600
D = 86400


def texto(limites):
    return ANSI.sub("", ns["segmento_limites"](limites, agora=AGORA))


CASOS = [
    # (nome, rate_limits, texto esperado)
    ("5h com 2h10 pela frente",
     {"five_hour": {"used_percentage": 23.4, "resets_at": AGORA + 2 * H + 10 * 60}},
     "5h 23% ↻2h10"),
    ("7d com 3 dias e 4 horas",
     {"seven_day": {"used_percentage": 41.2, "resets_at": AGORA + 3 * D + 4 * H}},
     "7d 41% ↻3d4h"),
    ("as duas janelas, na ordem 5h depois 7d",
     {"seven_day": {"used_percentage": 41.2, "resets_at": AGORA + 3 * D + 4 * H},
      "five_hour": {"used_percentage": 23.4, "resets_at": AGORA + 2 * H + 10 * 60}},
     "5h 23% ↻2h10 7d 41% ↻3d4h"),
    ("minutos com zero a esquerda",
     {"five_hour": {"used_percentage": 50, "resets_at": AGORA + 4 * H + 5 * 60}},
     "5h 50% ↻4h05"),
    ("menos de uma hora",
     {"five_hour": {"used_percentage": 90, "resets_at": AGORA + 12 * 60}},
     "5h 90% ↻0h12"),
    ("exatamente um dia vira formato de dias",
     {"seven_day": {"used_percentage": 10, "resets_at": AGORA + D}},
     "7d 10% ↻1d0h"),
    ("resets_at ausente: so o percentual",
     {"five_hour": {"used_percentage": 23.4}},
     "5h 23%"),
    ("resets_at no passado: so o percentual",
     {"five_hour": {"used_percentage": 23.4, "resets_at": AGORA - 60}},
     "5h 23%"),
    ("resets_at string: so o percentual, sem excecao",
     {"five_hour": {"used_percentage": 23.4, "resets_at": "amanha"}},
     "5h 23%"),
    ("resets_at booleano nao e numero",
     {"five_hour": {"used_percentage": 23.4, "resets_at": True}},
     "5h 23%"),
    ("resets_at NaN e float e nao pode estourar",
     {"five_hour": {"used_percentage": 23.4, "resets_at": float("nan")}},
     "5h 23%"),
    ("resets_at Infinity idem",
     {"five_hour": {"used_percentage": 23.4, "resets_at": float("inf")}},
     "5h 23%"),
    ("resets_at gigante nao estoura",
     {"five_hour": {"used_percentage": 23.4, "resets_at": 1e300}},
     "5h 23% ↻" + str(int(1e300 - AGORA) // D) + "d" + str((int(1e300 - AGORA) % D) // H) + "h"),
    ("percentual NaN nao aparece",
     {"five_hour": {"used_percentage": float("nan"), "resets_at": AGORA + H}},
     ""),
    ("janela sem percentual nao aparece",
     {"five_hour": {"resets_at": AGORA + H}},
     ""),
    ("spend_limit e ignorado",
     {"spend_limit": {"used_percentage": 62.8, "resets_at": AGORA + 10 * D}},
     ""),
    ("rate_limits ausente",
     None,
     ""),
    ("janela que nao e objeto",
     {"five_hour": 23.4},
     ""),
]

falhas = 0
for nome, limites, esperado in CASOS:
    try:
        obtido = texto(limites)
    except Exception as exc:  # a barra nunca pode estourar
        obtido = "EXCECAO: %r" % (exc,)
    if obtido == esperado:
        print("  ok    %s" % nome)
    else:
        falhas += 1
        print("  FALHA %s: esperava %r, veio %r" % (nome, esperado, obtido))

# Ponta a ponta: o JSON do harness no stdin, como o Claude Code manda, chega ao
# mesmo texto pelo `main()`. Aqui `agora` e o relogio real, entao o caso usa
# folga larga (3 dias) e confere so a forma, nao os minutos.
entrada = json.dumps({
    "model": {"display_name": "Teste"},
    "rate_limits": {
        "five_hour": {"used_percentage": 23.4, "resets_at": int(__import__("time").time()) + 2 * H + 30 * 60},
        "seven_day": {"used_percentage": 41.2, "resets_at": int(__import__("time").time()) + 3 * D + 4 * H},
    },
})
env = dict(os.environ)
env["PYTHONIOENCODING"] = "utf-8"
saida = subprocess.run(
    [sys.executable, FONTE], input=entrada.encode("utf-8"), stdout=subprocess.PIPE,
    stderr=subprocess.PIPE, env=env, timeout=30,
).stdout.decode("utf-8", "replace")
limpa = ANSI.sub("", saida)
if re.search(r"5h 23% ↻2h(29|30) .*7d 41% ↻3d(3|4)h", limpa):
    print("  ok    ponta a ponta pelo stdin")
else:
    falhas += 1
    print("  FALHA ponta a ponta pelo stdin: barra foi %r" % limpa.strip())

if falhas:
    print("FALHA: %d caso(s) do segmento de limites" % falhas)
    sys.exit(1)
print("OK: %d casos do segmento de limites" % (len(CASOS) + 1))
