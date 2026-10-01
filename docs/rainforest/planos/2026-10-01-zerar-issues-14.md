# Plano: Rodada 14 — triagem do Gmail (#367), creep da varredura (#368), dívidas da rodada 13 (#369)

Design: docs/rainforest/design/2026-10-01-zerar-issues-14.md

## O que não pode quebrar
- O `creep` continua recusando arquivo sem tarefa, inclusive varredura de OUTRO slug.
- O veredito do revisor isolado continua indo para o worktree do fluxo (casos 23–26 da bateria do veredito verdes).
- `--exige` com `../../../README.md`, caminho profundo e absoluto fora continua saindo 2; `--exige README.md` e `../file.txt` de subpasta continuam 0.
- O gate-turno-prometido continua com os 32 casos verdes, inclusive `#364-r2 aspa solta crlf`.
- O `-Teste` do runner continua tirando as tools de envio do WhatsApp; nenhuma variável de ambiente do usuário ou do sistema muda.

## Tarefas

### 1. Creep isenta a varredura do próprio slug [tipo: implementar]
atende: D1
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`, `skills/revisar/SKILL.md`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-conferir-fluxo.sh 2>&1 | grep -qE '^ +ok +\(#368\) varredura do proprio slug'`
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: 'docs/rainforest/varredura/' + slug + '.txt',
  para: 'docs/rainforest/varredura/' + 'NUNCA' + '.txt',
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: testa-conferir-fluxo.sh, caso "(#368) varredura do proprio slug nao e creep"
Implementação: em `globs_isentos` (`scripts/conferir-fluxo.cjs`, junto de design/plano/estado), entra exatamente a linha do `de:`, com um comentário de uma linha citando a #368 (o `brainstorm` obriga a criar e o `marcar --estagio design` exige). Casos novos na bateria, num repo git de caixa de areia (a seção de creep hoje usa o repo real; os novos montam o seu): `(#368) varredura do proprio slug nao e creep` — diff que só adiciona `docs/rainforest/varredura/<slug>.txt` → exit 0; `(#368) varredura de outro slug continua creep` — diff com `docs/rainforest/varredura/outro.txt` → recusa nomeando o arquivo. A seção "Isenções" de `skills/revisar/SKILL.md` ganha um item para a varredura do próprio slug, citando a #368.
pronto quando: com um diff real cujo único arquivo é `docs/rainforest/varredura/<slug>.txt`, `node scripts/conferir-fluxo.cjs creep --slug <slug> --base <b> --head <h>` sai 0, e com `varredura/outro.txt` sai recusando com o caminho — provado por `bash scripts/testa-conferir-fluxo.sh` (0 falhas, os dois casos #368 presentes).

### 2. Empate de veredito: o worktree de onde o revisor rodou vence [tipo: implementar]
atende: D2
arquivos: `hooks/veredito-revisor.cjs`, `hooks/testa-veredito-revisor.sh`
depende de: nenhuma
paralela: sim
prova: `bash hooks/testa-veredito-revisor.sh 2>&1 | grep -qE '^ +ok +\(#369\)'`
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: if (raiz) sobra = [raiz];
  para: if (false) sobra = [raiz];
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: testa-veredito-revisor.sh, caso "(#369) empate de dois worktrees armados: vence o do revisor"
Implementação: em `raizComEstadoDoSlug`, depois do filtro de janela armada e antes do `if (sobra.length === 1)`, entra: `if (sobra.length > 1) { const raiz = sobra.find((p) => path.resolve(p) === path.resolve(repoRoot));` + quebra + exatamente a linha do `de:` + `}`. Caso novo `(#369) empate de dois worktrees armados: vence o do revisor`: repo git real, dois worktrees linkados fora de `agent-*` (`fluxo` e `copia`), os dois com `revisar.vereditos: []`, principal sem o arquivo, revisor com cwd em `fluxo` → a entrada aparece em `fluxo` e `copia` fica byte a byte igual (cmp). Casos 23–26 continuam verdes.
pronto quando: com o payload SubagentStop real e esse par de worktrees armados, `node hooks/veredito-revisor.cjs` grava no worktree do `payload.cwd` em vez de sair com `ambiguo` — provado por `bash hooks/testa-veredito-revisor.sh` (0 falhas, caso #369 presente).

### 3. `--exige`: `..foo` passa, raiz recusa com mensagem própria, existência pelo caminho resolvido [tipo: implementar]
atende: D3
arquivos: `scripts/preparar-worktree.cjs`, `scripts/testa-preparar-worktree.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-preparar-worktree.sh 2>&1 | grep -qE '^ +ok +\(#369\) --exige \.\.foo'`
mutacao:
  arquivo: `scripts/preparar-worktree.cjs`
  de: if (rel === ".." || rel.startsWith(".." + path.sep) || path.isAbsolute(rel)) {
  para: if (rel.startsWith("..") || path.isAbsolute(rel)) {
  bateria: `bash scripts/testa-preparar-worktree.sh`
  fixture: testa-preparar-worktree.sh, caso "(#369) --exige ..foo dentro do worktree passa"
Implementação: em `conferirExige`, para cada arquivo: `const alvo = path.resolve(cwd, arquivo);` e `const rel = path.relative(toplevel, alvo);`; `rel === ""` → `falha(2, "--exige aponta para a raiz do worktree: '" + arquivo + "'")`; depois exatamente a linha do `de:` com `falha(2, "--exige fora do worktree: '" + arquivo + "'")`; e o teste de existência passa a ser `fs.existsSync(alvo)`. Casos novos, rótulo começando por `(#369)`: `--exige ..foo dentro do worktree passa` (arquivo `..foo` na raiz da fixture → 0); `--exige . recusa citando a raiz` (→ 2, stderr com "raiz"); `--exige absoluto dentro do worktree passa` (→ 0). Os casos `(#364)` e `(#364-r3)` continuam verdes.
pronto quando: com um worktree real, `--exige ..foo` (arquivo existente) sai 0, `--exige .` sai 2 com "raiz" no stderr, `--exige <absoluto de um arquivo do worktree>` sai 0 e `--exige ../../../README.md` continua 2 — provado por `bash scripts/testa-preparar-worktree.sh` (0 falhas, casos #369 presentes).

### 4. Sai a normalização de CRLF que nenhum teste distingue [tipo: implementar]
atende: D4
arquivos: `hooks/gate-turno-prometido.cjs`
depende de: nenhuma
paralela: sim
prova: `! grep -qF 'replace(/\r\n?/g' hooks/gate-turno-prometido.cjs`
mutacao: n/a
  motivo: a tarefa remove código que o revisor da rodada 13 mediu como neutro (bateria igual com e sem ele); não há comportamento novo a inverter — a garantia é a bateria seguir verde, inclusive o caso de CRLF.
Implementação: em `normalizarTexto`, `let normalizado = texto.replace(/\r\n?/g, '\n');` vira `let normalizado = texto;`, e o comentário acima, se citar CRLF, diz que a regex de aspas já trata `\r` como caractere comum (não atravessa linha em branco nem com CRLF).
pronto quando: com a fixture real `364-r2-aspa-solta-crlf.jsonl` (CRLF), `node hooks/gate-turno-prometido.cjs` continua saindo 2, e o fonte não tem mais a normalização — provado por `node hooks/testa-gate-turno-prometido.cjs` (`falhou: 0`, 32 casos) e pela `prova:` acima.

### 5. Runner dá 90 s para o MCP subir [tipo: implementar]
atende: D5
arquivos: `vigias/run-vigia.ps1`, `scripts/testa-run-vigia-claude.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-run-vigia-claude.sh 2>&1 | grep -qE 'ok.*\(#367\) MCP_TIMEOUT'`
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: $env:MCP_TIMEOUT = '90000'
  para: $env:MCP_TIMEOUT_DESLIGADO = '90000'
  bateria: `bash scripts/testa-run-vigia-claude.sh`
  fixture: testa-run-vigia-claude.sh, caso "(#367) MCP_TIMEOUT chega ao claude"
Implementação: logo antes da chamada `$prompt | & $claude -p ...`, entra exatamente a linha do `de:`, com um comentário curto citando a #367 e a medição (57,6 s contra o teto de 30 s do Claude Code, via `npx -y`). A variável vale só para este processo e seus filhos. Na bateria, o `bom.cmd` passa a ecoar também `%MCP_TIMEOUT%`; caso novo `(#367) MCP_TIMEOUT chega ao claude` confere `90000` no log da ronda.
pronto quando: com o `run-vigia.ps1 -Vigia sentinela-foco -Teste` real e um `claude` de caixa que ecoa o ambiente, o log da ronda mostra `MCP_TIMEOUT=90000` (ou o valor ecoado) — provado por `bash scripts/testa-run-vigia-claude.sh` (0 falhas, caso #367 presente).

### 6. Toda ronda nega o servidor `mcp__gmail` [tipo: implementar]
atende: D6
arquivos: `vigias/run-vigia.ps1`, `scripts/testa-run-vigia-claude.sh`
depende de: 5
paralela: nao
prova: `bash scripts/testa-run-vigia-claude.sh 2>&1 | grep -qE 'ok.*\(#367\) mcp__gmail negado'`
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: $negadas = @('mcp__gmail')
  para: $negadas = @()
  bateria: `bash scripts/testa-run-vigia-claude.sh`
  fixture: testa-run-vigia-claude.sh, caso "(#367) mcp__gmail negado tambem fora do -Teste"
Implementação: a lista negada deixa de existir só no `-Teste`: começa com exatamente a linha do `de:` (o servidor `gmail` inteiro — o vigia lê pelo `gmail-leitura`), o `-Teste` acrescenta as tools de envio do WhatsApp (as de envio do `gmail` ficam redundantes e podem sair), e o `--disallowedTools` vai em toda ronda. Comentário curto citando a #367 (em 01/10 a triagem leu pelo `gmail` de escopo completo). Casos novos: `(#367) mcp__gmail negado tambem fora do -Teste` e o mesmo no `-Teste`, conferindo `mcp__gmail` na lista ecoada; o caso 5 de hoje (envio negado no `-Teste`) continua verde. A bateria ganha um modo de rodar sem `-Teste` só se o runner permitir sem enviar nada (o `claude` é falso); se não permitir, o caso fora do `-Teste` lê o argumento montado por outro caminho e o relato diz qual.
pronto quando: com o `run-vigia.ps1` real e o `claude` de caixa, a lista em `--disallowedTools` contém `mcp__gmail` com e sem `-Teste` — provado por `bash scripts/testa-run-vigia-claude.sh` (0 falhas, casos #367 presentes). Conferência de efeito real, uma vez, no relato: `claude -p` no `-Cwd` do runner (`C:\Projetos\comms-vigia`) com `--disallowedTools mcp__gmail` e prompt que só lista as tools `mcp__gmail*` disponíveis (sem chamar nenhuma) mostra as do `gmail-leitura` e nenhuma do `gmail`.

### 7. Prompt do sentinela lê pelo `gmail-leitura` e avisa quando não leu [tipo: docs]
atende: D6, D7
arquivos: `vigias/sentinela-foco.md`
depende de: 6
paralela: nao
mutacao: n/a
  motivo: texto de prompt; não há comportamento de código a inverter — a coerência se confere contra D6/D7 e contra o nome real da tool.
Implementação: o item 4 ("Triagem do inbox") passa a nomear a tool do servidor `gmail-leitura` (o nome real sai da conferência da tarefa 6, ex.: `mcp__gmail-leitura__search_emails`), diz que o `gmail` de escopo completo está fora da sessão de propósito, e manda, se a tool não subir após as tentativas, escrever no briefing a linha exata `inbox: não verificado — MCP do Gmail não subiu` além de registrar pela porta.
pronto quando: com o texto do item 4 lido contra o design, ele nomeia a tool real do `gmail-leitura` (a mesma que a conferência da tarefa 6 listou), não cita o `gmail` como fonte, e traz a linha exata do D7 — conferido lendo o arquivo contra D6/D7.

### 8. Versão e registro [tipo: docs]
atende: D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `docs/rainforest/varredura/2026-10-01-zerar-issues-14.txt`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: versão e registro; a coerência se confere por `node scripts/conferir-versao.cjs` e pela leitura contra D1–D7.
pronto quando: com a `origin/main` do momento, os manifestos e o badge sobem o minor e `node scripts/conferir-versao.cjs` sai 0; a entrada do CHANGELOG descreve D1–D7 como o design (timeout só da ronda, `gmail` negado, aviso explícito, isenção da varredura, as três dívidas) e cita a #372 como fora — conferido lendo contra o design.
