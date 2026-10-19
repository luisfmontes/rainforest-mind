# -*- coding: utf-8 -*-
"""Bateria do segmento de perfil da statusline: a conta mostrada e a logada,
nao a que o nome da pasta sugere.

Existe por um defeito real: depois de `/conta pessoal` a pasta ~/.claude passou
a usar a conta pessoal e a barra seguiu dizendo "trabalho", porque o segmento
so olhava o caminho. Falsificavel: cada caso diz a conta esperada, e o teste
FALHA se a implementacao devolver outra."""
import io
import json
import os
import re
import shutil
import sys
import tempfile

FONTE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "statusline.py"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")

ns = {"__name__": "bateria", "__file__": FONTE}
exec(compile(io.open(FONTE, encoding="utf-8").read(), FONTE, "exec"), ns)

TRABALHO = "team@exemplo.invalid"
PESSOAL = "pessoal@exemplo.invalid"
ESTADO = {"contas": {"team": {"email": TRABALHO}, "pessoal": {"email": PESSOAL}}}
PASTA_TRABALHO = "<home>/.claude/projects/a.jsonl"
PASTA_PESSOAL = "<home>/.claude-personal/projects/a.jsonl"

tmp = tempfile.mkdtemp(prefix="testa-perfil-")
falhas = 0


def grava(caminho, obj):
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(obj, f)


def caso(nome, email, estado, pasta, esperado):
    global falhas
    base = os.path.join(tmp, nome.replace(" ", "-"))
    cfg = os.path.join(base, ".claude")
    os.makedirs(cfg)
    if email is not None:
        grava(os.path.join(cfg, ".claude.json"), {"oauthAccount": {"emailAddress": email}})
    dados = os.path.join(base, "dados")
    if estado is not None:
        os.makedirs(os.path.join(dados, "contas"))
        grava(os.path.join(dados, "contas", "estado.json"), estado)
    os.environ["CLAUDE_CONFIG_DIR"] = cfg
    os.environ["RFM_CONTA_DADOS"] = dados
    saida = ANSI.sub("", ns["segmento_perfil"]({"transcript_path": pasta}))
    ok = saida == esperado
    falhas += 0 if ok else 1
    print("%s %s: esperado %r, veio %r" % ("ok  " if ok else "FALHA", nome, esperado, saida))


# Pasta de trabalho com a conta pessoal logada: o defeito original.
caso("pasta trabalho conta pessoal", PESSOAL, ESTADO, PASTA_TRABALHO, "pessoal")
caso("pasta pessoal conta trabalho", TRABALHO, ESTADO, PASTA_PESSOAL, "trabalho")
caso("pasta trabalho conta trabalho", TRABALHO, ESTADO, PASTA_TRABALHO, "trabalho")
# Sem registro ou e-mail desconhecido: volta ao palpite pela pasta.
caso("sem estado", PESSOAL, None, PASTA_TRABALHO, "trabalho")
caso("sem claude json", None, ESTADO, PASTA_PESSOAL, "pessoal")
caso("email desconhecido", "outro@exemplo.invalid", ESTADO, PASTA_TRABALHO, "trabalho")

shutil.rmtree(tmp, ignore_errors=True)
sys.exit(1 if falhas else 0)
