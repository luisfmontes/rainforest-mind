# Plano: Subagente preso por comando em segundo plano

Design: docs/rainforest/design/2026-09-25-busca-na-raiz.md

## O que não pode quebrar
- A janela principal (payload sem `agent_id`) roda qualquer `find`, como hoje.
- `find` em caminho que não é raiz de disco (`find . -name`, `find /c/Projetos/x -name`, `find "$SB" ...`) passa, dentro ou fora de subagente.
- Comando que só cita `find` em texto (`grep "find /" arquivo`, `echo find /`) passa.
- Payload ilegível, vazio ou de outra ferramenta: sai 0 sem negar, como os gates irmãos.
- A bateria não escreve em `~/.rainforest` nem em `~/.claude*` reais.

## Tarefas

### 1. Hook nega `find` na raiz dentro de subagente [tipo: implementar]
atende: D1, D2, D3
arquivos: `hooks/gate-busca-raiz.cjs`, `hooks/testa-gate-busca-raiz.cjs`, `hooks/testa-gate-busca-raiz.sh`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `hooks/fixtures/busca-raiz/payload-bash-subagente.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-busca-raiz.cjs`
  de: `if (!Object.prototype.hasOwnProperty.call(payload, "agent_id")) process.exit(0);`
  para: `if (true) process.exit(0);`
  bateria: `node hooks/testa-gate-busca-raiz.cjs`
  fixture: `testa-gate-busca-raiz.cjs, caso "subagente: find / -iname nega com o caminho conhecido na mensagem"`
pronto quando: com o payload de `PreToolUse` de `Bash` de subagente (forma da captura real de 2026-09-24, `hooks/fixtures/portaria-folha/payload-de-subagente.json`, trocando só `tool_name` e `tool_input`) e os comandos reais dos incidentes (`find / -iname accounts.json 2>/dev/null; cat ...`, `find / -maxdepth 6 -iname "payload-ok.json"`, `find / -maxdepth 2 -iname "tmp"`), o hook sai 2 com uma mensagem que diz por que (preso em segundo plano) e onde procurar; o mesmo comando sem `agent_id` sai 0; `find /c/Projetos/rainforest-mind -iname x`, `find . -name y` e `grep "find /" z` saem 0 em subagente; `/c`, `/c/`, `C:/`, `C:\`, com aspas, e `find` depois de `;`, `&&` ou `|` negam; com `"busca-na-raiz": false` no `.rainforest/config.json` do projeto sai 0 — provado por `node hooks/testa-gate-busca-raiz.cjs` nesses casos, rodando o hook como processo real, e o hook registrado em `hooks/hooks.json` sob `PreToolUse` com matcher `Bash`.

### 2. Linha do perfil: timeout explícito e nada vivo no fim [tipo: docs]
atende: D4
arquivos: `referencias/perfil-de-trabalho.md`, `agents/arqueologo.md`, `agents/auditor-de-seguranca.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/executor.md`, `agents/planejador.md`, `agents/resolvedor-de-build.md`, `agents/revisor.md`, `agents/tester.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de system prompt; a falsificação é a coerência com o comportamento do harness (2 min de padrão, teto de 600000 no `timeout` do Bash) e o `perfil.cjs --conferir` batendo nos nove agentes.
pronto quando: a linha nova no bloco do perfil diz que comando que pode passar de 2 minutos leva `timeout` explícito (até 600000) na chamada do Bash, em vez de ir para segundo plano, e que o agente não entrega a resposta final com comando seu ainda rodando; a tabela de procedência cita a medição de 2026-09-25 (34 de 113); `node scripts/perfil.cjs --conferir` sai 0 depois do `--aplicar` e `bash scripts/testa-perfil.sh` passa.

### 3. Versão 1.23.14 [tipo: configurar]
atende: D3
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: bump de versão, sem comportamento a inverter.
pronto quando: `node scripts/conferir-versao.cjs` aceita (maior que a `origin/main`, hoje `1.23.13`) e `bash scripts/testa-versao.sh` confirma `plugin.json` e selo do README iguais.
