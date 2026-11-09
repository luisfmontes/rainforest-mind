# Plano: o verificar recusa diff que apaga ou pula teste sem declarar

Design: docs/rainforest/design/2026-11-09-regua-testes.md

## O que não pode quebrar
- `conferir-fluxo.cjs cobertura`, `creep`, `mutacoes` e `deriva` saem igual a hoje para plano sem o campo `afrouxa:`.
- `marcar verificar ok` de fluxo cujo diff não apaga nem pula teste fecha como hoje; fluxo sem plano, ou sem `base`/`head` no `revisar`, também (o segundo com um aviso em stderr).
- A bateria nova não contém, no próprio texto, nenhum marcador de pulo literal: os fixtures montam `.skip(` e afins por concatenação, senão o diff deste fluxo seria recusado pela trava que ele cria.

## Tarefas

### 1. Subcomando `afrouxa`: teste apagado e marcador de pulo no diff [tipo: implementar]
atende: D1, D2, D3, D5
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo-afrouxa.sh`
depende de: nenhuma
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (status === 'D' && ehArquivoDeTeste(caminho)) achados.push({ tipo: 'apagado', arquivo: caminho });`
  para: `if (false && ehArquivoDeTeste(caminho)) achados.push({ tipo: 'apagado', arquivo: caminho });`
  bateria: `bash scripts/testa-conferir-fluxo-afrouxa.sh`
  fixture: `testa-conferir-fluxo-afrouxa.sh, caso "A1 bateria apagada sem afrouxa recusa"`
prova: `bash scripts/testa-conferir-fluxo-afrouxa.sh`
pronto quando: num repositório git em `mktemp -d` com um commit base que tem `scripts/testa-x.sh`, `src/a.test.js` e `src/b.js`, e um plano cuja tarefa declara `arquivos:` com os três, `node scripts/conferir-fluxo.cjs afrouxa --slug t --plano <plano> --base <base> --head <head>` sai 2 com `RECUSADO:` e `apagado: scripts/testa-x.sh` quando o head apaga a bateria; sai 2 com `pulo: src/a.test.js:<n>` quando o head acrescenta uma linha com `it.skip(` (ou `.only(`, `xit(`) no teste; sai 0 quando o head só renomeia a bateria (`git mv`), quando acrescenta `it.skip(` em `src/b.js` (não é teste) e quando o diff só edita casos sem marcador; e sai 69 com `nao-verificavel:` quando o `git` não está no PATH — provado por `bash scripts/testa-conferir-fluxo-afrouxa.sh` saindo 0 com cada caso listado pelo nome, e pela mutação acima deixando o caso A1 vermelho

Forma prescrita:
- Em `scripts/conferir-fluxo.cjs`, seção `// ================================================================ afrouxa` antes de `function main()`:
  - `const PADROES_TESTE = [ /(^|\/)testa-[^/]*\.(sh|cjs|py)$/, /(^|\/)[^/]+\.(test|spec)\.[^/]+$/, /(^|\/)[^/]+_test\.[^/]+$/, /(^|\/)test_[^/]+\.py$/ ];` e `function ehArquivoDeTeste(caminho)` que testa o caminho com `/` contra a lista.
  - `const MARCADOR_PULO = /\.(skip|only)\(|\bx(it|describe|test)\(|@pytest\.mark\.skip|@unittest\.skip|\bt\.Skip\(|@Disabled\b|@Ignore\b/;`
  - `function achadosAfrouxa(raiz, base, head)`: roda, por `execFileSync(caminhoExecutavel('git'), [...], { cwd: raiz, encoding: 'utf8' })` com lista de argumentos (nunca string de shell), (1) `-c core.quotepath=false diff --name-status -M <base>...<head>`: para cada linha, `const [status, caminho] = linha.split('\t')` com `status` cortado na primeira letra; a linha do mutante (`de:` acima) empurra o apagado. (2) `-c core.quotepath=false diff -U0 --no-color -M --src-prefix=a/ --dst-prefix=b/ <base>...<head>`: acompanha o arquivo atual pelo `+++ b/<caminho>` (`+++ /dev/null` zera), lido como cabeçalho só entre `diff --git` e o primeiro `@@` do arquivo, porque linha adicionada cujo texto começa com `++ ` tem a mesma cara, a linha nova pelo `@@ -a,b +c,d @@` (começa em `c`, soma 1 a cada `+`), e empurra `{ tipo: 'pulo', arquivo, linha, trecho }` para cada linha `+` (fora do `+++`) de arquivo de teste que casa `MARCADOR_PULO`, com `trecho` = a linha sem o `+`, aparada, cortada em 120 caracteres. Devolve a lista; `ENOENT` do git sobe como erro com `code`.
  - `function cmdAfrouxa()`: `--slug`, `--base`, `--head` obrigatórios; `--plano` opcional, resolvido como no `cmdCreep` (`arg('plano', false) || docDoEstado(slug, 'plano') || path.join(RAIZ, caminhoDoc('planos', slug, { raiz: RAIZ }))`, ausente → `recusaPlanoAusente` e exit 2). O `git` roda em `RAIZ`, como o `creep`. `ENOENT` → `process.stderr.write('nao-verificavel: git nao encontrado no PATH\n')` e exit 69; outro erro do git, inclusive revisão desconhecida → `erro ao rodar git diff: <mensagem>` e exit 1. Sem achado: `ok: nenhum teste apagado ou pulado no diff` e exit 0. Com achado sem tarefa que o autorize (tarefa 2): stderr `RECUSADO: o diff tira teste do caminho sem declarar:`, uma linha por achado (`  apagado: <arquivo>` ou `  pulo: <arquivo>:<linha> <trecho>`), e a linha do remédio `Declare na tarefa que toca o arquivo: afrouxa: <por que o teste sai ou é pulado>`; exit 2.
  - `main` ganha `if (cmd === 'afrouxa') return cmdAfrouxa();`, e a linha de uso passa a `uso: design | cobertura | camadas | creep | afrouxa | mutacoes [--gravar-flake] | deriva [--slug <s>] [--arquivo <a>]`.
- **Bateria:** `scripts/testa-conferir-fluxo-afrouxa.sh`, no idioma da `testa-conferir-fluxo-no-lugar.sh` (`passa`/`falha`, `SANDBOXES` com trap, placar `ok: N   falhou: M` e `exit 1` se `FALHOU > 0`). Cada caso monta seu repositório com `git init -q`, `git -c user.email=t@t -c user.name=t commit`, plano mínimo com uma tarefa (`### 1. t [tipo: implementar]`, `atende: D1`, `arquivos:` com os três caminhos, `mutacao: n/a` + `motivo: x`), e roda o checador como o `chk` da `testa-conferir-fluxo-no-lugar.sh`: `env -u CLAUDE_PROJECT_DIR RFM_ESTADO_ROOT="$SM" node ...`, com `--plano` e todo caminho passado ao node na forma mista (`cygpath -m`). Marcadores montados por concatenação (`SK="sk""ip"`, `printf 'it.%s(...' "$SK"`). Casos, nomeados pelo que afirmam: `A1 bateria apagada sem afrouxa recusa` (exit 2, `apagado: scripts/testa-x.sh`), `A2 pulo novo em teste recusa com arquivo e linha` (exit 2, `pulo: src/a.test.js:`), `A3 .only e xit tambem recusam`, `A4 renome da bateria nao conta`, `A5 pulo em arquivo que nao e teste nao conta`, `A6 edicao sem marcador passa`, `A7 sem git no PATH sai 69` (`env PATH="<pasta vazia de mktemp>" "<caminho absoluto do node>" ...`, porque em `/usr/bin` o `git` mora junto do `node`).

### 2. Campo `afrouxa:` na tarefa: o escape declarado [tipo: implementar]
atende: D4
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo-afrouxa.sh`
depende de: 1
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `const autorizada = autorizadas.find((t) => t.globs.some((g) => globMatches(achado.arquivo, g)));`
  para: `const autorizada = undefined;`
  bateria: `bash scripts/testa-conferir-fluxo-afrouxa.sh`
  fixture: `testa-conferir-fluxo-afrouxa.sh, caso "B1 apagado com afrouxa na tarefa do arquivo passa"`
prova: `bash scripts/testa-conferir-fluxo-afrouxa.sh`
pronto quando: com o mesmo repositório da tarefa 1, a bateria apagada passa (exit 0, stdout com `afrouxa declarado: tarefa 1 (<motivo>): apagado: scripts/testa-x.sh`) quando a tarefa cujo `arquivos:` casa a bateria declara `afrouxa: <motivo>`; continua recusando (exit 2) quando o `afrouxa:` está numa tarefa cujo `arquivos:` não casa o arquivo; e `conferir-fluxo.cjs cobertura` recusa `afrouxa:` sem motivo nomeando a tarefa e aceita `afrouxa: <motivo>` sem `campo desconhecido` — provado por `bash scripts/testa-conferir-fluxo-afrouxa.sh` saindo 0 com cada caso listado, e pela mutação acima deixando o caso B1 vermelho

Forma prescrita:
- `extrairCamposDesconhecidos`: `'afrouxa'` entra em `conhecidos_top`.
- `function motivoAfrouxa(conteudo_plano, numero)`: no corpo da tarefa (`extrairCorpoTarefa`), fora de cerca e antes de `pronto quando:`, a primeira linha `^afrouxa:(.*)$` na coluna 0; devolve o resto aparado (`''` se vazio) ou `null` sem a linha.
- `cmdAfrouxa`: `autorizadas` = tarefas com `motivoAfrouxa` não vazio, cada uma `{ numero, motivo, globs: extrairArquivos(conteudo_plano, numero) }`. Para cada achado, `descricao` = `apagado: <arquivo>` ou `pulo: <arquivo>:<linha> <trecho>` (o mesmo texto da recusa) e a linha do mutante (`de:` acima); com `autorizada`, `console.log(\`afrouxa declarado: tarefa ${autorizada.numero} (${autorizada.motivo}): ${descricao}\`)`; sem, o achado vai para a recusa. Exit 0 quando todos autorizados.
- `cmdCobertura`: no laço das tarefas, `motivoAfrouxa(...) === ''` empurra `tarefa N. <nome> afrouxa: sem motivo — diga por que o teste sai ou é pulado`.
- **Bateria:** casos `B1 apagado com afrouxa na tarefa do arquivo passa`, `B2 afrouxa em tarefa de outro arquivo nao autoriza` (plano com duas tarefas, a do `afrouxa:` com `arquivos: \`src/outro.js\``), `B3 cobertura recusa afrouxa sem motivo` (exit 2, `afrouxa: sem motivo`), `B4 cobertura aceita afrouxa com motivo` (sem `campo desconhecido: afrouxa:` na saída). B3 e B4 rodam `cobertura` com design mínimo de uma decisão `D1` ao lado do plano (`--design` e `--plano` na forma mista).

### 3. O `marcar verificar ok` roda o `afrouxa` sobre o diff revisado [tipo: implementar]
atende: D1
arquivos: `scripts/estado.cjs`, `scripts/testa-conferir-fluxo-afrouxa.sh`
depende de: 2
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (afrouxa.status !== 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-fluxo-afrouxa.sh`
  fixture: `testa-conferir-fluxo-afrouxa.sh, caso "C1 marcar verificar ok recusa bateria apagada sem afrouxa"`
prova: `bash scripts/testa-conferir-fluxo-afrouxa.sh`
pronto quando: num repositório sandbox com estado do fluxo em que `revisar` fechou `ok` com `base`/`head` de um diff que apaga `scripts/testa-x.sh`, `node scripts/estado.cjs marcar --slug <s> --estagio verificar --status ok --json '{"comando":"bash","saida":"done"}'` sai 2 com `apagado: scripts/testa-x.sh` e `RECUSADO: o verificar não fecha` e não grava o estado (hash do JSON igual antes e depois); com `afrouxa: <motivo>` na tarefa, o mesmo comando sai 0 e o stdout traz `afrouxa declarado: tarefa 1 (`; e sem `base`/`head` no `revisar` a saída traz `aviso: revisar sem base/head` — provado por `bash scripts/testa-conferir-fluxo-afrouxa.sh` saindo 0 com os casos C1, C2 e C3, por `bash scripts/testa-estado.sh` e `bash scripts/testa-estado-reabrir.sh` saindo 0 (o caso 413 fecha `verificar` com `--raiz`), e pela mutação acima deixando C1 vermelho

Forma prescrita:
- Em `scripts/estado.cjs`, dentro do `if (fs.existsSync(arquivo_plano)) { ... }` do `verificar`, logo depois do bloco da catraca de mutações (`if (mutacoes.status !== 0) { ... }`): `const rev = estado.revisar || {};` e, com `rev.base && rev.head`, `const argsAf = [path.join(__dirname, 'conferir-fluxo.cjs'), 'afrouxa', '--slug', slug, '--plano', arquivo_plano, '--base', String(rev.base), '--head', String(rev.head)];`, `const afrouxa = spawnSync(process.execPath, argsAf, { stdio: 'inherit' });` e a linha do mutante, que imprime `RECUSADO: o verificar não fecha: a checagem de teste apagado ou pulado não passou (acima).` e sai 2. Sem `base`/`head`: `console.error('aviso: revisar sem base/head gravados; a checagem de teste apagado ou pulado não rodou');` e segue. Qualquer saída diferente de 0 recusa (exit 69 e erro do git são falta de prova, não aprovação). Sem `--raiz-codigo`: o diff é o que o `creep` mediu.
- **Bateria:** casos C1, C2, C3 no idioma da seção 6 de `scripts/testa-estado.sh` (estado criado por `iniciar`, design/plano gravados por `node -e` no JSON, `executar` e `revisar` fechados por `marcar` com exit conferido, `revisar` com `base`/`head` do repositório do caso, `RFM_ESTADO_ROOT="$SM"` explícito e `env -u CLAUDE_PROJECT_DIR`). C1 confere o hash do JSON do estado antes e depois. C3 grava `revisar={status:'ok'}` por `node -e` no JSON (como `scripts/testa-estado-reabrir.sh:94`), porque o `marcar revisar ok` recusa sem `base`/`head`. `C1 marcar verificar ok recusa bateria apagada sem afrouxa`, `C2 com afrouxa a checagem nao recusa`, `C3 revisar sem base e head avisa e segue`.

### 4. Documentação, versão 2.10.0 e CHANGELOG [tipo: docs]
atende: D6
arquivos: `skills/verificar/SKILL.md`, `skills/plano/SKILL.md`, `docs/travas-mecanicas.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 3
mutacao: n/a
  motivo: texto e versão; o comportamento é medido pelas tarefas 1 a 3
Forma: `skills/verificar/SKILL.md` ganha a seção `## Teste apagado ou pulado (afrouxa)`, depois de "Validação de mutações (catraca D9)": o que o `marcar verificar ok` passa a rodar, sobre qual diff (`revisar.base...revisar.head`), os dois sinais, o escape `afrouxa: <motivo>` e as saídas 0/2/69; e diz que um `.only(` ou `.skip(` de outra API dentro de arquivo de teste também casa, com o mesmo remédio. `skills/plano/SKILL.md` ganha, depois do parágrafo de `mutacao: n/a`, uma frase: tarefa que apaga ou pula teste declara `afrouxa: <por que>`, senão o `verificar` recusa. `docs/travas-mecanicas.md` ganha a linha da trava na tabela do `verificar`, no formato das vizinhas. Versão 2.10.0 nos dois `plugin.json` e no selo do README (`vers%C3%A3o-2.10.0` e `versão 2.10.0`; `README.en.md` intocado). CHANGELOG `## 2.10.0 — 2026-11-09` acima da 2.9.1, item `- **O verificar recusa teste apagado ou pulado sem declarar.** <o que faz e o escape>`. Os tetos: `skills/verificar/SKILL.md` e `skills/plano/SKILL.md` têm limite de tamanho.
pronto quando: com o repositório deste worktree, `node scripts/conferir-versao.cjs` sai 0; os dois `plugin.json` dizem `"version": "2.10.0"`; a seção nova do `verificar` descreve os mesmos dois sinais, o mesmo campo e as mesmas saídas que `cmdAfrouxa` implementa (conferido lendo os dois lado a lado); e `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh`, `bash scripts/testa-plugin-codex.sh` e `bash scripts/testa-indice-referencias.sh` saem 0 — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n "afrouxa" skills/verificar/SKILL.md skills/plano/SKILL.md docs/travas-mecanicas.md CHANGELOG.md` e pelas quatro baterias

## Emendas do leitor cego

- D1 e tarefas 1 e 3: o `afrouxa` roda em `RAIZ`, onde o `creep` rodou, sem `--raiz-codigo`. O caso 413 de `testa-estado.sh` grava `base`/`head` de um repositório e fecha `verificar` com `--raiz` em outro; rodar lá daria revisão desconhecida.
- D5: erro do git que não é `ENOENT` sai 1 e o `verificar` recusa.
- Tarefa 3: C2 exige exit 0 e o `afrouxa declarado:` no stdout (sem isso passaria com a checagem desligada); C1 confere o hash do estado; C3 grava o `revisar` no JSON; `testa-estado.sh` e `testa-estado-reabrir.sh` entram no critério.
- Tarefa 1: caminhos ao node na forma mista; A7 com PATH vazio e node por caminho absoluto; prefixos do diff fixados; `+++` lido como cabeçalho só antes do primeiro `@@`.
- Tarefa 2: `descricao` definida.
- Tarefa 4: a seção do `verificar` avisa do casamento largo de `.only(`/`.skip(`.

## Emendas da revisão 1

Decisões de Luís em 2026-11-09 sobre o achado `[design]`: renome de teste para fora dos padrões conta como apagado (D2); as variantes de marcador entram, com lista fechada (D2); o head vem de `revisar.snapshot.head` quando existir (D1). O `pronto quando:` da tarefa 1 sobre `git mv` vale para renome de teste para teste (A4).

- Tarefa 1: o achado do renome leva `arquivo` = destino e `de` = origem, e o destino é o que o `creep` exige no `arquivos:`; `descricao` traz `(renomeado de <origem>)`. Cabeçalho `+++` sem o TAB final. `--text --no-ext-diff --no-textconv` no diff. `--base`/`--head` começando com `-` saem 1. Sai a troca de `\\` por `/`, porque o git sempre devolve `/`.
- Bateria: casos A9 a A16 (renome para fora, espaço no nome, cada padrão de arquivo, cada marcador com a linha certa, linha `++ `, `.gitattributes` com `-diff`, revisão com hífen) e C4 (head declarado igual à base).
- Tarefa 1: `*.test.*`, `*.spec.*` e `*_test.*` aceitam uma extensão só depois do marcador, senão `a.test.js.off` continuaria sendo arquivo de teste e o renome para fora não seria visto.
- Tarefa 4: a seção do `verificar` diz que a lista de marcadores é fechada e que nome de teste fora dos padrões não é visto.
- Descartado: `afrouxa: x` autorizar tudo no `arquivos:` é o que o D4 decide; nome de arquivo com aspas ou barra invertida vem entre aspas no diff e fica fora (não reproduzível no Windows, onde a bateria roda).
