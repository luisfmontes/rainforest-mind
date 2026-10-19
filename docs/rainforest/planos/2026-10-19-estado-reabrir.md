# Plano: Reabrir revisar e verificar quando o código muda depois do ok (#567, #529)

Design: docs/rainforest/design/2026-10-19-estado-reabrir.md

## O que não pode quebrar
- `bash scripts/testa-estado.sh` segue com zero falha: fluxo que fecha `verificar` e `fechar` sem commit de código no meio passa como hoje.
- `marcar executar parcial` com posterior aberto continua recusado (#238); `reabrir` é verbo à parte.
- `marcar verificar reprovado` continua reabrindo `executar`, `revisar` e `fechar` (#441).
- Estado gravado antes deste fluxo (sem `verificar.head`) não trava o `exigir fechar`: só avisa.

## Tarefas

### 1. `verificar ok` grava o HEAD e `exigir fechar` recusa commit de código depois dele [tipo: implementar]
atende: D1, D2, D5, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-reabrir.sh`
depende de: nenhuma
prova-na-base: verde — a bateria `scripts/testa-estado-reabrir.sh` só nasce nesta tarefa
mutacao:
  arquivo: `scripts/estado.cjs`
  de: if (codigoDepois.length) {
  para: if (false) {
  bateria: `bash scripts/testa-estado-reabrir.sh`
  fixture: testa-estado-reabrir.sh, secao "D1: commit de codigo depois do verificar ok"
  timeout: 600000
pronto quando: numa caixa `mktemp -d` com repo git, fluxo aberto e `estado.cjs` real, com `verificar` fechado `ok` pelo `marcar` (plano sem `mutacao:` vermelha, para a catraca não pesar):
(a) o JSON em disco ganha `verificar.head` igual ao `git rev-parse HEAD` da caixa no momento do `marcar`;
(b) commit que toca `src/a.js` depois disso: `exigir --estagio fechar` sai 2, a saída nomeia `src/a.js` e cita `reabrir`;
(c) commit que toca só `docs/rainforest/estado/<slug>.json` (ou o design/plano do slug): `exigir --estagio fechar` sai 0;
(d) estado sem `verificar.head` (bloco `verificar` gravado à mão no formato antigo) e commit de código: `exigir --estagio fechar` sai 0 com aviso em stderr;
(e) *emenda da revisão 1:* `marcar verificar ok --raiz <worktree do mesmo repo>` não grava `verificar.head`, e o `exigir --estagio fechar` seguinte sai 0 mesmo com código da branch do estado que a outra árvore não tem;
(f) *emenda:* merge de commit da `main` (já empurrado para `origin/main`) depois do `verificar ok`: `exigir --estagio fechar` sai 0; commit de `src/a.js` na branch depois disso sai 2 e a saída não nomeia o arquivo que veio da `main`;
(g) *emenda:* `src/a.js` rastreado e modificado sem commit depois do `verificar ok`: sai 2 nomeando o arquivo; arquivo não rastreado não conta;
(h) *emenda:* commit só do `docs/rainforest/estado/<outro slug>.json` depois do `verificar ok`: sai 0;
(i) *emenda da revisão 2:* `exigir fechar` sai 0, depois commit de `src/a.js`: `marcar fechar ok` sai 2 nomeando o arquivo, e `fechar` não vira `ok` no JSON;
(j) *emenda 2:* `exigir revisar` tira o instantâneo, `revisar` ok, commit de `src/a.js`: `marcar verificar ok` sai 2 citando o `revisar` e o arquivo; `reabrir` sai 0;
(k) *emenda 2:* a branch muda a linha 1 do `CHANGELOG.md` antes do `verificar`, a `main` muda a linha 30 depois e entra por merge: `exigir fechar` sai 0;
(l) *emenda 2:* arquivo criado pela branch antes do `verificar` e apagado depois: `exigir fechar` sai 2 nomeando o arquivo;
(m) *emenda 3:* commit de arquivo de 1,7 MB depois do `verificar`: sai 2 nomeando o arquivo;
(n) *emenda 3:* a branch muda a linha 5, a `main` muda a linha 7 e entra por merge limpo: sai 0;
(o) *emenda 3:* depois do `verificar`, só a indentação da linha que a branch mudou: sai 2;
(p) *emenda 3:* conflito de versão (branch 1.70.0, `main` 1.69.2) resolvido para o valor da branch: sai 0;
(q) *emenda 3:* `exigir fechar` na `main` com o squash da branch: sai 0;
(r) *emenda 3:* `git mv` de `src/a.js` para `relatorios/` sem commit: sai 2 nomeando `src/a.js`;
(s) *emenda 3:* `marcar fechar ok` sem `verificar.head`: sai 0 com aviso;
(t) *emenda 4:* com a `main` parada, o conserto desfaz a mudança do bloco A e faz a mesma no bloco B: sai 2;
(u) *emenda 4:* `git mv` commitado de arquivo da `main` para `relatorios/`: sai 2 nomeando o nome antigo;
(v) *emenda 4:* a branch acrescenta 1,7 MB ao fim de um arquivo da `main` (patch acima de 1 MiB), a `main` muda a primeira linha dele e entra por merge: sai 0;
(w) *emenda 4:* estado do fluxo em `proj/` de um repositório maior: o estado rastreado e sujo não conta, e `proj/src/a.js` commitado depois do `verificar` sai 2 nomeando `src/a.js`;
provado por `bash scripts/testa-estado-reabrir.sh` com zero falha, placar `ok: N   falhou: 0`, nenhum caso lendo o texto do fonte.

Forma do código: em `scripts/estado.cjs`, função `arquivosDeCodigoDesde(head, slug, estado)` que roda `git diff --name-only <head> HEAD` e filtra com `globsIsentos`/`globMatches` de `scripts/conferir-fluxo.cjs` (os mesmos argumentos que o `creep` usa). No `marcar verificar ok`, grava `head` no bloco. No `exigir` do `fechar`, depois da checagem de pendências órfãs, a linha `const codigoDepois = arquivosDeCodigoDesde(estado.verificar.head, slug, estado);` e logo abaixo a linha exata `if (codigoDepois.length) {`, que imprime a recusa e sai 2.

### 2. verbo `reabrir` [tipo: implementar]
atende: D3, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-reabrir.sh`
depende de: 1
prova-na-base: verde — a seção "D3: reabrir" da bateria só nasce nesta tarefa
mutacao:
  arquivo: `scripts/estado.cjs`
  de: for (const e of ['revisar', 'verificar', 'fechar']) if (estado[e]) estado[e] = { ...estado[e], status: 'pendente', em: hoje() };
  para: for (const e of []) if (estado[e]) estado[e] = { ...estado[e], status: 'pendente', em: hoje() };
  bateria: `bash scripts/testa-estado-reabrir.sh`
  fixture: testa-estado-reabrir.sh, secao "D3: reabrir"
  timeout: 600000
pronto quando: na mesma caixa:
(a) com `revisar` em `ok`: `estado.cjs reabrir --slug <s> --estagio executar --motivo "achado A"` sai 0; no JSON, `executar.status` = `parcial`, `revisar`/`verificar`/`fechar` = `pendente`, e `reaberturas` tem um item com `motivo` "achado A", `de` "revisar" e data;
(b) com `verificar` em `ok` e `fechar` em `ok`: `reabrir` sai 0 e deixa os três em `pendente`; o `exigir --estagio fechar` seguinte sai 2 (verificar pendente);
(c) depois de `reabrir`, `exigir --estagio executar` sai 0 e `marcar executar ok` volta a valer;
(d) recusas com exit 2 e JSON intacto (`cksum` igual): `--motivo ""`, `--estagio revisar`, e `executar` ainda em `parcial` (nada a reabrir); slug inexistente sai 1, a convenção do `estado.cjs` para slug sem estado (*emenda da revisão 1*);
(e) `marcar executar parcial` com `revisar` em `ok` continua recusado (#238);
provado por `bash scripts/testa-estado-reabrir.sh` com zero falha.

Forma do código: `if (cmd === 'reabrir')` no despacho de comandos, `reabrir: ['slug', 'estagio', 'motivo']` na tabela de flags, e a linha exata `for (const e of ['revisar', 'verificar', 'fechar']) if (estado[e]) estado[e] = { ...estado[e], status: 'pendente', em: hoje() };`. O `reabrir` entra na linha `uso:` do fim do arquivo.

### 3. `marcar executar ok` recusa `de:` que não casa no fonte [tipo: implementar]
atende: D4, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-reabrir.sh`
depende de: 2
prova-na-base: verde — a seção "D4: de que nao casa" da bateria só nasce nesta tarefa
mutacao:
  arquivo: `scripts/estado.cjs`
  de: if (naoCasam.length) {
  para: if (false) {
  bateria: `bash scripts/testa-estado-reabrir.sh`
  fixture: testa-estado-reabrir.sh, secao "D4: de que nao casa"
  timeout: 600000
pronto quando: na caixa, com plano cuja tarefa 1 declara `mutacao:` com `arquivo:` existente:
(a) `de:` que não aparece no arquivo: `marcar executar ok` (com o `mutacao` do `--json` completo) sai 2, nomeia a tarefa e o arquivo, e o JSON fica intacto;
(b) `de:` que aparece uma vez: sai 0;
(c) `mutacao: n/a` com motivo, e `arquivo:` inexistente: sai 0 (como hoje);
(d) `bash scripts/testa-estado.sh` segue com zero falha (rodada pela integração com `rodar-longo`, porque passa de 10 min);
provado por `bash scripts/testa-estado-reabrir.sh` com zero falha e pela linha de placar de `scripts/testa-estado.sh`.

Forma do código: função `desQueNaoCasam(slug, estado)` em `scripts/estado.cjs` que lê o plano por `docDoEstagio('planos', slug, estado)`, extrai as tarefas com `extrairTarefas` de `scripts/conferir-fluxo.cjs`, e para cada `mutacao:` com `arquivo:` existente conta o `de:` (sem as crases, relativo ao `raiz:` quando houver). No `marcar executar ok`, junto da catraca, `const naoCasam = desQueNaoCasam(slug, estado);` e a linha exata `if (naoCasam.length) {`.

### 4. Skills, README, CHANGELOG e versão [tipo: docs]
atende: D3, D7
arquivos: `skills/revisar/SKILL.md`, `skills/fechar/SKILL.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `docs/travas-mecanicas.md`, `docs/rainforest/estado/2026-10-19-lote-issues-1019.json`, `scripts/contrato-plugin-codex.cjs`
*emenda do CI do PR #570:* a âncora binária do corpo de `skills/fechar/SKILL.md` em `scripts/contrato-plugin-codex.cjs` se re-mede quando a skill muda de propósito, e `scripts/testa-plugin-codex.sh` a confere.
*emenda da revisão 2:* `docs/travas-mecanicas.md` ganha a linha da trava nova (a tabela de travas acompanha a trava), e o estado do lote anterior chega pelo cherry-pick do `fechar ok` dele, rastro de fluxo que a D2 emendada isenta na trava, mas o `creep` não.
depende de: 3
mutacao: n/a
  motivo: texto de skill, CHANGELOG e versão; não há comportamento a inverter
pronto quando: com as tarefas 1 a 3 no repo: `skills/revisar/SKILL.md` ("Veredito binário") diz que achado não bloqueante de revisão aprovada volta por `reabrir`, com o comando; `skills/fechar/SKILL.md` diz que CI vermelho depois do `verificar ok` volta por `reabrir` e que o `exigir fechar` recusa commit de código depois do `verificar`; o CHANGELOG ganha entrada MINOR sobre a versão da `origin/main` com as três mudanças (D1, D3, D4) e o que fica fora (D5); as duas `plugin.json` e o selo do README batem. Provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando o texto com D1–D7.
