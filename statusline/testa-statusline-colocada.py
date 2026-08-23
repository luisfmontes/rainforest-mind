# -*- coding: utf-8 -*-
"""Bateria do segmento de co-locada da statusline. Falsificavel: cada caso diz o
rotulo esperado, e o teste FALHA se a implementacao devolver outra coisa."""
import atexit
import datetime
import io
import json
import os
import re
import shutil
import sys
import tempfile

# Criar TEMP falso para não mexer com nada real
FAKE_TEMP = tempfile.mkdtemp(prefix="statusline-colocada-teste-")
atexit.register(lambda: shutil.rmtree(FAKE_TEMP, ignore_errors=True))

FONTE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "statusline.py"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")

ns = {"__name__": "bateria", "__file__": FONTE}
exec(compile(open(FONTE, encoding="utf-8").read(), FONTE, "exec"), ns)


def escreve_sessoes(dados, pasta_raiz=None):
    """Escreve sessoes.json falso e retorna (caminho_raiz, caminho_json).

    Se pasta_raiz for None, cria uma pasta temporária.
    """
    if pasta_raiz is None:
        pasta_raiz = os.path.join(FAKE_TEMP, "raiz-teste-%d" % id(dados))
        os.makedirs(pasta_raiz, exist_ok=True)

    caminho_json = os.path.join(pasta_raiz, "sessoes.json")
    with io.open(caminho_json, "w", encoding="utf-8") as fh:
        json.dump(dados, fh)

    # Garantir que tem pelo menos um marcador (FOCO.md ou ideias.jsonl)
    foco_path = os.path.join(pasta_raiz, "FOCO.md")
    if not os.path.exists(foco_path):
        with io.open(foco_path, "w", encoding="utf-8") as fh:
            fh.write("# Foco\n")

    return pasta_raiz


def segmento(cwd, pasta_raiz):
    """Executa segmento_co_locada com ambiente fake."""
    # Preenche resolver_raiz_dados para achar nossa pasta
    ns["resolver_raiz_dados"] = lambda c: pasta_raiz
    return ANSI.sub("", ns["segmento_co_locada"](cwd))


agora_ms = int(datetime.datetime.now().timestamp() * 1000)
JANELA = ns["JANELA_COLOCADA_MS"]


# Helpers para criar entradas de sessão
def entrada_viva(cwd):
    """Entrada de sessão viva no cwd."""
    return {"cwd": cwd, "prompt_ts": agora_ms, "stop_ts": agora_ms}


def entrada_velha(cwd):
    """Entrada de sessão antiga (fora da janela)."""
    return {"cwd": cwd, "prompt_ts": agora_ms - JANELA - 1000, "stop_ts": agora_ms - JANELA - 1000}


# ================================================================ casos ====

def caso_uma_sessao_viva():
    """Uma sessão viva no cwd (só a própria) → sem segmento."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/Projetos/x")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    return obtido, ""


def caso_duas_sessoes_vivas():
    """Duas sessões vivas no mesmo cwd → segmento aparece."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/Projetos/x"),
        "sessao-2": entrada_viva("C:/Projetos/x")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    # Esperado: "⚠ 2 janelas aqui" (sem ANSI, já foi removido)
    return obtido, "⚠ 2 janelas aqui"


def caso_duas_sessoes_uma_velha():
    """Duas sessões, mas uma velha (fora da janela) → sem segmento."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/Projetos/x"),
        "sessao-2": entrada_velha("C:/Projetos/x")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    return obtido, ""


def caso_outra_sessao_outro_cwd():
    """Outra sessão viva em outro cwd → sem segmento."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/Projetos/x"),
        "sessao-2": entrada_viva("C:/Projetos/y")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    return obtido, ""


def caso_sessoes_json_ausente():
    """sessoes.json ausente → sem segmento, sem exceção."""
    pasta_raiz = os.path.join(FAKE_TEMP, "sem-sessoes-json")
    os.makedirs(pasta_raiz, exist_ok=True)
    # Garantir marcador
    foco_path = os.path.join(pasta_raiz, "FOCO.md")
    with io.open(foco_path, "w", encoding="utf-8") as fh:
        fh.write("# Foco\n")

    ns["resolver_raiz_dados"] = lambda c: pasta_raiz
    obtido = ANSI.sub("", ns["segmento_co_locada"]("C:/Projetos/x"))
    return obtido, ""


def caso_sessoes_json_quebrado():
    """sessoes.json com JSON quebrado → sem segmento, sem exceção."""
    pasta_raiz = os.path.join(FAKE_TEMP, "json-quebrado")
    os.makedirs(pasta_raiz, exist_ok=True)

    # Escrever JSON quebrado
    caminho_json = os.path.join(pasta_raiz, "sessoes.json")
    with io.open(caminho_json, "w", encoding="utf-8") as fh:
        fh.write("{ invalid json ...")

    # Garantir marcador
    foco_path = os.path.join(pasta_raiz, "FOCO.md")
    with io.open(foco_path, "w", encoding="utf-8") as fh:
        fh.write("# Foco\n")

    ns["resolver_raiz_dados"] = lambda c: pasta_raiz
    obtido = ANSI.sub("", ns["segmento_co_locada"]("C:/Projetos/x"))
    return obtido, ""


def caso_worktree_de_agente_filtrado():
    """Worktree de agente é filtrado e não conta."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/Projetos/x"),
        "sessao-2": entrada_viva("C:/Projetos/x/.claude/worktrees/agent-abc123")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    # Só uma sessão de verdade, não conta o worktree de agente
    return obtido, ""


def caso_normalizacao_cwd_backslash():
    """Normalização de cwd: backslash vs forward slash."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:\\Projetos\\x"),
        "sessao-2": entrada_viva("C:/Projetos/x")
    })
    # Comparar com forward slash
    obtido = segmento("C:/Projetos/x", raiz)
    # Devem ser normalizadas para a mesma coisa
    return obtido, "⚠ 2 janelas aqui"


def caso_normalizacao_cwd_maiuscula():
    """Normalização de cwd: maiuscula vs minuscula."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/PROJETOS/X"),
        "sessao-2": entrada_viva("C:/Projetos/x")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    return obtido, "⚠ 2 janelas aqui"


def caso_tres_sessoes_vivas():
    """Três sessões vivas no mesmo cwd → mostra "3 janelas aqui"."""
    raiz = escreve_sessoes({
        "sessao-1": entrada_viva("C:/Projetos/x"),
        "sessao-2": entrada_viva("C:/Projetos/x"),
        "sessao-3": entrada_viva("C:/Projetos/x")
    })
    obtido = segmento("C:/Projetos/x", raiz)
    return obtido, "⚠ 3 janelas aqui"


CASOS = [
    ("uma sessão viva (só a própria) → sem segmento", caso_uma_sessao_viva),
    ("duas sessões vivas no cwd → segmento aparece", caso_duas_sessoes_vivas),
    ("duas sessões, mas uma velha → sem segmento", caso_duas_sessoes_uma_velha),
    ("outra sessão em outro cwd → sem segmento", caso_outra_sessao_outro_cwd),
    ("sessoes.json ausente → sem segmento, sem exceção", caso_sessoes_json_ausente),
    ("sessoes.json com JSON quebrado → sem segmento", caso_sessoes_json_quebrado),
    ("worktree de agente é filtrado", caso_worktree_de_agente_filtrado),
    ("normalização: backslash vs forward", caso_normalizacao_cwd_backslash),
    ("normalização: maiuscula vs minuscula", caso_normalizacao_cwd_maiuscula),
    ("três sessões vivas → mostra '3 janelas aqui'", caso_tres_sessoes_vivas),
]

falhas = 0
for nome, funcao in CASOS:
    obtido, esperado = funcao()
    ok = obtido == esperado
    if not ok:
        falhas += 1
    print(u"%s %-65s esperado=%-25r obtido=%r"
          % (u"ok  " if ok else u"FALHA", nome, esperado, obtido))

print("")
print(u"%d/%d casos passaram" % (len(CASOS) - falhas, len(CASOS)))
sys.exit(1 if falhas else 0)
