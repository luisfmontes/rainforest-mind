"""scripts/validar-colhidas.py — confere cada ideia colhida contra o artefato real.

Uso: python scripts/validar-colhidas.py

Colher grava um `resultado` em prosa, e prosa nao e evidencia — e a regra 12 aplicada
ao proprio acervo de ideias. Este script pergunta, para cada colhida: o que o resultado
afirma que existe, existe hoje?

REGRA DE MANUTENCAO: colher uma ideia obriga a acrescentar a checagem dela no dict
CHECKS. Colhida sem checagem sai marcada `???` de proposito — o script nao finge
cobertura que nao tem.

Duas licoes ficaram no codigo, das falhas da primeira rodada (2026-08-09), e as duas
eram do VALIDADOR, nao das colheitas: regex que nao cruzava quebra de linha, e caminho
que envelheceu quando o config dir mudou de lugar. Alarme falso e pior que trava
nenhuma — antes de acusar uma colheita, confira se o erro e seu.

Confere cada ideia colhida contra o artefato que o campo `resultado` afirma existir.

Colhida cujo resultado nao tem artefato e o mesmo defeito dos relatorios de hoje:
relato aceito sem evidencia. Cada checagem abaixo foi derivada lendo o `resultado`
da propria ideia — o teste e "isso que ele diz que existe, existe?".
"""
import json
import os
import re
import subprocess
from pathlib import Path

R = Path(r"C:\Projetos\rainforest-mind")


def ler(rel):
    p = R / rel
    for enc in ("utf-8", "cp1252"):
        try:
            return p.read_text(encoding=enc)
        except (FileNotFoundError, UnicodeDecodeError):
            if not p.exists():
                return None
    return None


def existe(rel):
    return (R / rel).exists()


def contem(rel, *padroes):
    t = ler(rel)
    if t is None:
        return None  # arquivo ausente
    return all(re.search(p, t, re.I | re.S) for p in padroes)


def commit_existe(h):
    r = subprocess.run(["git", "-C", str(R), "cat-file", "-t", h],
                       capture_output=True, text=True)
    return r.returncode == 0 and r.stdout.strip() == "commit"


SKILL = "skills/rainforest-mind/SKILL.md"
EXEC = "agents/executor.md"

# id -> (descricao do que o resultado afirma, funcao que confere)
CHECKS = {
    "comando-tive-uma-ideia":
        ("commands/ideia.md existe", lambda: existe("commands/ideia.md")),
    "parametrizar-caminhos-rainforest":
        ("RFM_ROOT nos 4 arquivos + CLAUDE_CONFIG_DIR + RFM_BRIDGE_LAUNCHER",
         lambda: all([contem("hooks/foco-session-start.cjs", "RFM_ROOT", "CLAUDE_CONFIG_DIR"),
                      contem("hooks/heartbeat.cjs", "RFM_ROOT"),
                      contem("vigias/run-vigia.ps1", "RFM_BRIDGE_LAUNCHER|RFM_CLAUDE_EXE")])),
    "verificacao-cruzada-build-multiplataforma":
        ("executor.md item (e) fala de build cruzado",
         # \s+ e nao espaco: no arquivo "build" fecha uma linha e "cruzado" abre a
         # seguinte. A versao anterior deste check acusou FALHA num resultado honrado.
         lambda: contem(EXEC, r"build\s+cruzado")),
    "vigias-dependem-do-bridge-whatsapp":
        ("run-vigia.ps1 le WHATSAPP_API_BASE_URL",
         lambda: contem("vigias/run-vigia.ps1", "WHATSAPP_API_BASE_URL")),
    "regra-bloqueada-em-silencio":
        ("regra 14 existe no SKILL.md",
         lambda: contem(SKILL, r"14\.")),
    "worktree-nasce-do-head-da-abertura":
        ("ff-only autorizado no SKILL.md e no executor.md",
         lambda: contem(SKILL, "ff-only") and contem(EXEC, "ff-only")),
    "agente-instala-software-no-sistema":
        ("regra 15 no SKILL.md + linha no executor.md",
         lambda: contem(SKILL, r"15\.") and contem(EXEC, "Nunca altere o ambiente")),
    "radar-de-foco-cobra-em-tempo-pessoal":
        ("natureza [trabalho]/[pessoal] no SKILL.md e no FOCO.md",
         lambda: contem(SKILL, r"\[trabalho\]") and contem("FOCO.md", r"\[trabalho\]")),
    "check-de-ferramenta-nao-e-evidencia":
        ("regra 12 fala de saida de ferramenta",
         lambda: contem(SKILL, "ferramenta")),
    "eliminar-a-entrega-antes-de-culpar-o-modelo":
        ("run-vigia.ps1 loga tamanho do prompt + vigias/_comum.md existe",
         lambda: existe("vigias/_comum.md") and contem("vigias/run-vigia.ps1", "prompt")),
    "auditar-relatorio-de-agente-antes-de-concluir":
        ("SKILL.md fala de conferir citacao arquivo:linha",
         lambda: contem(SKILL, "cita")),
    "timestamp-de-log-e-utc-nao-local":
        ("SKILL.md: relogio local, nunca timestamp de log",
         lambda: contem(SKILL, "UTC")),
    "aviso-de-bloqueio-chega-tarde-demais":
        ("commit 6781d2a existe",
         lambda: commit_existe("6781d2a")),
    "design-nao-nasce-na-main":
        ("commit 6b3cc31 existe + regra 11 fala de branch de trabalho",
         lambda: commit_existe("6b3cc31") and contem(SKILL, "branch de trabalho")),
    "gate-do-p1-e-hook-nao-texto":
        ("scripts/conferir-entrega.py existe",
         lambda: existe("scripts/conferir-entrega.py")),
    "carimbo-de-data-tambem-le-utc":
        ("SKILL.md regra 8 fala de UTC/Z",
         lambda: contem(SKILL, "UTC")),
    "incidente-sai-da-injecao-fica-no-arquivo":
        ("hook filtra linhas iniciadas por '>'",
         lambda: contem("hooks/lib/contexto-sessao.cjs", r"CITACAO")),
    "subagente-relato-nao-e-evidencia":
        ("commit b3df0f6 existe",
         lambda: commit_existe("b3df0f6")),
    "skill-controle-horas":
        ("plugin apontamento-horas instalado",
         lambda: any(Path(os.path.expandvars(r"%USERPROFILE%")).joinpath(c, "plugins", "cache", "marketplace-interno").exists()
                     for c in (".claude", ".claude-personal"))),
    "segundo-cerebro":
        ("vault C:\\Projetos\\segundo-cerebro existe",
         lambda: Path(r"C:\Projetos\segundo-cerebro").exists()),
    "livros-psicologia-para-skill":
        ("15+ livros destilados no vault",
         lambda: len(list(Path(r"C:\Projetos\segundo-cerebro\livros").glob("*"))) >= 15
         if Path(r"C:\Projetos\segundo-cerebro\livros").exists() else False),
    "jornada-medida-no-transcript-nao-em-carimbo":
        ("scripts/jornada.py existe + regra 8 proibe carimbo de commit",
         lambda: existe("scripts/jornada.py")
         and contem(SKILL, r"nunca\s+se\s+infere\s+de\s+carimbo")),
    "executor-reincidiu-depois-da-correcao-do-isolamento":
        ("conferir-entrega.py + gate-worktree.cjs + itens (j) e (k) no executor.md",
         lambda: existe("scripts/conferir-entrega.py") and existe("hooks/gate-worktree.cjs")
         and contem(EXEC, r"\(j\)") and contem(EXEC, r"\(k\)")),
    "gate-worktree-barra-quem-esta-no-lugar-certo":
        ("gate usa alvosBash (nao ev.cwd) + bateria tem o caso do bug",
         lambda: contem("hooks/gate-worktree.cjs", r"function alvosBash")
         and contem("hooks/testa-gate-worktree.sh", r"O BUG: tem que PASSAR")),
    "batedor-vigia-de-repos-ancorado":
        ("prompt + apurador com o nome que o runner procura + livro + tarefa agendada",
         lambda: existe("vigias/batedor-repos.md") and existe("vigias/dados-batedor-repos.js")
         and existe("vigias/livro-de-repos.md")
         and subprocess.run(["schtasks", "/query", "/tn", r"\ClaudeVigias\batedor-repos"],
                            capture_output=True).returncode == 0),
    "escala-de-confianca-em-toda-afirmacao":
        ("os tres agentes exigem CONFIRMADO/INFERIDO/LACUNA",
         lambda: all(contem(f"agents/{a}.md", "CONFIRMADO", "INFERIDO", "LACUNA")
                     for a in ("executor", "revisor", "tester"))),
    "repo-privado-whatsapp-standards":
        # O caminho do resultado envelheceu: o config dir virou .claude-personal em
        # 2026-08-08 e a skill virou repo proprio (luisfmontes/message-standards), em
        # vez de a pasta skills inteira ser o repo.
        ("skills/message-standards e repo git",
         lambda: Path(os.path.expandvars(
             r"%USERPROFILE%\.claude-personal\skills\message-standards\.git")).exists()),
}

SEM_ARTEFATO = {
    "contato-psicologa-whatsapp": "informacao recebida, nada a construir — nao ha o que conferir",
    "gmail-enviar-e-anexos": "MCP externo, fora do repo — conferir exige rodar o Gmail",
    "condensar-a-skill-e-medir-pt-vs-en": "numeros de tamanho ja envelheceram (o arquivo cresceu depois)",
}

colhidas = []
for linha in (R / "ideias.jsonl").read_text(encoding="utf-8").splitlines():
    if not linha.strip():
        continue
    d = json.loads(linha)
    if d.get("status") == "colhida":
        colhidas.append(d["id"])

ok = falhou = pulado = semcheck = 0
print(f"{len(colhidas)} colhidas\n")

for cid in colhidas:
    if cid in SEM_ARTEFATO:
        print(f"  --   {cid}\n       {SEM_ARTEFATO[cid]}")
        pulado += 1
        continue
    if cid not in CHECKS:
        print(f"  ???  {cid}  (sem checagem escrita)")
        semcheck += 1
        continue
    desc, fn = CHECKS[cid]
    try:
        r = fn()
    except Exception as e:
        r = None
        desc += f"  [erro: {e}]"
    if r:
        print(f"  ok   {cid}")
        ok += 1
    else:
        print(f"  FALHA {cid}\n        afirmava: {desc}")
        falhou += 1

print(f"\n{'-'*50}")
print(f"confirmadas: {ok}   nao confirmadas: {falhou}   "
      f"sem artefato conferivel: {pulado}   sem checagem: {semcheck}")
