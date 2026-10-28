# Plano: Lote A — saude, gate-fechar-issue e esperar-ci sem falso alarme (#608, #592, #594, #587, #591)

Design: docs/rainforest/design/2026-10-27-ferramentas-do-fluxo.md

## O que não pode quebrar
- `scripts/testa-saude.sh`: os cenários que hoje passam continuam passando, inclusive "sem parentesco" com clone **completo** de história reescrita (raiz diferente) → ALERTA com `reset --hard`. A D2 só muda o caso do clone **raso**.
- `scripts/testa-saude.sh`: "as duas config dirs, nao so uma" e "(Issue #221)" seguem verdes — `.claude` + `.claude-personal` (nomes que nenhum padrão de fábrica casa) continuam comparadas.
- `scripts/testa-publicar-branch.sh` (g): g1–g4 e g7–g12 seguem com o exit de hoje. A **g5** muda de propósito no commit da tarefa 3: `STUB_CHECKS_EXIT=1` só continua saindo 5 se o JSON relido tiver bucket `fail`/`cancel`; a fixture da g5 passa a fixar esse JSON.
- `esperar-ci` com `--watch` saindo 0 tem o caminho de hoje, linha por linha (só `pass`/`skipping` é verde; lista vazia e JSON ilegível → 5).
- `hooks/testa-gate-fechar-issue.sh`: todo caso que hoje espera 2 continua 2; todo que espera 0 continua 0. O gate segue fail-closed (D6): nenhuma falha de consulta vira passagem.
- `hooks/testa-config.sh` e `node scripts/conferir-setup.cjs` seguem verdes com a chave nova da D3 na tabela do `skills/setup/SKILL.md`.
- Nenhum caso de teste afirma sobre o texto do fonte de `saude.cjs`, `publicar-branch.cjs` ou `gate-fechar-issue.cjs`. As baterias rodam o script como processo. Exceção deliberada e única: a tarefa 6 lê `commands/feedback.md`, porque o defeito da #592 é o texto prescrito.
- As linhas `de:` das tarefas 1–5 são código a nascer. O briefing do `executar` as cita literalmente como requisito: a catraca só aplica a mutação se o texto casar byte a byte e uma única vez no arquivo.

## Regra de parada
- **D5 (leitura textual de workflow):** o veredito 8 exige "nenhum workflow alcança PR". A leitura é conservadora: qualquer menção a `pull_request`, ou `push` num arquivo sem `branches:`/`branches-ignore:`, conta como alcançar — erra para o 5 de hoje. Forma de YAML que a heurística não cobre (âncora, `on` entre aspas, matriz de eventos exótica) vira nota no PR, não parser novo.
- **D6 (gate):** o modelo de ameaça é o da D6 — fechar Issue por palavra-chave sem evidência. Fechamento manual no site e gate desligado ficam fora. Contorno novo que o revisor achar fora disso vira nota no PR.

## Tarefas

### 1. saude: clone raso não acusa "sem parentesco" [tipo: implementar]
atende: D1, D2
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
prova-na-base: verde — o caso de clone raso entra na bateria existente, que na base roda sem ele; o vermelho é medido pela mutação
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `const rasoLa = cloneRaso(instalado);`
  para: `const rasoLa = false;`
  bateria: `bash scripts/testa-saude.sh`
  timeout: `3600000`
  fixture: `testa-saude.sh, secao "#608 D2: clone raso", caso "#608-2. clone raso 1 commit atras vira aviso"` (emenda da revisão: o #608-1, em dia, não chega a comparar raízes e não morde a mutação)
pronto quando: forma do código (a mutação depende dela):
- Função de topo `cloneRaso(dir)` roda `git rev-parse --is-shallow-repository` com `cwd: dir` e devolve `true` só com status 0 e saída `true`.
- Dentro de `avaliarConfigDir`, no bloco que hoje compara `raizAqui`/`raizLa`, as linhas exatas `const rasoLa = cloneRaso(instalado);` e `const raso = rasoLa || cloneRaso(RAIZ_CODIGO);` vêm antes da comparação de raízes (emenda D2 da revisão 1: qualquer lado raso). Com `raso` verdadeiro, a comparação de raízes não é usada: `git cat-file -e <la>^{commit}` em `RAIZ_CODIGO` decide — existe → segue para a contagem `rev-list --count` de hoje; não existe → relato `nivel: 'aviso'` com detalhe `<o clone|este repositorio> e raso e o commit <la7> nao existe aqui (commit proprio ou historia reescrita — repositorio raso nao distingue)`, **sem** `reset --hard` na ação; com skill faltando, o ALERTA `carregado sem` prevalece e leva esse texto.

Com um `installPath` que é `git clone --depth 1 file://<repo da caixa>` (o mesmo formato que o `claude plugin marketplace` produziu em 2026-10-27, `.git/shallow` presente):
- clone raso no mesmo commit do repo → `node scripts/saude.cjs` não emite `ALERTA  plugin instalado`;
- clone raso 1 commit atrás → linha `aviso` com `1 commit(s) atras`, sem `sem parentesco`;
- clone raso cujo HEAD é um commit que o repo não tem → linha `aviso` contendo `clone e raso`, e a saída inteira não contém `reset --hard`;
- caso vizinho que continua ALERTA: clone **completo** com história reescrita (raiz diferente) → `ALERTA  plugin instalado` com `sem parentesco` e `reset --hard`.

Superfície humana: no caso raso desconhecido, a pessoa lê que o clone é raso e por que não dá para afirmar parentesco, e não recebe um comando destrutivo. O critério falha se o `reset --hard` voltar a aparecer.

Provado por `bash scripts/testa-saude.sh` com placar sem falha, e, na integração, por `node scripts/saude.cjs` desta máquina (clone do marketplace raso desde 2026-10-27 01:39) sem a linha `ALERTA  plugin instalado: [.claude] o clone esta numa historia sem parentesco`.

### 2. saude: config dirs ignoradas por padrão de nome [tipo: implementar]
atende: D3
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`, `hooks/lib/config.cjs`, `hooks/testa-config.sh`, `skills/setup/SKILL.md`
depende de: 1
prova-na-base: verde — os casos entram nas baterias existentes; o vermelho é medido pela mutação
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `return padroes.some((p) => casaPadrao(nome, p));`
  para: `return false;`
  bateria: `bash scripts/testa-saude.sh`
  timeout: `3600000`
  fixture: `testa-saude.sh, secao "#608 D3: config dirs ignoradas", caso "bench sem override nao gera ALERTA de autocompact"`
pronto quando: forma do código:
- `hooks/lib/config.cjs` ganha a chave `'saude-ignorar-config-dirs'` com `tipo: 'padroes'`, `padrao: null`, descrição curta ("padrões de nome de config dir que o /saude não compara; null = *bench* e *.aposentada"), `entrevista: null`; `validarTipo` aceita `'padroes'` = `null` ou array de strings não vazias (até 60 caracteres cada). Caso novo em `hooks/testa-config.sh`: array de strings válido, `[]` válido, `[""]`, `"x"` e `[1]` inválidos.
- `skills/setup/SKILL.md` ganha a linha da chave na tabela (o `conferir-setup.cjs` exige toda chave de `CHAVES` na tabela).
- Em `scripts/saude.cjs`: constante `const IGNORADAS_DE_FABRICA = ['*bench*', '*.aposentada'];`; `casaPadrao(nome, padrao)` com `*` como único curinga, sem diferenciar caixa; `padroesIgnorados()` lê a chave por `resolverConfig()` (array → usa ele, inclusive `[]`; `null`/ausente/config ilegível → `IGNORADAS_DE_FABRICA`); `configDirIgnorada(nome, padroes)` com o corpo exato `return padroes.some((p) => casaPadrao(nome, p));`.
- O filtro `configDirIgnorada(basename)` entra nas três enumerações de `~/.claude*`: `configDirsDoHarness` (só no ramo da varredura da home; com `CLAUDE_CONFIG_DIR` declarado nada muda), `todasAsConfigDirsDaHome` e a lista `candidatas` de `checarAutocompact`. Isso cobre as quatro checagens da D3.

Com HOME falsa contendo `.claude` (settings com `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` = `"45"` e `plugins/`), `.claude-bench-rf` (settings com chave de harness, sem override, e `plugins/`) e `.claude-personal.aposentada` (override `"45"`, plugin em outra versão):
- `node scripts/saude.cjs` não emite `ALERTA  autocompact`, nem `aviso config dirs`, nem `aviso skills-divergentes` citando as duas pastas ignoradas;
- casos vizinhos que continuam acusando: `.claude=45` + `.claude-personal=50` → `ALERTA  autocompact`; `.claude=45` + `.claude-personal` **sem** override → `ALERTA  autocompact` (a conta real esquecida, motivo de a opção A ter sido descartada);
- com `{"saude-ignorar-config-dirs": []}` na config, a bench volta a entrar e o `ALERTA  autocompact` reaparece.

Provado por `bash scripts/testa-saude.sh`, `bash hooks/testa-config.sh` e `node scripts/conferir-setup.cjs` sem falha, e, na integração, por `node scripts/saude.cjs` desta máquina sem `ALERTA  autocompact`.

### 3. esperar-ci: queda do `--watch` decide pelo estado relido [tipo: implementar]
atende: D1, D4
arquivos: `scripts/publicar-branch.cjs`, `scripts/testa-publicar-branch.sh`
depende de: nenhuma
prova-na-base: verde — os casos entram na bateria existente; o vermelho é medido pela mutação
mutacao:
  arquivo: `scripts/publicar-branch.cjs`
  de: `if (!falhos.length && relidos.length) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-publicar-branch.sh`
  fixture: `testa-publicar-branch.sh, secao "(g) esperar-ci", caso "(g18) watch cai com checks pending: sai 69"`
pronto quando: forma do código:
- No ramo `checks.status !== 0` de `esperarCi`, antes de devolver 5, relê `gh pr checks <pr> --json name,bucket` e tenta `JSON.parse` do stdout **independente do status** do relido.
- JSON ilegível ou leitura sem stdout → `erro('nao-verificavel: ...')` com o stderr do `gh`, `return 69`.
- Lista parseada: `const falhos = relidos.filter((c) => c.bucket === 'fail' || c.bucket === 'cancel');` — `falhos.length` → 5 com a mensagem de hoje nomeando os checks; a linha exata `if (!falhos.length && relidos.length) {` abre o ramo "espera interrompida" → stderr começando por `nao-verificavel:` e `return 69`; lista vazia → 5 como hoje ("no checks reported conta como não verde").

Com o stub `gh` da bateria:
- `--watch` sai 1 e o relido sai 1 com stderr `error connecting to api.github.com` e stdout vazio → exit **69**, stderr começa por `nao-verificavel:` (critério literal da #587);
- `--watch` sai 1 e o relido traz `[{"name":"a","bucket":"pending"}]` → **69** (g18);
- `--watch` sai 1 e o relido traz `[{"name":"a","bucket":"fail"}]` → **5**, stderr nomeia `a (fail)` (g5 reescrita);
- `--watch` sai 1 e o relido traz `[]` → **5**;
- `--watch` sai 0: g1–g4, g7–g10 inalteradas.

Superfície humana: no 69, a pessoa lê que o CI não pôde ser verificado (não que está vermelho) e o motivo; o critério falha se o 69 sair sem o prefixo `nao-verificavel:`.

Provado por `bash scripts/testa-publicar-branch.sh` sem falha.

### 4. esperar-ci: "sem CI de PR" pelos workflows do checkout [tipo: implementar]
atende: D1, D5
arquivos: `scripts/publicar-branch.cjs`, `scripts/testa-publicar-branch.sh`
depende de: 3
prova-na-base: verde — os casos entram na bateria existente; o vermelho é medido pela mutação
mutacao:
  arquivo: `scripts/publicar-branch.cjs`
  de: `if (/\bpull_request/.test(texto)) return true;`
  para: `if (/\bpull_request/.test(texto)) return false;`
  bateria: `bash scripts/testa-publicar-branch.sh`
  fixture: `testa-publicar-branch.sh, secao "(g) esperar-ci", caso "(g19) workflow com pull_request e PR sem check: sai 5" (emenda da revisão 1: o corpo de alcancaPr virou três linhas, a âncora é a do gatilho pull_request)`
pronto quando: forma do código:
- Função de topo `alcancaPr(texto)`: `pull_request` conta; `push` conta salvo filtro `branches:` de nomes fixos dentro do bloco `push:` (`branches-ignore` ou `*` no bloco contam — emenda da revisão 1; `branches:` de outro gatilho, de `with:` ou de comentário não filtra o push, e a releitura no formato do gh real — exit 1, stdout vazio, `no checks reported` no stderr — sai 5, não 69: g25 a g28, emenda da revisão 2; `on:` de fluxo com push e comentário de fim de linha não filtram: g29 e g30, revisão 3; só os filhos diretos do `on:` de topo em bloco são lidos, e filho que cita push fora da forma `push:` + bloco conta: g31 e g32, revisão 4; glob de branch é `*`, `?`, `+` ou `[...]`, procurado só no valor de `branches:`: g33 a g35, revisão 5).
- Função de topo `workflowsDePr(raiz)`: `git ls-files .github/workflows` com `cwd: raiz`; status ≠ 0 → `null` (desconhecido); senão lê cada `.yml`/`.yaml` listado e devolve quantos `alcancaPr` aceita.
- Em `esperarCi`, a consulta `gh api repos/{owner}/{repo}/actions/workflows` sai; `semCiDePr` = `workflowsDePr(process.cwd()) === 0`. `null` segue o caminho de hoje (sem 8). O resto do ramo (PR sem check → 8, mensagem `repositório sem CI de PR`, `merge autorizado`/`pare no PR aberto`) fica.
- O stub `STUB_WORKFLOWS` deixa de ser lido pelo script; os casos g11/g12 passam a se apoiar na caixa sem `.github/workflows`.

Com a caixa git da bateria e o PR sem check (`STUB_CHECKS_JSON='[]'`, `STUB_CHECKS_EXIT=1`):
- sem `.github/workflows` → **8** (g11/g12, #576 preservada);
- só `.github/workflows/protect-main.yml` com o conteúdo real da #591 (`on:` / `push:` / `branches: [main]`) → **8** (critério literal da #591);
- `.github/workflows/ci.yml` com `on: pull_request` → **5** (g14), porque há CI de PR e ele não reportou;
- `.github/workflows/ci.yml` com `on: [push]` sem `branches` → **5**;
- `protect-main.yml` + um workflow só de `schedule:` → **8**;
- cwd fora de repositório git → **69** (o script para antes de ler workflow), nunca 8 (g22; emenda da revisão 2).

Provado por `bash scripts/testa-publicar-branch.sh` sem falha.

### 5. gate-fechar-issue: consulta de evidência com o repo do comando, e erro ≠ ausência [tipo: implementar]
atende: D1, D6
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
prova-na-base: verde — os casos entram na bateria existente; o vermelho é medido pela mutação
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (repo) argsView.push("--repo", repo);`
  para: `if (false) argsView.push("--repo", repo);`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, secao "#594", caso "pr create -R x/y com Closes #n e marcador, cwd fora de repo: exit 0"`
pronto quando: forma do código:
- `temMarcadorEvidencia(issueNum, repo, cwd)` monta `const argsView = ["issue", "view", String(issueNum), "--json", "comments"];` e tem a linha exata `if (repo) argsView.push("--repo", repo);`; sem `repo`, roda com `cwd` = o cwd do segmento (`cwdPorSegmento`), no mesmo molde da consulta da #496 (`hooks/gate-fechar-issue.cjs`, ~linha 1072).
- Devolve `{ ok: true, tem: <bool> }` ou `{ ok: false, erro: <stderr> }`. O chamador (~linha 871) bloqueia nos dois casos ruins, com mensagens distintas: `tem: false` → a mensagem de hoje; `ok: false` → `não consegui ler a Issue #<n>: <stderr>; rode de dentro do repositório ou use --repo` — e essa mensagem **não** manda comentar a evidência.
- O `repo` vem do `--repo`/`-R` do próprio segmento (o parser de ~linha 840 já o lê).
- As outras chamadas `gh ... view` do gate são listadas no relatório da tarefa com o veredito de cada uma (já leva repo / passa a levar / não se aplica); a que estiver na mesma classe passa a levar o repo.

Com o stub `gh` da bateria estendido para que `issue view` **falhe** (exit 1, stderr `failed to run git: fatal: not a git repository`) quando não vier `--repo caixa/repo` e o cwd não for repositório:
- `gh pr create -R caixa/repo --body "Closes #12"` com cwd fora de repo e Issue com marcador → **0** (o caso da #594);
- mesmo comando com Issue sem marcador → **2**, stderr com a mensagem de hoje (`não tem comentário com a evidência`);
- `gh pr create --body "Closes #12"` (sem `-R`) com cwd fora de repo → **2**, stderr com `não consegui ler a Issue #12` e **sem** `não tem comentário`;
- contornos que continuam 2: `gh pr create -R caixa/repo --body "Fixes #12"` sem marcador; `gh issue close 12 -R caixa/repo` sem marcador;
- vizinhos que continuam 0: `gh pr create --body "Segue #12"`; casos (c) e (d2) de hoje.

Superfície humana: na falha de leitura, a pessoa lê que o gate não conseguiu olhar a Issue e como dar o repo — não que falta evidência. O critério falha se as duas mensagens se confundirem.

Provado por `bash hooks/testa-gate-fechar-issue.sh` sem falha.

### 6. /feedback prescreve "Segue #<n>:" e a forma passa pelo gate [tipo: implementar]
atende: D7
arquivos: `commands/feedback.md`, `hooks/testa-gate-fechar-issue.sh`
depende de: 5
prova-na-base: verde — o caso novo lê a forma de `commands/feedback.md`; na base ele não existe, e o vermelho é medido pela mutação
mutacao:
  arquivo: `commands/feedback.md`
  de: Segue #<n>: ...
  para: CORRIGE #<n>: ...
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, secao "#592", caso "forma prescrita pelo /feedback passa pelo gate"`
pronto quando: `commands/feedback.md` (linhas ~115-116) prescreve `` `Segue #<n>: ...` `` e não contém mais `CORRIGE #<n>`. O caso novo extrai do `commands/feedback.md` real a forma entre crases que segue "na primeira linha:", troca `<n>` por `591` e `...` por `texto`, e roda `gh issue create --title "<forma>" --body "<forma>"` pelo gate → **exit 0**. Com a mutação (forma `CORRIGE`) → **exit 2**, e o caso fica vermelho. Se a extração não achar a forma, o caso falha (nunca pula).

Provado por `bash hooks/testa-gate-fechar-issue.sh` sem falha e `grep -c "CORRIGE #<n>" commands/feedback.md` devolvendo `0`.

### 8. gate-fechar-issue: `gh pr merge <URL>` consulta a Issue no repo da URL [tipo: implementar]
atende: D6
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 6
prova-na-base: verde — o caso entra na bateria existente; o vermelho é medido pela mutação
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const repoDaIssue = repo || repoDaUrlDoPr(ref);`
  para: `const repoDaIssue = repo;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: `testa-gate-fechar-issue.sh, secao "#594 merge por URL", caso "pr merge <URL de outro repo> com Closes #12: consulta no repo da URL e barra"`
pronto quando: achado da revisão de segurança automática sobre o commit da tarefa 5 (2026-10-27): no `gh pr merge <URL>`, o `--repo` é proibido (a URL já diz o repo) e a consulta de evidência corria contra o repo do cwd — Issue de mesmo número com marcador no repo do cwd deixaria passar o fechamento no repo da URL (bypass dentro do modelo de ameaça da D6). Forma do código: função de topo `repoDaUrlDoPr(ref)` devolve `dono/repo` de `https://github.com/<dono>/<repo>/pull/<n>` (com ou sem barra final), `null` para número ou qualquer outra forma; no caminho do merge, a linha exata `const repoDaIssue = repo || repoDaUrlDoPr(ref);` e as duas chamadas `verificarIssuesCitadas(..., repoDaIssue, cwdSegmento)` usam ela. Com o stub `gh` estendido por uma variável que devolve marcador SÓ quando o `issue view` vem SEM `--repo` (simula a Issue homônima com marcador no repo do cwd) e o `pr view` devolvendo corpo `Closes #12`: `gh pr merge https://github.com/caixa/repo/pull/7 --squash` → **2**; vizinho `gh pr merge https://github.com/caixa/repo/pull/7 --squash` com a Issue de `caixa/repo` com marcador → **0**; `gh pr merge 7 --squash` (número, sem URL) → comportamento de hoje. Provado por `bash hooks/testa-gate-fechar-issue.sh` sem falha.

### 7. Versão 2.0.5, README e colheita [tipo: docs]
atende: D1, D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `skills/fechar/SKILL.md`, `vigias/ERROS.md`, `skills/executar/SKILL.md`, `skills/rainforest-mind/references/regra-11.md`, `scripts/contrato-plugin-codex.cjs`, `hooks/testa-abertura-mod-config.sh`
depende de: 2, 4, 6, 8
mutacao: n/a
  motivo: bump de versão e texto; o comportamento é medido pelas tarefas 1–6 e pela trava `conferir-versao`
pronto quando: `.claude-plugin/plugin.json` em `2.0.5` e o badge do README com o mesmo número; o README descreve, onde já fala de cada peça, (a) a chave `saude-ignorar-config-dirs` com os padrões de fábrica `*bench*` e `*.aposentada`, (b) o 69 do `esperar-ci` como "não verificável" (rede ou espera interrompida) e o 8 como "nenhum workflow do checkout alcança PR"; nenhuma chave nova restaura o comportamento antigo (D1) — conferido por `node -e "const c=require('./hooks/lib/config.cjs').CHAVES;console.log(Object.keys(c).filter(k=>/saude|esperar|gate-fechar/.test(k)).join(','))"` devolvendo exatamente `gate-fechar-issue,saude-ignorar-config-dirs` (na base, 2026-10-27, devolve `gate-fechar-issue`). `vigias/ERROS.md` já está no commit do design. Achado da execução (2026-10-27): `skills/executar/SKILL.md` e `skills/rainforest-mind/references/regra-11.md` mandam o comando de preparo "literal com caminho absoluto"; o único absoluto conhecido no despacho é o do checkout principal, e o gate de worktree da 2.0.4 o barra (3 de 3 agentes pararam no passo 2). O texto passa a prescrever `node scripts/preparar-worktree.cjs --hash <hash>` com caminho RELATIVO, rodado de dentro do worktree do agente — conferido por `grep -n "preparar-worktree" skills/executar/SKILL.md skills/rainforest-mind/references/regra-11.md` sem nenhuma ocorrência de "caminho absoluto" ligada ao preparo. Provado por `node scripts/conferir-versao.cjs` com exit 0 e `ok    versao 2.0.5`. Emenda do CI do PR #615 (2026-10-28): o texto novo de `skills/fechar/SKILL.md` e de `regra-11.md` move duas âncoras que medem esses arquivos — o corpo binário de `fechar` em `scripts/contrato-plugin-codex.cjs` (16102 B) e `elaboracoesBytes`/`regrasBytes` em `hooks/testa-abertura-mod-config.sh` (33697 B / 39619 B, abaixo do teto de 40960); provado por `bash scripts/testa-plugin-codex.sh` e `bash hooks/testa-abertura-mod-config.sh`, ambos com exit 0.
