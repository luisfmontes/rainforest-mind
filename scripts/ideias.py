#!/usr/bin/env python3
"""Escrita segura no ideias.jsonl — a trava mecanica que substitui o procedimento decorado.

Por que existe: os quatro cuidados da skill do /ideia sao hoje um checklist em prosa
que cada janela reimplementa do zero, em script improvisado, toda vez. Funciona
enquanto ninguem esquece — e esquecer corrompe a memoria inteira, com descoberta
tardia. Relatorios que geraram este arquivo:

  relatorios/2026-08-08-executor-reincidencia-isolamento.md  (P1: tirar o veredito
      das maos de quem executa; trava mecanica vale mais que regra escrita)
  relatorios/2026-08-09-plantar-ideia-atrito-e-lacuna.md     (P1 a P4: comando unico,
      modelar `unificada`, provar que nao mexi no que nao devia, escrita atomica)

O que ele garante, em toda operacao de escrita:

  1. Trava de arquivo — sessoes paralelas do Luis escrevem neste jsonl. Reler-vivo
     mitiga; trava resolve.
  2. Releitura do arquivo VIVO no instante da escrita, nunca de leitura anterior.
     Em 2026-08-09 o arquivo cresceu por baixo de uma janela entre duas operacoes
     dela, e so a releitura evitou apagar a ideia de outra sessao.
  3. Backup antes de qualquer escrita.
  4. Escrita em temporario + os.replace atomico. Erro no meio de escrita direta
     deixa truncado o arquivo que e a memoria inteira.
  5. Newline final garantido, LF sempre (o arquivo e LF puro; CRLF quebraria o diff).
  6. Contagem conferida por operacao: +1 no plantar, igual no colher e no unificar.
  7. Linhas nao-alvo conferidas byte a byte apos a escrita. Contagem igual convive
     com a linha errada sobrescrita — so a identidade prova.
  8. Data carimbada AQUI, do relogio local. O modelo nunca digita data: em
     2026-08-08 as 22:30 uma janela leu UTC, achou que era madrugada do dia 9 e
     gravou plantada_em no futuro. Campo de data vindo do input e erro, nao aviso.

Qualquer falha sai com exit code != 0 antes de tocar o arquivo. Exit code nao se
argumenta — que e a razao de a trava ser codigo e nao paragrafo.

Uso:
  python scripts/ideias.py plantar  < nova.json
  python scripts/ideias.py colher   --id <id>  < resultado.json
  python scripts/ideias.py editar   --id <id>  < mudancas.json
  python scripts/ideias.py iniciar  --id <id>
  python scripts/ideias.py unificar --manter <id> --absorver <id>  < fundida.json
  python scripts/ideias.py reparar  [--id <id> | --todas] [--conferir]
  python scripts/ideias.py listar   [--status plantada] [--tipo ideia|observacao|todos]
  python scripts/ideias.py conferir
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import date, datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ALVO = RAIZ / "ideias.jsonl"
DIR_BACKUP = RAIZ / ".ideias-backups"
TRAVA = RAIZ / ".ideias.lock"

CAMPOS_OBRIGATORIOS = ("id", "titulo", "descricao", "contexto", "projeto")
# Campos que o script carimba. Vindos do input, sao erro — e a correcao por
# construcao do bug de UTC: o modelo nao tem como escrever data errada se nao
# escreve data nenhuma.
CAMPOS_PROIBIDOS_NO_INPUT = (
    "status", "plantada_em", "colhida_em", "unificada_em", "unificada_em_id",
    "colheita_iniciada_em",
)
STATUS_CONHECIDOS = ("plantada", "em-colheita", "colhida", "unificada")
TIPOS_CONHECIDOS = ("ideia", "observacao")
ORDEM_CANONICA = (
    "id", "titulo", "descricao", "contexto", "projeto", "ao_colher", "tipo",
    "status", "plantada_em", "colheita_iniciada_em", "andamento",
    "colhida_em", "resultado", "unificada_em", "unificada_em_id", "absorveu",
)
RE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class Erro(Exception):
    """Falha prevista: mensagem limpa e exit 1, sem stack trace."""


# --------------------------------------------------------------------------
# data — sempre local, nunca UTC
# --------------------------------------------------------------------------

def hoje() -> str:
    """Data do relogio LOCAL. Nao usar utcnow(): depois das 21h em Brasilia o
    UTC ja virou o dia e o carimbo sai no futuro (incidente 2026-08-08)."""
    return date.today().isoformat()


# --------------------------------------------------------------------------
# trava e leitura
# --------------------------------------------------------------------------

class Trava:
    """Trava de arquivo entre sessoes paralelas. Stale acima de 120s e quebrada."""

    def __init__(self, caminho: Path, espera: float = 10.0):
        self.caminho = caminho
        self.espera = espera
        self.fd = None

    def __enter__(self):
        limite = time.monotonic() + self.espera
        while True:
            try:
                self.fd = os.open(self.caminho, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(self.fd, f"{os.getpid()} {datetime.now().isoformat()}\n".encode())
                return self
            except FileExistsError:
                idade = time.time() - self.caminho.stat().st_mtime
                if idade > 120:
                    print(f"aviso: trava com {idade:.0f}s (orfa) — quebrando", file=sys.stderr)
                    self.caminho.unlink(missing_ok=True)
                    continue
                if time.monotonic() > limite:
                    raise Erro(
                        f"outra sessao esta escrevendo (trava em {self.caminho} ha {idade:.0f}s). "
                        "Tente de novo em instantes."
                    )
                time.sleep(0.2)

    def __exit__(self, *_):
        if self.fd is not None:
            os.close(self.fd)
        self.caminho.unlink(missing_ok=True)
        return False


def ler_vivo() -> list[str]:
    """Le o arquivo VIVO agora. Nunca reaproveitar leitura de antes da operacao."""
    if not ALVO.exists():
        raise Erro(f"nao achei {ALVO}")
    bruto = ALVO.read_text(encoding="utf-8")
    return [l for l in bruto.split("\n") if l.strip()]


def parse_linhas(linhas: list[str]) -> list[dict]:
    saida = []
    for i, l in enumerate(linhas, 1):
        try:
            saida.append(json.loads(l))
        except json.JSONDecodeError as e:
            raise Erro(f"linha {i} nao e JSON valido: {e}")
    return saida


def indice_por_id(linhas: list[str], alvo_id: str) -> int:
    for i, obj in enumerate(parse_linhas(linhas)):
        if obj.get("id") == alvo_id:
            return i
    raise Erro(f"id '{alvo_id}' nao existe no arquivo")


def serializar(obj: dict) -> str:
    """Uma linha, campos na ordem canonica, acento literal (o arquivo e UTF-8)."""
    ordenado = {k: obj[k] for k in ORDEM_CANONICA if k in obj}
    ordenado.update({k: v for k, v in obj.items() if k not in ordenado})
    linha = json.dumps(ordenado, ensure_ascii=False)
    json.loads(linha)  # nunca gravar o que nao volta
    return linha


# --------------------------------------------------------------------------
# gravacao verificada — o coracao
# --------------------------------------------------------------------------

def gravar(linhas_antes: list[str], linhas_depois: list[str], alvos: set[int], rotulo: str) -> None:
    """Grava atomico e prova o resultado lendo o arquivo de volta do disco.

    `alvos` sao os indices que PODEM ter mudado. Todo o resto e conferido byte a
    byte: contagem igual convive com a linha errada sobrescrita (P3 do relatorio
    de 2026-08-09), entao contagem sozinha nao prova nada.
    """
    DIR_BACKUP.mkdir(exist_ok=True)
    # Milissegundos, nao segundos: em 2026-08-09 tres operacoes seguidas cairam
    # no mesmo segundo e as duas ultimas sobrescreveram o backup da primeira.
    # A reversao de cada operacao continuava certa (ela usa o backup que acabou
    # de tirar), mas o historico intermediario sumia — e backup que some sem
    # avisar e a mesma familia de defeito que este arquivo inteiro combate.
    carimbo = datetime.now().strftime("%Y%m%d-%H%M%S-%f")[:-3]
    backup = DIR_BACKUP / f"ideias-{carimbo}.jsonl"
    if backup.exists():  # cinto e suspensorio, caso o relogio repita
        raise Erro(f"backup {backup.name} ja existe — abortando antes de escrever")
    shutil.copy2(ALVO, backup)

    tmp = ALVO.with_suffix(".jsonl.tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(linhas_depois) + "\n")  # newline final garantido
    os.replace(tmp, ALVO)  # atomico

    # --- prova, lendo do disco ---
    relidas = ler_vivo()
    problemas = []

    if len(relidas) != len(linhas_depois):
        problemas.append(f"contagem no disco {len(relidas)} != esperada {len(linhas_depois)}")

    intocadas = 0
    for i in range(min(len(linhas_antes), len(relidas))):
        if i in alvos:
            continue
        if linhas_antes[i] == relidas[i]:
            intocadas += 1
        else:
            problemas.append(f"linha {i + 1} mudou e nao devia")

    try:
        parse_linhas(relidas)
    except Erro as e:
        problemas.append(str(e))

    nao_alvo = len(linhas_antes) - len([i for i in alvos if i < len(linhas_antes)])
    print(f"  contagem: {len(linhas_antes)} -> {len(relidas)}")
    print(f"  todas as {len(relidas)} linhas sao JSON valido: {'sim' if not problemas else 'NAO'}")
    print(f"  linhas nao-alvo identicas byte a byte: {intocadas}/{nao_alvo}")
    print(f"  backup: {backup.relative_to(RAIZ)}")

    if problemas:
        shutil.copy2(backup, ALVO)
        raise Erro(f"{rotulo} REVERTIDO — {'; '.join(problemas)}")
    print(f"  {rotulo}: ok")


def validar_entrada(obj: dict, exigir_obrigatorios: bool = True) -> None:
    if not isinstance(obj, dict):
        raise Erro("o JSON da entrada precisa ser um objeto")
    proibidos = [c for c in CAMPOS_PROIBIDOS_NO_INPUT if c in obj]
    if proibidos:
        raise Erro(
            f"campo(s) {', '.join(proibidos)} nao vem da entrada — quem carimba e o script, "
            "do relogio local. Remova e rode de novo."
        )
    if exigir_obrigatorios:
        faltando = [c for c in CAMPOS_OBRIGATORIOS if not obj.get(c)]
        if faltando:
            raise Erro(f"campo(s) obrigatorio(s) faltando ou vazio(s): {', '.join(faltando)}")
    if "id" in obj and not RE_ID.match(obj["id"]):
        raise Erro(f"id '{obj['id']}' nao e kebab-case ([a-z0-9] separado por hifen)")
    if "tipo" in obj and obj["tipo"] not in TIPOS_CONHECIDOS:
        raise Erro(f"tipo '{obj['tipo']}' desconhecido — use {' ou '.join(TIPOS_CONHECIDOS)}")


def ler_stdin() -> dict:
    bruto = sys.stdin.read().strip()
    if not bruto:
        raise Erro("nada na entrada padrao — mande o JSON por stdin (< arquivo.json)")
    try:
        return json.loads(bruto)
    except json.JSONDecodeError as e:
        raise Erro(f"entrada nao e JSON valido: {e}")


# --------------------------------------------------------------------------
# comandos
# --------------------------------------------------------------------------

def cmd_plantar(_args) -> None:
    novo = ler_stdin()
    validar_entrada(novo)
    with Trava(TRAVA):
        antes = ler_vivo()
        if any(o.get("id") == novo["id"] for o in parse_linhas(antes)):
            raise Erro(f"ja existe ideia com id '{novo['id']}' — escolha outro")
        novo["status"] = "plantada"
        novo["plantada_em"] = hoje()
        novo.setdefault("ao_colher", None)
        depois = antes + [serializar(novo)]
        print(f"plantando '{novo['id']}'")
        gravar(antes, depois, {len(antes)}, "plantar")


def cmd_colher(args) -> None:
    entrada = ler_stdin()
    validar_entrada(entrada, exigir_obrigatorios=False)
    if not entrada.get("resultado"):
        raise Erro("colher exige {\"resultado\": \"...\"} na entrada — o que de fato foi entregue")
    with Trava(TRAVA):
        antes = ler_vivo()
        i = indice_por_id(antes, args.id)
        obj = json.loads(antes[i])
        if obj.get("status") == "colhida":
            raise Erro(f"'{args.id}' ja esta colhida em {obj.get('colhida_em')}")
        obj.update({k: v for k, v in entrada.items() if k != "resultado"})
        obj["status"] = "colhida"
        obj["colhida_em"] = hoje()
        obj["resultado"] = entrada["resultado"]
        depois = list(antes)
        depois[i] = serializar(obj)
        print(f"colhendo '{args.id}' (linha {i + 1})")
        gravar(antes, depois, {i}, "colher")


def cmd_editar(args) -> None:
    """Corrige campos de uma ideia ainda aberta.

    Faltava, e a falta apareceu rapido: em 2026-08-09, uma hora depois de plantar
    seis ideias, duas precisaram de correcao de conteudo — a decisao do idioma
    saiu e o desenho de "dois repos" virou "um repo mais pasta de dados". Havia
    comando para nascer e para fechar, nenhum para mudar de ideia no meio. Sem
    ele a correcao vira edicao a mao no jsonl, que e exatamente o que este
    arquivo inteiro existe para impedir.

    So mexe no que ainda esta aberto: colhida e unificada sao registro do que
    aconteceu, e reescrever registro fechado apaga a historia em vez de corrigi-la.
    """
    entrada = ler_stdin()
    validar_entrada(entrada, exigir_obrigatorios=False)
    if "id" in entrada and entrada["id"] != args.id:
        raise Erro("editar nao troca id — o id e a identidade da ideia, nao um campo")
    mudaveis = {k: v for k, v in entrada.items() if k != "id"}
    if not mudaveis:
        raise Erro("nada para editar — mande no JSON so os campos que mudam")
    with Trava(TRAVA):
        antes = ler_vivo()
        i = indice_por_id(antes, args.id)
        obj = json.loads(antes[i])
        if obj.get("status") in ("colhida", "unificada"):
            raise Erro(
                f"'{args.id}' esta '{obj['status']}' — o que ja fechou nao se reescreve"
            )
        obj.update(mudaveis)
        obj["editada_em"] = hoje()
        depois = list(antes)
        depois[i] = serializar(obj)
        print(f"editando '{args.id}' (linha {i + 1}): {', '.join(sorted(mudaveis))}")
        gravar(antes, depois, {i}, "editar")


def cmd_iniciar(args) -> None:
    with Trava(TRAVA):
        antes = ler_vivo()
        i = indice_por_id(antes, args.id)
        obj = json.loads(antes[i])
        if obj.get("status") != "plantada":
            raise Erro(f"'{args.id}' esta '{obj.get('status')}', so 'plantada' vira 'em-colheita'")
        obj["status"] = "em-colheita"
        obj["colheita_iniciada_em"] = hoje()
        # Sem isto, 'em-colheita' diz que comecou e nao diz o que ja andou —
        # e o que falta volta a ser reconstruido de memoria na proxima sessao.
        if args.andamento:
            obj["andamento"] = args.andamento
        depois = list(antes)
        depois[i] = serializar(obj)
        print(f"iniciando colheita de '{args.id}' (linha {i + 1})")
        gravar(antes, depois, {i}, "iniciar")


def cmd_unificar(args) -> None:
    """Duas linhas na mesma operacao: a que sobrevive recebe o conteudo fundido,
    a absorvida vira ponteiro. Operacao que a skill nao previa e que em
    2026-08-09 obrigou uma janela a inventar status no meio do caminho."""
    fundida = ler_stdin()
    validar_entrada(fundida)
    if args.manter == args.absorver:
        raise Erro("--manter e --absorver precisam ser ideias diferentes")
    with Trava(TRAVA):
        antes = ler_vivo()
        i_manter = indice_por_id(antes, args.manter)
        i_absorver = indice_por_id(antes, args.absorver)
        sobrevivente = json.loads(antes[i_manter])
        absorvida = json.loads(antes[i_absorver])
        if absorvida.get("status") in ("colhida", "unificada"):
            raise Erro(f"'{args.absorver}' esta '{absorvida['status']}' — nao se absorve")

        sobrevivente.update(fundida)
        sobrevivente["status"] = sobrevivente.get("status") or "plantada"
        sobrevivente.setdefault("plantada_em", hoje())
        absorvidas = list(sobrevivente.get("absorveu") or [])
        if args.absorver not in absorvidas:
            absorvidas.append(args.absorver)
        sobrevivente["absorveu"] = absorvidas

        absorvida["status"] = "unificada"
        absorvida["unificada_em"] = hoje()
        absorvida["unificada_em_id"] = sobrevivente["id"]

        depois = list(antes)
        depois[i_manter] = serializar(sobrevivente)
        depois[i_absorver] = serializar(absorvida)
        print(f"unificando '{args.absorver}' (linha {i_absorver + 1}) "
              f"em '{sobrevivente['id']}' (linha {i_manter + 1})")
        gravar(antes, depois, {i_manter, i_absorver}, "unificar")


def data_do_git(alvo_id: str) -> str | None:
    """Data do commit mais antigo que introduziu este id no jsonl, ou None.

    Existe para o `reparar` nao ter que chutar `plantada_em`. A linha reparada
    nasceu num dia que nao e hoje; carimbar hoje seria inventar historia — que e
    o mesmo defeito do bug de UTC de 2026-08-08, so que silencioso, porque data
    plausivel nao dispara alarme nenhum. O git ja guarda a resposta.
    """
    try:
        r = subprocess.run(
            ["git", "log", "--reverse", "--format=%ad", "--date=short",
             "-S", f'"{alvo_id}"', "--", ALVO.name],
            cwd=RAIZ, capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    linhas = [l.strip() for l in r.stdout.splitlines() if l.strip()]
    return linhas[0] if linhas else None


def diagnosticar(obj: dict) -> dict[str, str]:
    """Campos de estado ausentes e de onde sairia o valor. So olha o que FALTA.

    Reparo nunca corrige valor errado — para isso existe `editar`, que deixa
    rastro de decisao. Reparo so preenche buraco de linha que entrou no arquivo
    sem passar por este script (a `design-so-no-chat-antes-do-worktree`, de
    2026-08-10, entrou sem `status` nem `plantada_em` e so apareceu no `conferir`).
    """
    faltando: dict[str, str] = {}
    if obj.get("status") not in STATUS_CONHECIDOS:
        if obj.get("unificada_em"):
            faltando["status"] = "unificada"
        elif obj.get("colhida_em") or obj.get("resultado"):
            faltando["status"] = "colhida"
        elif obj.get("colheita_iniciada_em"):
            faltando["status"] = "em-colheita"
        else:
            faltando["status"] = "plantada"
    if not obj.get("plantada_em"):
        faltando["plantada_em"] = "<git>"
    return faltando


def cmd_reparar(args) -> None:
    """Preenche campo de estado ausente em linha que entrou fora do script.

    Sem ele o unico conserto possivel era editar o jsonl a mao — exatamente o que
    este arquivo existe para impedir. O `editar` nao serve: `status` e
    `plantada_em` estao em CAMPOS_PROIBIDOS_NO_INPUT, e devem continuar, porque
    a proibicao e o que impede o modelo de digitar data.
    """
    if not args.id and not args.todas:
        raise Erro("diga --id <id> ou --todas (com --conferir, nada e gravado)")
    if args.plantada_em:
        if not args.id:
            raise Erro("--plantada-em so vale com --id, uma linha por vez")
        try:
            d = date.fromisoformat(args.plantada_em)
        except ValueError:
            raise Erro(f"--plantada-em '{args.plantada_em}' nao e data ISO (AAAA-MM-DD)")
        if d > date.today():
            raise Erro(f"--plantada-em {args.plantada_em} esta no futuro")

    with Trava(TRAVA):
        antes = ler_vivo()
        objs = parse_linhas(antes)
        indices = ([indice_por_id(antes, args.id)] if args.id
                   else [i for i, o in enumerate(objs) if diagnosticar(o)])
        if not indices:
            print("nada a reparar — nenhuma linha com campo de estado ausente.")
            return

        depois = list(antes)
        alvos: set[int] = set()
        pendentes: set[str] = set()
        for i in indices:
            obj = json.loads(antes[i])
            faltando = diagnosticar(obj)
            if not faltando:
                print(f"linha {i + 1} ({obj.get('id')}): nada ausente — nao mexo.")
                continue
            resolvido: dict[str, str] = {}
            for campo, valor in faltando.items():
                if valor != "<git>":
                    resolvido[campo] = valor
                    origem = "inferido do proprio registro"
                elif args.plantada_em:
                    resolvido[campo] = args.plantada_em
                    origem = "informado na linha de comando"
                elif (d := data_do_git(obj["id"])):
                    resolvido[campo] = d
                    origem = "data do commit que introduziu a linha"
                elif args.conferir:
                    # Em --conferir a pendencia se descreve; quem aborta e a
                    # gravacao. Dry-run que morre no primeiro buraco nao mostra
                    # os outros, e o comando existe justamente para mostrar.
                    pendentes.add(obj["id"])
                    print(f"  {obj.get('id')}.{campo} = ?  (o git nao sabe — "
                          f"precisa de --plantada-em AAAA-MM-DD)")
                    continue
                else:
                    raise Erro(
                        f"'{obj['id']}': o git nao sabe quando esta linha entrou "
                        f"(ainda nao commitada?). Nao vou carimbar hoje numa linha que nao "
                        f"nasceu hoje — passe --plantada-em AAAA-MM-DD com a data real."
                    )
                print(f"  {obj.get('id')}.{campo} = {resolvido[campo]}  ({origem})")
            if args.conferir:
                continue
            obj.update(resolvido)
            obj["reparada_em"] = hoje()
            obj["reparo"] = sorted(resolvido)
            depois[i] = serializar(obj)
            alvos.add(i)

        if args.conferir:
            print(f"\n--conferir: {len(indices)} linha(s) acima, nada gravado.")
            if pendentes:
                print(f"{len(pendentes)} sem data no git — o reparo real vai recusar "
                      f"ate receber --plantada-em: {', '.join(sorted(pendentes))}")
            return
        if not alvos:
            return
        print(f"reparando {len(alvos)} linha(s)")
        gravar(antes, depois, alvos, "reparar")


def cmd_listar(args) -> None:
    objs = parse_linhas(ler_vivo())
    hj = date.today()
    alvo_status = args.status
    itens = [o for o in objs if alvo_status == "todos" or o.get("status") == alvo_status]
    if args.tipo != "todos":
        itens = [o for o in itens if (o.get("tipo") or "ideia") == args.tipo]

    def idade(o):
        d = o.get("plantada_em")
        try:
            return (hj - date.fromisoformat(d)).days
        except (TypeError, ValueError):
            return None

    itens.sort(key=lambda o: o.get("plantada_em") or "", reverse=True)
    rotulo_tipo = "" if args.tipo == "todos" else f" ({args.tipo})"
    print(f"{len(itens)} {alvo_status}{rotulo_tipo}\n")
    for o in itens:
        d = idade(o)
        quando = "data invalida" if d is None else (
            "hoje" if d == 0 else f"ha {d} dia{'s' if d != 1 else ''}"
        )
        if d is not None and d < 0:
            quando = f"DATA NO FUTURO ({o.get('plantada_em')})"
        print(f"- {o.get('titulo')}")
        print(f"  {o.get('id')} | {quando} | {o.get('projeto')}")
    total = len(objs)
    colhidas = sum(1 for o in objs if o.get("status") == "colhida")
    print(f"\n{total} no total, {colhidas} colhidas.")


def cmd_conferir(_args) -> None:
    """Saude do arquivo. Pega, entre outras, a data no futuro que o bug de UTC
    produz — o relatorio de 2026-08-09 nasceu com nome de arquivo do dia seguinte."""
    linhas = ler_vivo()
    objs = parse_linhas(linhas)
    hj = date.today()
    problemas = []
    vistos = {}
    for i, o in enumerate(objs, 1):
        ident = o.get("id")
        if not ident:
            problemas.append(f"linha {i}: sem id")
        elif not RE_ID.match(ident):
            problemas.append(f"linha {i}: id '{ident}' nao e kebab-case")
        elif ident in vistos:
            problemas.append(f"linha {i}: id '{ident}' repetido (ja na linha {vistos[ident]})")
        else:
            vistos[ident] = i
        if o.get("status") not in STATUS_CONHECIDOS:
            problemas.append(f"linha {i}: status '{o.get('status')}' desconhecido")
        if (t := o.get("tipo")) is not None and t not in TIPOS_CONHECIDOS:
            problemas.append(f"linha {i}: tipo '{t}' desconhecido")
        for campo in ("plantada_em", "colhida_em", "unificada_em", "colheita_iniciada_em"):
            if not (v := o.get(campo)):
                continue
            try:
                if date.fromisoformat(v) > hj:
                    problemas.append(f"linha {i} ({ident}): {campo}={v} esta NO FUTURO (hoje e {hj})")
            except ValueError:
                problemas.append(f"linha {i} ({ident}): {campo}='{v}' nao e data ISO")
        if o.get("status") == "colhida" and not o.get("resultado"):
            problemas.append(f"linha {i} ({ident}): colhida sem resultado")
        for campo in CAMPOS_OBRIGATORIOS:
            if not o.get(campo):
                problemas.append(f"linha {i} ({ident}): campo obrigatorio '{campo}' vazio")

    print(f"{len(objs)} linhas, {len(vistos)} ids unicos")
    for s in STATUS_CONHECIDOS:
        print(f"  {s}: {sum(1 for o in objs if o.get('status') == s)}")
    if problemas:
        print(f"\n{len(problemas)} problema(s):")
        for p in problemas:
            print(f"  - {p}")
        raise Erro("conferencia falhou")
    print("\nsem problemas.")


def main() -> int:
    p = argparse.ArgumentParser(
        prog="ideias.py",
        description="Escrita segura no ideias.jsonl (trava, backup, atomico, conferido).",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("plantar", help="acrescenta uma ideia (JSON por stdin)").set_defaults(fn=cmd_plantar)

    c = sub.add_parser("colher", help="marca colhida (JSON com 'resultado' por stdin)")
    c.add_argument("--id", required=True)
    c.set_defaults(fn=cmd_colher)

    c = sub.add_parser("editar", help="corrige campos de ideia ainda aberta (JSON por stdin)")
    c.add_argument("--id", required=True)
    c.set_defaults(fn=cmd_editar)

    c = sub.add_parser("iniciar", help="plantada -> em-colheita")
    c.add_argument("--id", required=True)
    c.add_argument("--andamento", help="o que ja andou e o que falta (vai pro campo andamento)")
    c.set_defaults(fn=cmd_iniciar)

    c = sub.add_parser("unificar", help="funde duas ideias (JSON fundido por stdin)")
    c.add_argument("--manter", required=True)
    c.add_argument("--absorver", required=True)
    c.set_defaults(fn=cmd_unificar)

    c = sub.add_parser("reparar", help="preenche campo de estado ausente (linha gravada fora do script)")
    c.add_argument("--id", help="uma linha especifica")
    c.add_argument("--todas", action="store_true", help="toda linha com campo de estado ausente")
    c.add_argument("--conferir", action="store_true", help="mostra o que faria, nao grava")
    c.add_argument("--plantada-em", dest="plantada_em",
                   help="data real, so quando o git nao souber (AAAA-MM-DD)")
    c.set_defaults(fn=cmd_reparar)

    c = sub.add_parser("listar", help="lista por status e tipo")
    c.add_argument("--status", default="plantada", choices=[*STATUS_CONHECIDOS, "todos"])
    c.add_argument("--tipo", default="ideia", choices=[*TIPOS_CONHECIDOS, "todos"])
    c.set_defaults(fn=cmd_listar)

    sub.add_parser("conferir", help="valida o arquivo inteiro").set_defaults(fn=cmd_conferir)

    args = p.parse_args()
    try:
        args.fn(args)
    except Erro as e:
        print(f"erro: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
