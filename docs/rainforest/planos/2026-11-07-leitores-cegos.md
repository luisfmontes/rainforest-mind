# Plano: leitor cego do plano e diagnóstico cego no depurar

Design: docs/rainforest/design/2026-11-07-leitores-cegos.md

## O que não pode quebrar
- `skills/plano/SKILL.md` e `skills/depurar/SKILL.md` ficam abaixo de 500 linhas e 16.384 bytes (`bash scripts/testa-teto-skills.sh`).
- O `agents/depurador.md` continua sem a ferramenta Agent (`disallowedTools: Agent`) e com o bloco `perfil-de-trabalho` intacto.
- O briefing do leitor cego não leva a linha `Slug:`. Hoje isso não grava nada, porque o hook `veredito-revisor.cjs` filtra pelo tipo `revisor`, mas a linha não deve existir para não virar veredito do `revisar` se o agente mudar.

## Tarefas

### 1. Leitor cego no fechamento do plano [tipo: docs]
atende: D1, D2, D3, D4, D8, D9
arquivos: `skills/plano/references/leitor-cego.md`, `skills/plano/SKILL.md`
depende de: nenhuma
mutacao: n/a
  motivo: texto de skill, sem comportamento executável a inverter. A falsificação é rodar o briefing de verdade (pronto quando).
pronto quando: com o briefing literal de `skills/plano/references/leitor-cego.md` preenchido com o design e o plano deste fluxo e despachado num `general-purpose` com `model: sonnet`, o agente devolve achados nos três graus do D4 (bloqueante, maior, menor), cada um com a tarefa afetada, sem propor código e sem editar arquivo. Isso é provado pela saída colada do agente e por `git -C <worktree> status --short` vazio depois do despacho. O `## Fechar` do `skills/plano/SKILL.md` diz quando rodar (D1), aponta para a referência e manda corrigir bloqueante e maior antes do `marcar ok` (D4).

### 2. Diagnóstico cego na Fase 3 do depurar [tipo: docs]
atende: D5, D6, D7, D8, D9
arquivos: `skills/depurar/references/diagnostico-cego.md`, `skills/depurar/SKILL.md`, `agents/depurador.md`
depende de: nenhuma
mutacao: n/a
  motivo: texto de skill e de agente, sem comportamento executável a inverter. A falsificação é rodar o prompt contra um defeito real com causa conhecida (pronto quando).
pronto quando: com o prompt literal de `skills/depurar/references/diagnostico-cego.md` preenchido só com o sintoma e o repro do defeito #648 e despachado num `general-purpose` com `model: sonnet`, num worktree descartável no commit `32be77c2` (2.5.0, antes do conserto), a causa candidata nº 1 cita a regra de topo JS de `hooks/lib/definicoes.cjs` (linha 33 na base), que é a linha que o conserto do #651 trocou para aceitar a anotação de tipo. (Corrigido no executar: a versão anterior deste critério dizia `scripts/lib/complexidade.cjs` sem ter conferido o diff do #651; `git show 3e344d23 -- hooks/lib/definicoes.cjs` mostra a troca.) Cada candidata traz `arquivo:linha` e uma checagem que prova ou derruba a causa, e a resposta não propõe conserto. O sintoma é: um `.tsx` com `const Painel: React.FC = () => { ... }` não aparece na saída de `node scripts/catalogo-funcoes.cjs complexas`. Isso é provado pela saída colada do agente. A Fase 3 do `skills/depurar/SKILL.md` manda despachar em background antes de escrever as hipóteses (D5) e desempatar por checagem (D6). O `agents/depurador.md` manda pular o passo e avisar no relato quando não houver Agent (D7).

A saída literal da prova da tarefa 2 e o placar com o resumo da tarefa 1 estão em `relatorios/2026-11-07-provas-leitores-cegos.md`. Na tarefa 1, o `git status --short` não saiu vazio: a única alteração era da janela principal no plano, feita durante a leitura.

Prova da tarefa 1, rodada no executar: o leitor cego leu este plano e devolveu 4 bloqueantes, 5 maiores e 3 menores, quase todos "o executor haiku não tem o texto a escrever nem pode despachar agente". Os achados não foram aplicados por dois motivos. As tarefas foram escritas pela janela principal, conforme a memória "manifesto sem agente sonnet de escrita". E este plano é só de docs, caso em que D1 dispensa o leitor. O achado "README sem 2.5.1" foi leitura concorrente com o bump, e isso virou a linha "commite o plano antes do despacho" na referência.

### 3. Versão 2.6.0 com README e CHANGELOG [tipo: docs]
atende: D10
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2
mutacao: n/a
  motivo: subida de versão e notas, sem comportamento a inverter.
pronto quando: com a árvore do fluxo, `node scripts/conferir-versao.cjs` aceita a 2.6.0 nos dois `plugin.json`, e a entrada 2.6.0 do `CHANGELOG.md` descreve os dois passos novos com o momento em que cada um roda, coerente com D1 e D5. Isso é provado pela saída do `conferir-versao.cjs` e pela leitura da entrada contra o design.
