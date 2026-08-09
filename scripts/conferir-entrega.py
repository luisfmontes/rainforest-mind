#!/usr/bin/env python3
"""Confere a entrega de um subagente. Roda na JANELA PRINCIPAL, depois da entrega.

O P1 do relatorio de 2026-08-08 (relatorios/2026-08-08-executor-reincidencia-isolamento.md):

  "Enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela
   deveria travar, ela nao trava nada."

Naquele dia o agente RODOU `git rev-parse --show-toplevel`, recebeu o diretorio
principal do repo — que era a condicao de parada —, transcreveu a condicao
corretamente e escreveu um OK do lado. Na mesma entrega colou o pai do commit,
viu que divergia da base e se absolveu com "diferenca nao afeta a funcionalidade",
quando era justamente o commit que fazia o criterio de aceite passar.

Nenhuma regra de texto alcanca esse modo de falha, porque o texto ja estava la e
foi lido. O que alcanca e o veredito sair das maos de quem executou: a janela
principal roda isto ao receber a entrega, e o exit code nao se argumenta.

As seis falhas dos dois relatorios e onde cada uma morre aqui:

  worktree ignorado, trabalho no dir principal ....... checagem 1
  commit sobre base errada, auto-absolvido ........... checagem 2
  sujeira deixada no worktree ........................ checagem 3
  arquivo rastreado apagado como dano colateral (N3) . checagem 3
  mexeu no diretorio principal do Luis (N1) .......... checagem 4
  stash/pop movendo o HEAD do Luis (N1) .............. checagem 5

Cada checagem imprime o comando literal e a saida CRUA antes do veredito: quem
ler o relatorio confere a conclusao contra a evidencia, sem confiar na conclusao.

Uso tipico, com o que a janela principal ja sabia antes de despachar:

  python scripts/conferir-entrega.py \
      --worktree C:/repo/.worktrees/agent-abc \
      --base 61be664 \
      --head-antes $(git -C C:/repo rev-parse HEAD)

Exit 0 so quando tudo passa.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


class Conferencia:
    def __init__(self) -> None:
        self.falhas: list[str] = []
        self.avisos: list[str] = []
        self.n = 0

    # -- execucao --------------------------------------------------------
    def git(self, dir_: str, *args: str) -> tuple[int, str]:
        try:
            p = subprocess.run(
                ["git", "-C", str(dir_), *args],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
        except FileNotFoundError:
            return 127, "git nao encontrado no PATH"
        return p.returncode, (p.stdout + p.stderr).strip()

    # -- relato ----------------------------------------------------------
    def abre(self, titulo: str) -> None:
        self.n += 1
        print(f"\n{self.n}. {titulo}")

    def mostra(self, dir_: str, *args: str) -> tuple[int, str]:
        rc, out = self.git(dir_, *args)
        print(f"   $ git -C {dir_} {' '.join(args)}")
        for linha in (out or "(vazio)").splitlines() or ["(vazio)"]:
            print(f"     {linha}")
        return rc, out

    def ok(self, msg: str) -> None:
        print(f"   OK   {msg}")

    def falha(self, msg: str) -> None:
        print(f"   FALHA  {msg}")
        self.falhas.append(f"{self.n}. {msg}")

    def aviso(self, msg: str) -> None:
        print(f"   aviso  {msg}")
        self.avisos.append(f"{self.n}. {msg}")


def norm(p: str) -> str:
    """Compara caminho sem tropecar em barra invertida, maiuscula e link."""
    try:
        return str(Path(p).resolve()).replace("\\", "/").rstrip("/").lower()
    except OSError:
        return p.replace("\\", "/").rstrip("/").lower()


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="conferir-entrega.py",
        description="Confere a entrega de um subagente na janela principal (P1 do relatorio 2).",
    )
    ap.add_argument("--worktree", required=True, help="o worktree que o agente RECEBEU no briefing")
    ap.add_argument("--base", help="hash da base que o commit dele devia ter (o que foi no briefing)")
    ap.add_argument("--commit", default="HEAD", help="commit entregue (default: HEAD do worktree)")
    ap.add_argument("--repo-principal", help="default: deduzido do git-common-dir do worktree")
    ap.add_argument("--head-antes", help="HEAD do repo principal ANTES do despacho, para pegar HEAD movido")
    ap.add_argument("--permite-sujeira", action="store_true",
                    help="nao falhar por working tree suja no worktree (raro; justifique)")
    a = ap.parse_args()

    c = Conferencia()
    wt = a.worktree

    if not Path(wt).is_dir():
        print(f"erro: worktree '{wt}' nao existe", file=sys.stderr)
        return 2

    # ------------------------------------------------------------------
    c.abre("Onde ele mexeu — o worktree e mesmo um worktree?")
    rc, top = c.mostra(wt, "rev-parse", "--show-toplevel")
    if rc != 0:
        c.falha("nao e repositorio git")
        top = ""
    _, gitdir = c.mostra(wt, "rev-parse", "--git-dir")
    _, common = c.git(wt, "rev-parse", "--git-common-dir")

    principal = a.repo_principal
    if not principal and common:
        p = Path(common)
        if not p.is_absolute():
            p = Path(wt) / p
        principal = str(p.resolve().parent)

    if top and norm(top) != norm(wt):
        c.falha(f"o toplevel ({top}) nao e o worktree do briefing ({wt})")
    elif top:
        c.ok("o toplevel bate com o worktree do briefing")

    if "worktrees" not in gitdir.replace("\\", "/"):
        c.falha(
            f"o git-dir e '{gitdir}' — sem 'worktrees' no meio isto NAO e worktree linkado, "
            "e o agente trabalhou no repo principal. Foi esta a falha de 2026-08-08."
        )
    else:
        c.ok("git-dir aponta para worktree linkado")

    if principal and top and norm(principal) == norm(top):
        c.falha(f"worktree e repo principal sao o mesmo lugar ({principal})")

    # ------------------------------------------------------------------
    c.abre("De onde ele partiu — a base do commit entregue")
    rc, linha = c.mostra(wt, "log", "--format=%H %P", "-1", a.commit)
    if rc != 0:
        c.falha(f"commit '{a.commit}' nao resolve no worktree")
    elif a.base:
        partes = linha.split()
        entregue, pais = partes[0], partes[1:]
        rc_anc, _ = c.git(wt, "merge-base", "--is-ancestor", a.base, entregue)
        pai_direto = any(p.startswith(a.base) or a.base.startswith(p) for p in pais)
        if pai_direto:
            c.ok(f"a base {a.base} e pai direto do commit entregue")
        elif rc_anc == 0:
            c.aviso(f"a base {a.base} nao e pai direto, mas e ancestral — houve commit no meio")
        else:
            c.falha(
                f"a base {a.base} NAO esta na historia de {entregue[:12]} — o trabalho saiu de outro "
                "lugar. 'Nao afeta a funcionalidade' e conclusao da janela principal, nunca do agente."
            )
    else:
        c.aviso("sem --base para conferir; o briefing devia ter fixado uma")

    # ------------------------------------------------------------------
    c.abre("O que ficou solto no worktree")
    _, st = c.mostra(wt, "status", "--porcelain")
    apagados = [l for l in st.splitlines() if l[:2].strip() == "D" or l[:2] == " D"]
    if apagados:
        c.falha(f"{len(apagados)} arquivo(s) RASTREADO(S) apagado(s) — dano colateral (falha N3): "
                + ", ".join(l[3:] for l in apagados[:5]))
    if st and not a.permite_sujeira:
        c.falha(f"{len(st.splitlines())} entrada(s) nao commitada(s) — a entrega nao esta no commit")
    elif st:
        c.aviso(f"{len(st.splitlines())} entrada(s) nao commitada(s), dispensado por --permite-sujeira")
    else:
        c.ok("worktree limpo, tudo o que ele fez esta no commit")

    # ------------------------------------------------------------------
    if principal and Path(principal).is_dir() and norm(principal) != norm(wt):
        c.abre(f"O repo principal foi tocado? ({principal})")
        _, stp = c.mostra(principal, "status", "--porcelain")
        if stp:
            c.falha(
                f"{len(stp.splitlines())} alteracao(oes) no diretorio principal do Luis — o agente "
                "devia estar isolado no worktree. Foi a falha N1 de 2026-08-08."
            )
        else:
            c.ok("diretorio principal intacto")

        c.abre("O HEAD do repo principal se mexeu?")
        _, head_agora = c.mostra(principal, "rev-parse", "HEAD")
        if not a.head_antes:
            c.aviso("sem --head-antes; registre o HEAD antes de despachar para esta checagem valer")
        elif not head_agora.startswith(a.head_antes) and not a.head_antes.startswith(head_agora):
            c.falha(
                f"o HEAD do repo principal era {a.head_antes} e virou {head_agora[:12]} — algo moveu "
                "o HEAD do Luis (stash/pop, checkout). Falha N1 de 2026-08-08."
            )
        else:
            c.ok("HEAD do repo principal inalterado")
    else:
        c.abre("Repo principal")
        c.aviso("nao identifiquei um repo principal distinto do worktree — checagens 4 e 5 puladas")

    # ------------------------------------------------------------------
    print("\n" + "=" * 66)
    if c.falhas:
        print(f"REPROVADO — {len(c.falhas)} falha(s):")
        for f in c.falhas:
            print(f"  - {f}")
        print("\nNao integre. Se alguma falha for aceitavel, a dispensa e sua, por escrito,")
        print("nesta janela — nunca do agente que produziu a entrega.")
        return 1
    if c.avisos:
        print(f"APROVADO com {len(c.avisos)} aviso(s):")
        for w in c.avisos:
            print(f"  - {w}")
        return 0
    print("APROVADO — as 5 checagens passaram.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
