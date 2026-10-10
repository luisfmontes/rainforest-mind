# Plano: Laço executor → revisor com teto no fluxo

Design: docs/rainforest/design/2026-10-10-laco-executor-revisor.md

## O que não pode quebrar
- `scripts/testa-teto-skills.sh` verde: `skills/revisar/SKILL.md` (16032 B) e `skills/executar/SKILL.md` (16370 B) ficam ≤ 16384 B — o laço mora em `skills/revisar/references/laco.md`, a skill só aponta.
- O contrato de veredito (hook `SubagentStop`, `TETO_TENTATIVAS`, `liberar`) não muda: o laço só lê o que ele grava.
- `hooks/testa-veredito-revisor.sh` verde (o `agents/revisor.md` ganha o marcador `[design]`, a última linha `VEREDITO:` não muda).

## Tarefas

### 1. `critica-do-revisor.cjs` e sua bateria [tipo: implementar]
atende: D6, D9
arquivos: `scripts/critica-do-revisor.cjs`, `scripts/testa-critica-do-revisor.sh`, `scripts/fixtures/critica-do-revisor/*`, `scripts/tempos-baterias.json`
depende de: nenhuma
paralela: nao
prova: `bash scripts/testa-critica-do-revisor.sh`
mutacao:
  arquivo: `scripts/critica-do-revisor.cjs`
  de: .filter((l) => !/^\s*VEREDITO:/i.test(l))
  para: .filter((l) => l === l)
  bateria: `bash scripts/testa-critica-do-revisor.sh`
  fixture: critica-sem-linha-de-veredito
pronto quando: com um estado de fluxo cujo `revisar.vereditos` tem um `reprovado` apontando para um transcrito real de revisor, `node scripts/critica-do-revisor.cjs --slug <slug>` imprime os achados sem a linha `VEREDITO:` e sai 0; com achado `[design]` sai 3; sem `reprovado` sai 4; com transcrito ausente sai 69 — provado por `bash scripts/testa-critica-do-revisor.sh` exercitando os quatro casos com `RFM_ESTADO_ROOT` numa caixa e saindo 0

### 2. Revisor marca `[design]` [tipo: docs]
atende: D7
arquivos: `agents/revisor.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: instrução ao agente; o efeito mecânico (exit 3) é provado na tarefa 1
pronto quando: com o `agents/revisor.md` que o harness carrega, a seção de saída manda prefixar com `[design]` o achado que contesta uma `D<n>` do design ou o plano, e a última linha continua sendo `VEREDITO:` — provado por `grep -c "\[design\]" agents/revisor.md` devolvendo 1 ou mais e `bash hooks/testa-veredito-revisor.sh` saindo 0

### 3. O laço escrito, e o ponteiro [tipo: docs]
atende: D1, D2, D3, D4, D5, D8
arquivos: `skills/revisar/references/laco.md`, `skills/revisar/SKILL.md`, `skills/executar/SKILL.md`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto normativo; o comportamento executável é o script da tarefa 1
pronto quando: com o `revisar` como a sessão o lê, o reprovado aponta para `references/laco.md`, que prescreve: rodar `critica-do-revisor.cjs`; exit 3 para e sobe ao usuário; exit 0 redespacha o executor com despacho novo (regra 11) e a saída colada literal; o teto é o `TETO_TENTATIVAS` do `estado.cjs`; e o `executar` aponta para o mesmo arquivo — provado por `grep -c "critica-do-revisor.cjs" skills/revisar/references/laco.md` ≥ 1, `grep -c "references/laco.md" skills/revisar/SKILL.md skills/executar/SKILL.md` ≥ 1 em cada, `grep -c "TETO_TENTATIVAS\|liberar" skills/revisar/references/laco.md` ≥ 1, e `bash scripts/testa-teto-skills.sh` saindo 0

### 4. Versão e nota [tipo: docs]
atende: D1
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: nota de versão
pronto quando: com a entrada nova do CHANGELOG, ela descreve o laço, o teto de 3 e a parada por `[design]` — provado por `awk '/^## /{n++} n==1' CHANGELOG.md | grep -c "design\]"` ≥ 1 e versão igual nos dois `plugin.json` e no badge do README
