#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Statusline do Claude Code — um unico processo por render.

Segmentos, na ordem:
    pasta (wt) branch N+   perfil   modelo   ctx%   5h% 7d%   relogio · jornada   prazo

Regras de projeto que este arquivo respeita:
  - jornada NUNCA e inferida aqui: o numero vem do scripts/jornada.cjs do
    rainforest-mind, executado em segundo plano e lido de cache (regra 8).
  - nada pode travar a barra: todo subprocesso tem timeout e todo segmento
    que falhar simplesmente nao aparece.
"""

import datetime
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HOME = os.path.expanduser("~")
CACHE_JORNADA = os.path.join(
    os.environ.get("TEMP", os.path.join(HOME, "AppData", "Local", "Temp")),
    "claude-statusline-jornada.txt",
)
CACHE_VERSAO = os.path.join(
    os.environ.get("TEMP", os.path.join(HOME, "AppData", "Local", "Temp")),
    "claude-statusline-versao.txt",
)
# statusline.py agora esta no plugin com statusline-jornada.sh ao lado.
# Caminho relativo ao arquivo evita dependencia de ~/.claude que sera apagado.
REFRESHER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline-jornada.sh")
REFRESHER_VERSAO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline-versao.sh")
FOCO = os.path.join(HOME, ".rainforest", "FOCO.md")
IDADE_MAX_CACHE = 90  # segundos
IDADE_MAX_CACHE_VERSAO = 6 * 3600  # 6 horas para cache de versao
GIT_TIMEOUT = 1.5

# ---------------------------------------------------------------- cores ----
RESET = "\033[0m"


def c(texto, cor, negrito=False):
    prefixo = "\033[1m" if negrito else ""
    return "%s\033[38;5;%dm%s%s" % (prefixo, cor, texto, RESET)


CINZA = 245
CINZA_ESCURO = 240
CIANO = 80
AMARELO = 179
VERDE = 114
VERMELHO = 203
MAGENTA = 176
AZUL = 111

SEP = c(" \u2502 ", CINZA_ESCURO)


def por_faixa(valor, atencao, alerta):
    """Verde abaixo de `atencao`, amarelo ate `alerta`, vermelho acima."""
    if valor >= alerta:
        return VERMELHO
    if valor >= atencao:
        return AMARELO
    return VERDE


# ------------------------------------------------------------------ git ----
def git(cwd, *args):
    try:
        r = subprocess.run(
            ["git", "-C", cwd, "--no-optional-locks"] + list(args),
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT,
        )
    except Exception:
        return ""
    if r.returncode != 0:
        return ""
    return r.stdout.strip()


def segmento_local(cwd):
    """pasta (wt) branch N+ — onde esta esta janela."""
    pasta = os.path.basename(os.path.abspath(cwd)) or cwd
    partes = [c(pasta, CIANO, negrito=True)]

    info = git(cwd, "rev-parse", "--abbrev-ref", "HEAD", "--git-dir", "--git-common-dir")
    if not info:
        return " ".join(partes)

    linhas = info.splitlines()
    branch = linhas[0] if linhas else ""
    gitdir = linhas[1] if len(linhas) > 1 else ""

    if "worktrees" in gitdir.replace("\\", "/"):
        partes.append(c("wt", MAGENTA))

    if branch == "HEAD":
        branch = git(cwd, "rev-parse", "--short", "HEAD") or "?"
    if branch:
        partes.append(c(branch, AMARELO))

    sujos = git(cwd, "status", "--porcelain", "-uno")
    n = len([l for l in sujos.splitlines() if l.strip()])
    if n:
        partes.append(c("%d\u25b4" % n, VERMELHO))

    return " ".join(partes)


# ----------------------------------------------------------------- perfil --
def segmento_perfil(dados):
    origem = dados.get("transcript_path") or os.environ.get("CLAUDE_CONFIG_DIR", "")
    origem = origem.replace("\\", "/")
    if ".claude-personal" in origem:
        return c("pessoal", MAGENTA)
    if "/.claude/" in origem or origem.endswith("/.claude"):
        return c("trabalho", AZUL)
    return ""


# --------------------------------------------------------------- jornada ---
def dispara_refresh():
    bash = "C:/Program Files/Git/bin/bash.exe"
    if not (os.path.exists(bash) and os.path.exists(REFRESHER)):
        return
    try:
        subprocess.Popen(
            [bash, REFRESHER.replace("\\", "/")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "DETACHED_PROCESS", 0),
        )
    except Exception:
        pass


def segmento_tempo():
    agora = datetime.datetime.now()
    cor_relogio = VERMELHO if agora.hour >= 19 else CINZA
    partes = [c(agora.strftime("%Hh%M"), cor_relogio)]

    valor = ""
    try:
        idade = agora.timestamp() - os.path.getmtime(CACHE_JORNADA)
        with open(CACHE_JORNADA, "r", encoding="utf-8") as fh:
            valor = fh.read().strip()
        if idade > IDADE_MAX_CACHE:
            dispara_refresh()
    except Exception:
        dispara_refresh()

    m = re.match(r"^(\d+)h(\d+)$", valor)
    if m:
        horas = int(m.group(1)) + int(m.group(2)) / 60.0
        partes.append(c(valor, por_faixa(horas, 6, 8)))

    return c(" \u00b7 ", CINZA_ESCURO).join(partes)


# ----------------------------------------------------------------- prazo ---
def secoes_de_prazo(texto):
    """So 'Ativo' e 'Compromissos com prazo' — o resto do FOCO.md e historico."""
    blocos, atual, coletando = [], [], False
    for linha in texto.splitlines():
        if linha.startswith("## "):
            if coletando:
                blocos.append("\n".join(atual))
            titulo = linha[3:].strip().lower()
            coletando = titulo.startswith("ativo") or titulo.startswith("compromissos")
            atual = []
            continue
        if coletando:
            atual.append(linha)
    if coletando:
        blocos.append("\n".join(atual))
    return "\n".join(blocos)


# Carimbo de registro de avanco: "- 2026-08-18: a Task 1 rodou". A data ali e a
# do diario, nao um compromisso \u2014 e a regra 5 manda datar o avanco no fim de toda
# sessao, entao sem esta linha o proprio metodo acende "prazo hoje" todo santo
# dia. Alarme sempre aceso e alarme que se aprende a ignorar, e o custo cai
# justamente na semana do prazo de verdade.
RE_CARIMBO = re.compile(r"^\s*[-*+]?\s*\d{4}-\d{2}-\d{2}\s*[:\u2013\u2014-]\s*")
# Allowlist, nao blocklist: data solta no meio da prosa e quase sempre contexto
# ("declarado em 12/08", "combinado no grupo em 29/07"), nunca o prazo em si.
RE_MARCADOR = re.compile(
    r"prazo|at[e\u00e9]\s|entrega|reuni[a\u00e3]o|vence|marco|limite|deadline",
    re.IGNORECASE,
)


def datas_de_compromisso(linha, hoje):
    """So as datas que a linha declara como COMPROMISSO \u2014 nao carimbo, nao contexto."""
    if "\u2705" in linha or "conclu" in linha.lower():
        return []
    # Tira so o carimbo, nao a linha: "- 2026-08-20: prazo do X e 22/08" ainda conta o 22.
    linha = RE_CARIMBO.sub("", linha, count=1)
    if not RE_MARCADOR.search(linha):
        return []
    # Remover clausulas de contexto com conectivos expandidos.
    # Allowlist necessariamente incompleto \u2014 portugues nao cabe em lista.
    # Oracoes subordinadas de contexto sao mencionadas para referencia, nao como
    # compromisso \u2014 e podem ser intercaladas (no meio da frase) ou caudas (ao fim).
    # Diferenca: intercalada fecha com virgula ("Prazo, segundo fulano, e 26/08");
    # cauda corre ate o fim ("Entrega ate 30/08, conforme reuniao de 22/08").
    # Remover tudo entre virgula + conectivo e a proxima virgula OU fim de linha
    # trata os dois casos com uma regra so, mantendo a data de compromisso.
    conectivos_contexto = (
        r",\s*"
        r"(conforme|de acordo com|segundo|declarado|citado|mencionado|"
        r"definido|alinhado|acordado|combinado|tratado|discutido|previsto)"
        r"(?:[^,])*"
    )
    linha_limpa = re.sub(conectivos_contexto, "", linha, flags=re.IGNORECASE)

    # Encontrar datas na string limpa. Sem ancoragem por posicao: a ordem inversa
    # ("31/08 e o prazo final de entrega") e portugues comum, e falso negativo
    # (alarme que nao acende no prazo) e mais caro que falso positivo (alarme cedo
    # que o Luis ve e descarta). Entre os dois erros, a barra prefere o cedo.
    achadas = []

    # Datas YYYY-MM-DD
    for m in re.finditer(r"\b(\d{4})-(\d{2})-(\d{2})\b", linha_limpa):
        a, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        achadas.append((a, mo, d))

    # Datas DD/MM
    for m in re.finditer(r"\b(\d{2})/(\d{2})\b", linha_limpa):
        d, mo = int(m.group(1)), int(m.group(2))
        achadas.append((hoje.year, mo, d))

    return achadas


def segmento_prazo():
    try:
        with open(FOCO, "r", encoding="utf-8") as fh:
            texto = secoes_de_prazo(fh.read())
    except Exception:
        return ""

    hoje = datetime.date.today()
    datas = []
    for linha in texto.splitlines():
        datas.extend(datas_de_compromisso(linha, hoje))

    futuras = []
    for a, m, d in datas:
        try:
            data = datetime.date(a, m, d)
        except ValueError:
            continue
        if data >= hoje:
            futuras.append(data)
    if not futuras:
        return ""

    faltam = (min(futuras) - hoje).days
    if faltam == 0:
        rotulo, cor = "prazo hoje", VERMELHO
    elif faltam == 1:
        rotulo, cor = "prazo 1d", VERMELHO
    elif faltam <= 3:
        rotulo, cor = "prazo %dd" % faltam, AMARELO
    else:
        rotulo, cor = "prazo %dd" % faltam, CINZA_ESCURO
    return c(rotulo, cor)


# ---------------------------------------------------------------- versao ---
def le_cache_versao():
    """Le cache de versao estavel da CLI. Retorna string ou vazio se falhar."""
    try:
        with open(CACHE_VERSAO, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except Exception:
        return ""


def le_versao_transcript(transcript_path):
    """Le a versao da sessao do transcript, lendo apenas os ultimos 8 KB.

    Procura de tras para frente pela primeira linha JSONL valida com
    um campo "version". Ignora linhas JSON invalidas.
    """
    if not transcript_path:
        return ""

    try:
        # Abre arquivo para ler cauda.
        with open(transcript_path, "rb") as fh:
            fh.seek(0, 2)  # vai ao fim
            tamanho = fh.tell()

            # Le no maximo 8 KB do final.
            tamanho_leitura = min(8192, tamanho)
            fh.seek(tamanho - tamanho_leitura)
            cauda = fh.read().decode("utf-8", errors="ignore")

        # Processa linhas de tras para frente.
        linhas = cauda.splitlines()
        for linha in reversed(linhas):
            if not linha.strip():
                continue
            try:
                obj = json.loads(linha)
                versao = obj.get("version")
                if versao and isinstance(versao, str):
                    return versao.strip()
            except Exception:
                # Linha com JSON invalido, continua para a anterior.
                continue

        return ""
    except Exception:
        return ""


def compara_versoes(v1, v2):
    """Compara duas versoes numericamente, componente a componente.

    Retorna -1 se v1 < v2, 0 se v1 == v2, 1 se v1 > v2.
    Retorna None se versoes sao incomparaveis (componentes nao numericos).
    """
    try:
        p1 = [int(x) for x in v1.split(".")]
        p2 = [int(x) for x in v2.split(".")]
    except Exception:
        return None

    # Compara componente a componente.
    for i in range(max(len(p1), len(p2))):
        c1 = p1[i] if i < len(p1) else 0
        c2 = p2[i] if i < len(p2) else 0
        if c1 < c2:
            return -1
        if c1 > c2:
            return 1

    return 0


def dispara_refresh_versao():
    """Dispara refresher de versao em segundo plano, mesmo molde do jornada."""
    bash = "C:/Program Files/Git/bin/bash.exe"
    if not (os.path.exists(bash) and os.path.exists(REFRESHER_VERSAO)):
        return
    try:
        subprocess.Popen(
            [bash, REFRESHER_VERSAO.replace("\\", "/")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "DETACHED_PROCESS", 0),
        )
    except Exception:
        pass


def segmento_versao(transcript_path):
    """Avisa quando a versao da sessao esta atras do estavel publicado.

    Le cache de versao estavel; se estiver velho (> 6 horas), dispara
    refresher em segundo plano. Compara com versao da sessao lida do
    transcript. Se estiver atrasada, retorna segmento com versao e sinal
    de atraso. Qualquer falha retorna string vazia.
    """
    versao_sessao = le_versao_transcript(transcript_path)
    if not versao_sessao:
        return ""

    # Confere idade do cache; se velho, dispara refresh.
    agora = datetime.datetime.now()
    try:
        idade = agora.timestamp() - os.path.getmtime(CACHE_VERSAO)
        if idade > IDADE_MAX_CACHE_VERSAO:
            dispara_refresh_versao()
    except Exception:
        dispara_refresh_versao()

    # Le cache de versao estavel.
    versao_estavel = le_cache_versao()
    if not versao_estavel:
        return ""

    # Compara numericamente.
    cmp = compara_versoes(versao_sessao, versao_estavel)
    if cmp is None:
        # Versoes incomparaveis, nao mostra nada.
        return ""

    if cmp < 0:
        # Sessao esta atrasada. Mostra versao da sessao e sinal de atraso.
        return c(versao_sessao + " \u21e9", AMARELO)

    # Versoes iguais ou sessao adiantada: sem segmento.
    return ""


# ------------------------------------------------------------------ main ---
def main():
    try:
        dados = json.load(sys.stdin)
    except Exception:
        dados = {}

    cwd = dados.get("cwd") or dados.get("workspace", {}).get("current_dir") or "."
    transcript_path = dados.get("transcript_path")

    segmentos = [segmento_local(cwd), segmento_perfil(dados)]

    modelo = dados.get("model", {}).get("display_name") or dados.get("model", {}).get("id")
    if modelo:
        segmentos.append(c(modelo, CINZA))

    ctx = dados.get("context_window", {}).get("used_percentage")
    if isinstance(ctx, (int, float)):
        segmentos.append(c("ctx %d%%" % round(ctx), por_faixa(ctx, 50, 75)))

    limites = dados.get("rate_limits", {})
    partes_limite = []
    for chave, rotulo in (("five_hour", "5h"), ("seven_day", "7d")):
        pct = limites.get(chave, {}).get("used_percentage")
        if isinstance(pct, (int, float)):
            partes_limite.append(c("%s %d%%" % (rotulo, round(pct)), por_faixa(pct, 60, 85)))
    if partes_limite:
        segmentos.append(" ".join(partes_limite))

    segmentos.append(segmento_tempo())
    segmentos.append(segmento_versao(transcript_path))
    segmentos.append(segmento_prazo())

    print(SEP.join([s for s in segmentos if s]))


if __name__ == "__main__":
    main()
