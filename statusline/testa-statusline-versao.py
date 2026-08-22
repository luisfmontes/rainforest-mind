# -*- coding: utf-8 -*-
"""Bateria do segmento de versao da statusline. Falsificavel: cada caso diz o
rotulo esperado, e o teste FALHA se a implementacao devolver outra coisa."""
import io
import json
import os
import re
import sys
import tempfile

# CACHE_VERSAO e calculado NA CARGA do modulo, a partir de os.environ["TEMP"].
# Isso tem de acontecer ANTES do exec, e com um caminho Windows de verdade —
# tempfile.mkdtemp() ja devolve um caminho no formato certo neste SO. Um
# caminho POSIX tipo "/tmp/..." o Python no Windows resolve para "C:\tmp\...",
# que nao existe, e todos os casos deixam de acender pelo motivo errado (verde
# e vermelho ficam identicos: ambos caem no "nao consegui ler o arquivo").
# Tambem nao pode ser o TEMP real da maquina: a bateria nao pode ler nem
# escrever o cache de versao de verdade.
FAKE_TEMP = tempfile.mkdtemp(prefix="statusline-versao-teste-")
os.environ["TEMP"] = FAKE_TEMP

FONTE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "statusline.py"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# Mesmo motivo do __file__ na bateria de prazo: o fonte resolve vizinhos por
# caminho relativo a si mesmo, e sem isso o exec estoura NameError.
ns = {"__name__": "bateria", "__file__": FONTE}
exec(compile(open(FONTE, encoding="utf-8").read(), FONTE, "exec"), ns)

_contador_transcript = [0]


def escreve_cache(conteudo):
    """None apaga o cache (simula ausencia); string escreve o conteudo."""
    caminho = ns["CACHE_VERSAO"]
    if conteudo is None:
        if os.path.exists(caminho):
            os.remove(caminho)
        return
    with io.open(caminho, "w", encoding="utf-8") as fh:
        fh.write(conteudo)


def escreve_transcript(linhas):
    """Escreve um .jsonl de transcript falso e devolve o caminho."""
    _contador_transcript[0] += 1
    caminho = os.path.join(FAKE_TEMP, "transcript-%d.jsonl" % _contador_transcript[0])
    with io.open(caminho, "w", encoding="utf-8") as fh:
        fh.write("\n".join(linhas))
    return caminho


def segmento(transcript_path):
    return ANSI.sub("", ns["segmento_versao"](transcript_path))


# ---------------------------------------------------------------- casos ----
def caso_atrasado():
    escreve_cache("2.1.231")
    caminho = escreve_transcript([json.dumps({"version": "2.1.220"})])
    return segmento(caminho), u"2.1.220 \u21e9"


def caso_em_dia():
    escreve_cache("2.1.231")
    caminho = escreve_transcript([json.dumps({"version": "2.1.231"})])
    return segmento(caminho), u""


def caso_sem_cache():
    escreve_cache(None)
    caminho = escreve_transcript([json.dumps({"version": "2.1.220"})])
    return segmento(caminho), u""


def caso_sem_transcript():
    # Cache presente e valido: se o segmento acender aqui, o defeito e ignorar
    # a ausencia do transcript, nao a ausencia do cache.
    escreve_cache("2.1.231")
    inexistente = os.path.join(FAKE_TEMP, "nao-existe.jsonl")
    obtido_inexistente = segmento(inexistente)
    obtido_none = segmento(None)
    if obtido_inexistente == u"" and obtido_none == u"":
        return u"", u""
    return u"inexistente=%r none=%r" % (obtido_inexistente, obtido_none), u""


def caso_transcript_vazio():
    escreve_cache("2.1.231")
    caminho = escreve_transcript([])  # 0 byte
    return segmento(caminho), u""


def caso_json_invalido_na_ultima_linha():
    escreve_cache("2.1.231")
    caminho = escreve_transcript([
        json.dumps({"version": "2.1.220"}),
        u"isto nao e json valido {{{",
    ])
    return segmento(caminho), u"2.1.220 \u21e9"


def caso_2_1_9_vs_2_1_10():
    # Separa comparacao numerica de comparacao de string: como texto,
    # "2.1.9" > "2.1.10" (o caractere '9' > '1'); numericamente 9 < 10.
    escreve_cache("2.1.10")
    caminho = escreve_transcript([json.dumps({"version": "2.1.9"})])
    return segmento(caminho), u"2.1.9 \u21e9"


def caso_cache_com_lixo():
    escreve_cache("nao-e-versao")
    caminho = escreve_transcript([json.dumps({"version": "2.1.220"})])
    return segmento(caminho), u""


CASOS = [
    (u"atrasado: cache a frente, segmento acende com a versao da sessao", caso_atrasado),
    (u"em dia: mesma versao do cache, segmento vazio", caso_em_dia),
    (u"sem cache: arquivo de cache ausente, segmento vazio", caso_sem_cache),
    (u"sem transcript: caminho inexistente e None, segmento vazio", caso_sem_transcript),
    (u"transcript vazio (0 byte), segmento vazio", caso_transcript_vazio),
    (u"JSON invalido na ultima linha cai para a anterior valida", caso_json_invalido_na_ultima_linha),
    (u"2.1.9 vs 2.1.10: comparacao tem de ser numerica, nao textual", caso_2_1_9_vs_2_1_10),
    (u"cache com lixo (nao-versao): incomparavel, segmento vazio", caso_cache_com_lixo),
]

falhas = 0
for nome, funcao in CASOS:
    obtido, esperado = funcao()
    ok = obtido == esperado
    if not ok:
        falhas += 1
    print(u"%s %-70s esperado=%-16r obtido=%r"
          % (u"ok  " if ok else u"FALHA", nome, esperado, obtido))

print("")
print(u"%d/%d casos passaram" % (len(CASOS) - falhas, len(CASOS)))
sys.exit(1 if falhas else 0)
