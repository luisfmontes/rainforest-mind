# Plano: Veredito do revisor fora da última linha exata

Design: docs/rainforest/design/2026-09-25-veredito-fora-da-linha.md

## O que não pode quebrar
- Veredito na última linha exata grava como hoje, sem bloqueio nem turno extra.
- Revisão avulsa (sem `Slug:`) e agente que não é revisor: o hook sai 0 sem gravar e sem bloquear, como hoje.
- Com `contrato-veredito` desligado, o hook não grava nem bloqueia.
- `estado.cjs veredito --transcrito` usa a mesma extração: um transcrito que o hook aceita, o `estado.cjs` também aceita (sem divergência entre os dois).
- `skills/revisar/SKILL.md` está a 11 B do teto (`testa-teto-skills.sh`): nada entra nela sem sair outra coisa.
- Nenhuma bateria ou teste ao vivo escreve em `~/.claude*` ou `~/.rainforest` reais.

## Tarefas

### 1. Confirmar ao vivo o bloqueio do `SubagentStop` [tipo: pesquisar]
atende: D1, D3
arquivos: `docs/rainforest/pesquisas/2026-09-25-subagentstop-block.md`, `hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa; o artefato é a captura do comportamento real do harness, não código.
pronto quando: numa sessão headless (`claude -p`) isolada da config do usuário (`--setting-sources` sem `user`, ou equivalente conferido no `claude --help`, para o plugin instalado NÃO carregar), com um hook `SubagentStop` de teste que bloqueia a primeira parada com `{"decision":"block","reason":"..."}` e libera a segunda: o doc cola (a) o transcrito do subagente mostrando que ele continuou depois do bloqueio e que a mensagem final seguiu o `reason`, (b) o payload real da segunda parada, com `stop_hook_active: true` (salvo como fixture), e (c) o que acontece se o hook bloquear também a segunda parada (o harness corta, ou laça). Se o isolamento não for possível sem carregar o plugin instalado, o doc diz isso e para antes de rodar.

### 2. Extração aceita marcação em volta da linha [tipo: implementar]
atende: D2, D4
arquivos: `scripts/lib/extrair-veredito.cjs`, `scripts/testa-segunda-opiniao.sh`, `hooks/testa-veredito-revisor.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/lib/extrair-veredito.cjs`
  de: `.replace(/^[*_`]+|[*_`]+$/g, '')`
  para: `.replace(/^$/g, '')`
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: `testa-veredito-revisor.sh, caso "veredito em negrito na ultima linha grava ok"`
pronto quando: com um `last_assistant_message` real terminando em `**VEREDITO: reprovado**` (o formato visto na revisão de 2026-09-24), o hook grava `reprovado`; com `__VEREDITO: ok__` e `` `VEREDITO: ok` ``, grava `ok`; com `**VEREDITO: reprovado — 4 bloqueantes**` (texto depois do veredito dentro da marcação) NÃO grava `reprovado` — é linha fora do vocabulário; o `segunda-opiniao.cjs` aceita `**concordo**` — provado por `bash hooks/testa-veredito-revisor.sh` e `bash scripts/testa-segunda-opiniao.sh` nesses casos.

### 3. Hook devolve a vez ao revisor na primeira parada inválida [tipo: implementar]
atende: D1, D3, D5
arquivos: `hooks/veredito-revisor.cjs`, `hooks/testa-veredito-revisor.sh`, `hooks/fixtures/veredito-revisor/payload-subagentstop-segunda-parada.json`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: `if (veredito === 'invalido' && payload.stop_hook_active !== true) {`
  para: `if (false) {`
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: `testa-veredito-revisor.sh, caso "primeira parada sem veredito valido bloqueia com o motivo e nao grava"`
pronto quando: com o payload real de `SubagentStop` de um revisor com `Slug:` cuja última linha não é veredito (ex.: termina em "Premissas aceitas sem conferir: …"), o hook imprime no stdout `{"decision":"block","reason":…}` com o motivo citando a linha exata esperada, sai 0 e NÃO grava veredito; o mesmo payload com `stop_hook_active: true` (fixture da tarefa 1) grava `invalido` e não bloqueia; veredito válido não bloqueia; revisão sem `Slug:`, agente que não é revisor e `contrato-veredito` desligado não bloqueiam — provado por `bash hooks/testa-veredito-revisor.sh` nesses casos.

### 4. Documentar a segunda chance [tipo: docs]
atende: D1, D2, D3
arquivos: `agents/revisor.md`, `skills/revisar/SKILL.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: doc; a falsificação é a coerência com D1–D3 e com o comportamento real das tarefas 2 e 3.
pronto quando: a seção do `agents/revisor.md` que pede a última linha diz que negrito em volta é aceito (D2) e que, fora disso, o hook devolve a vez uma vez pedindo a linha, e na segunda o veredito fica `invalido` (D1, D3) — conferido lendo contra `hooks/veredito-revisor.cjs` e `scripts/lib/extrair-veredito.cjs`; em `skills/revisar/SKILL.md` só a frase "sem negrito" vira "negrito aceito", no mesmo tamanho (a skill está a 11 B do teto).

### 5. Versão 1.23.12 [tipo: configurar]
atende: D1
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 4
paralela: nao
mutacao: n/a
  motivo: bump de versão, sem comportamento a inverter.
pronto quando: `node scripts/conferir-versao.cjs` aceita (versão maior que a da `origin/main`, hoje `1.23.11`) e `bash scripts/testa-versao.sh` confirma `plugin.json` e selo do README iguais. Última tarefa do `executar`, para o `revisar` cobrir o diff inteiro.
