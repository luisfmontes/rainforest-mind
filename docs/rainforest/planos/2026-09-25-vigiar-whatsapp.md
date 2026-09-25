# Plano: Skill vigiar para conversa de WhatsApp

Design: docs/rainforest/design/2026-09-25-vigiar-whatsapp.md

## O que não pode quebrar
- `watch_chat.py` sem a flag nova de status se comporta byte a byte como hoje: o `commands/vigiar.md` do fork e quem já o usa na sessão do `inovacao` não quebram.
- Nenhuma leitura grava no `messages.db` da bridge (continua `mode=ro`).
- Nenhuma tarefa derruba, reinicia ou reconfigura as bridges reais (3005 e 3006) — regra 15. Para testar a bridge fora do ar, usar um servidor falso em porta livre.
- Nenhuma fixture versionada leva JID, telefone ou nome real: o payload real do `/api/status` tem o JID da conta, e ele sai redigido.
- Bateria nenhuma escreve em `~/.claude*`, `~/.rainforest` ou `~/.whatsapp-mcp` reais: `HOME`/`USERPROFILE` e config em caixa de areia.
- A chave `integracao-whatsapp-mcp` continua desligada por padrão, e o `/saude` segue conferindo só o que foi declarado.

## Sobre as tarefas no repo `whatsapp-mcp`
As tarefas 1 e 2 são no repositório `C:/Projetos/whatsapp-mcp`, num worktree e num PR próprios de lá. O `conferir-mutacao.cjs` copia a árvore **deste** repo e, com caminho absoluto de fora, mutaria o arquivo real do outro repo — por isso elas declaram `mutacao: n/a`, e a mutação é rodada à mão no worktree do `whatsapp-mcp`, com a saída vermelha colada na evidência do `executar`.

## Tarefas

### 1. `watch_chat.py` avisa quando a bridge cai e quando volta [tipo: implementar]
atende: D1, D5
arquivos: `C:/Projetos/whatsapp-mcp/scripts/watch_chat.py`, `C:/Projetos/whatsapp-mcp/scripts/test_watch_chat.py`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: fonte fora deste repo; a catraca daqui não alcança sem mutar o arquivo real. No worktree do whatsapp-mcp, inverter `if healthy != last_healthy:` para `if False:` tem de deixar `python -m pytest scripts/test_watch_chat.py` vermelho no caso da queda; saída colada na evidência do executar.
pronto quando: com `--status-url http://127.0.0.1:<porta>/api/status` apontando para um servidor falso que responde o formato real do `/api/status` da bridge (capturado da 3005 em 2026-09-25: `{"success":true,"healthy":true,"connected":true,"logged_in":true,...}`, JID redigido) e depois passa a responder `healthy:false`, e em seguida para de responder, o script emite na saída uma linha `BRIDGE: desconectada (<motivo>)` na primeira transição e **uma só** enquanto continuar fora, e `BRIDGE: conectada` quando volta; sem `--status-url`, a saída é idêntica à de hoje; a linha diz ao leitor humano que a espera está cega, não que ninguém respondeu — provado por `python -m pytest scripts/test_watch_chat.py` no worktree do whatsapp-mcp, com os casos de queda, volta, porta recusada e sem flag.

### 2. `vigiar.md` do fork: caminho do script, porta da conta e linha BRIDGE [tipo: docs]
atende: D1, D2, D5
arquivos: `C:/Projetos/whatsapp-mcp/commands/vigiar.md`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: doc de fluxo; a falsificação é a coerência com o `watch_chat.py` da tarefa 1 e com o `accounts.json` real.
pronto quando: lido contra o `watch_chat.py` da tarefa 1 e o `~/.whatsapp-mcp/accounts.json` real (`pessoal` 3005, `trabalho` 3006): o passo 3 usa `${CLAUDE_PLUGIN_ROOT}/scripts/watch_chat.py` só se o arquivo existir, e aceita o caminho já resolvido por quem chama; o comando armado leva `--status-url` com a porta da conta resolvida no passo 1; há um passo que diz o que fazer com `BRIDGE: desconectada` (avisar o usuário que a espera está cega, sem desarmar) e com `BRIDGE: conectada` — conferido por leitura, e cada flag citada existe no `parse_args` da tarefa 1.

### 3. Checagem de arme do rainforest: chave, bridge da conta e caminhos [tipo: implementar]
atende: D2, D4, D5
arquivos: `scripts/vigiar-checar.cjs`, `scripts/testa-vigiar-checar.sh`, `hooks/fixtures/vigiar/status-conectada.json`, `hooks/fixtures/vigiar/status-desconectada.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/vigiar-checar.cjs`
  de: `if (!ligado('integracao-whatsapp-mcp', { projeto: projetoDir })) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-vigiar-checar.sh`
  fixture: `testa-vigiar-checar.sh, caso "chave desligada recusa em uma linha sem consultar a bridge"`
pronto quando: com `node scripts/vigiar-checar.cjs --conta <alias>` numa caixa de areia com `accounts.json` no formato real (`{"pessoal":{"dir":..,"port":3005,"jid":..}}`, dados fictícios) e um servidor falso servindo o payload real do `/api/status` (JID redigido): chave desligada → exit 2 e uma linha dizendo o comando que liga a chave; chave ligada e bridge da conta fora (porta recusada ou `healthy:false`) → exit 2 e uma linha nomeando a conta e a porta; conta inexistente → exit 2 listando as contas que existem; tudo certo → exit 0 e JSON com `status_url` da porta **da conta pedida** (não 3005 quando a conta é a de 3006), `script` (`$WHATSAPP_MCP_DIR/scripts/watch_chat.py`, padrão `C:/Projetos/whatsapp-mcp`) e `vigiar_md`, recusando com exit 2 se o script não existir — provado por `bash scripts/testa-vigiar-checar.sh` nesses casos, e uma vez contra a bridge real de leitura (`--conta pessoal`, só GET) com a saída colada.

### 4. Skill e comando `vigiar` [tipo: docs]
atende: D2, D3, D4
arquivos: `skills/vigiar/SKILL.md`, `commands/vigiar.md`
depende de: 2, 3
paralela: nao
mutacao: n/a
  motivo: texto de skill e comando; a falsificação é a coerência com o `vigiar-checar.cjs` da tarefa 3 e com o `vigiar.md` do fork da tarefa 2.
pronto quando: a skill manda rodar `node scripts/vigiar-checar.cjs --conta <alias>` antes de qualquer arme, e com exit ≠ 0 repassar a linha e parar (D4); com exit 0, seguir o `vigiar_md` devolvido usando o `script` e o `status_url` devolvidos, sem reescrever o fluxo do fork (D2); a `description` diz em uma linha que é acompanhar uma conversa dentro da sessão e não um vigia agendado de `vigias/` (D3); o comando `/rainforest-mind:vigiar` carrega a skill — conferido lendo contra a saída real do `vigiar-checar.cjs` e contra o `vigiar.md` da tarefa 2, e `bash scripts/testa-teto-skills.sh` aceita a skill nova.

### 5. Versão 1.23.13 [tipo: configurar]
atende: D2
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 4
paralela: nao
mutacao: n/a
  motivo: bump de versão, sem comportamento a inverter.
pronto quando: `node scripts/conferir-versao.cjs` aceita (maior que a da `origin/main`, hoje `1.23.12`) e `bash scripts/testa-versao.sh` confirma `plugin.json` e selo do README iguais. Última tarefa do `executar`, para o `revisar` cobrir o diff inteiro.
