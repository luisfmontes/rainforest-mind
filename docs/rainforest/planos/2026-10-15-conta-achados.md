# Plano: conta unificar: 5 achados baixos da pasta-unica (#503)

Design: docs/rainforest/design/2026-10-15-conta-achados.md

## O que não pode quebrar
- Todos os casos atuais de `bash scripts/testa-conta-unificar.sh` seguem verdes, inclusive os da rodada 6 (achado 1: `--aplicar` registra a pessoal do `oauthAccount`; achado 2: gravação concorrente do `.claude.json` sobrevive; achado 3: progresso append-only).
- `bash scripts/testa-conta-uma-pasta.sh` e `bash scripts/testa-conta-unificar-profile.sh` seguem verdes.
- Toda recusa sai antes de qualquer escrita: com saída 2, o disco da fixture fica igual ao de antes (mesmos hashes).

## Tarefas

### 1. Progresso com `\n` na frente e mescla do `.claude.json` que relata o que gravou [tipo: implementar]
atende: D1, D5
arquivos: `scripts/lib/conta-unificar.cjs`, `scripts/testa-conta-unificar.sh`
depende de: nenhuma
prova-na-base: verde — os dois casos (linha rasgada no progresso; `mcpServers.github` gravado por uma sessão entre o plano e o aplicar) são montados pela própria bateria com o preload de teste, e só existem nela a partir desta tarefa
mutacao:
  arquivo: `scripts/lib/conta-unificar.cjs`
  de: if (Object.hasOwn(mcpServers, n)) { mantidos.push(n); continue; }
  para: if (false) { mantidos.push(n); continue; }
  bateria: `bash scripts/testa-conta-unificar.sh`
  fixture: testa-conta-unificar.sh, caso novo "#503 D5" (sessão grava mcpServers.github com outra definição antes da etapa .claude.json)
pronto quando: com a fixture real da bateria, (a) um `unificar-progresso.jsonl` cuja última linha é `"projects/-proj-x/memory/b.md` sem fecho nem `\n`, seguido de uma retomada `--aplicar`, termina com a migração completa (sai 0) e a cópia gravada depois da linha rasgada não se perde; (b) uma sessão que grava `mcpServers.github` com `command: "outro-gh"` no `.claude.json` de trabalho entre o plano e a etapa faz o `--aplicar` sair 0 com `mcpServers.github.command` igual a `outro-gh`, e a saída do relatório nomeia `github` como mantido do destino, sem contá-lo como `+1` — provado por `bash scripts/testa-conta-unificar.sh` com zero falha.

Forma do código: `gravarProgresso` grava `'\n' + JSON.stringify(...) + '\n'` (a linha vazia já é ignorada por `lerProgresso`). Na etapa `.claude.json` de `aplicar`, o laço de `mcpAdd` vira:
```
for (const [n, def] of Object.entries(mcpAdd)) {
  if (Object.hasOwn(mcpServers, n)) { mantidos.push(n); continue; }
  mcpServers[n] = def;
  gravados.push(n);
}
```
e a etapa devolve `{ gravados, mantidos }` (também quando não há nada a mesclar: listas vazias), que `aplicar` devolve como `claudeJson` ao lado de `plugins` e `reagendado`. `relatorio(plano, aplicado)`: com `aplicado`, a linha `mcp em .claude.json:` conta e lista `aplicado.claudeJson.gravados`, e com `mantidos` não vazio acrescenta `mantido do destino: <nomes>`; sem `aplicado` (relatório antes do aplicar) fica como hoje. Nenhum caso de teste lê o texto do fonte.

Casos novos na bateria:
- "#503 D1": fixture com o progresso de uma rodada anterior terminando em linha rasgada; `--aplicar` sai 0 e o MEMORY.md fica igual ao de uma rodada única limpa (mesmo predicado do caso da rodada 6, achado 3).
- "#503 D5": preload no estilo de `sessao2.cjs` que, na primeira cópia, grava `mcpServers.github = { type: "stdio", command: "outro-gh" }` no `.claude.json` de trabalho; `--aplicar` sai 0, `mcpServers.github.command` = `outro-gh`, e a saída contém `github` na linha de mantido e não contém `+1 (github)`.

### 2. Recusas do registro da pessoal no relatório, mensagem e e-mail duplicado [tipo: implementar]
atende: D2, D3, D4
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-unificar.sh`
depende de: 1
prova-na-base: verde — as fixtures (pasta pessoal sem `oauthAccount`; pessoal com o mesmo e-mail da `team` registrada) são variantes novas do `semear.cjs` da bateria, criadas nesta tarefa
mutacao:
  arquivo: `scripts/conta.cjs`
  de: if (oauth.emailAddress === (estado.contas.team || {}).email) {
  para: if (false) {
  bateria: `bash scripts/testa-conta-unificar.sh`
  fixture: testa-conta-unificar.sh, caso novo "#503 D4" (pessoal com o e-mail da team)
pronto quando: com a fixture real da bateria, (a) sem `contas.pessoal` e sem `oauthAccount` na pasta pessoal, `conta.cjs unificar` SEM `--aplicar` sai 2 e a mensagem contém `/login` e não contém `rode status` nem `preparar` (emenda D3 depois da 1ª revisão); gravado então o `oauthAccount` no `.claude.json` da pasta pessoal, como o login faz, o mesmo relatório sai 0; (b) com `--aplicar`, a mesma fixture sai 2 com a mesma mensagem e o disco fica igual (mesmo hash do `estado.json` e do `.claude.json` de trabalho); (c) com `contas.team.email` = `team@exemplo.invalid` e `oauthAccount.emailAddress` da pessoal também `team@exemplo.invalid`, o relatório e o `--aplicar` saem 2, a mensagem nomeia o e-mail duplicado, e o `estado.json` não ganha `contas.pessoal` — provado por `bash scripts/testa-conta-unificar.sh` com zero falha.

Forma do código: em `conta.cjs`, o bloco que hoje fica depois do `schtasks /Query` ("Conta pessoal sem registro (rodada 6, achado 1)") sobe para antes do `if (!args.includes('--aplicar'))` que imprime o relatório, e decide `plano.registroPessoal` igual. Dentro dele, depois de achar o `oauth`, entra a guarda:
```
if (oauth.emailAddress === (estado.contas.team || {}).email) {
  return sair(2, `...o e-mail ${oauth.emailAddress} já é o da conta de trabalho...unificar não escreveu nada`);
}
```
A mensagem da recusa sem `oauthAccount` passa a mandar fazer login na pasta pessoal (`claude` com `CLAUDE_CONFIG_DIR` apontando para ela e `/login`) e depois `unificar` de novo, e continua terminando com `unificar não escreveu nada`. Nenhum caso de teste lê o texto do fonte.

### 3. CHANGELOG, README e versão [tipo: docs]
atende: D1, D2, D3, D4, D5
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2
mutacao: n/a
  motivo: tarefa de documentação e número de versão; não há comportamento a inverter
pronto quando: com as tarefas 1 e 2 no repo, a entrada nova do CHANGELOG (PATCH sobre a versão da `origin/main` no momento do despacho) descreve, para quem ainda vai migrar, as cinco mudanças de D1–D5 sem prometer mais do que o código faz, e as duas `plugin.json` e o selo do README batem com ela — provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando a entrada com D1–D5.
