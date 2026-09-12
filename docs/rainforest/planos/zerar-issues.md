# Plano — zerar as Issues abertas

**Slug:** `zerar-issues` · **Design:** `docs/rainforest/design/zerar-issues.md`
**Base:** `origin/main` @ `58e8c37` · **Branch:** `fluxo/zerar-issues`

Dezenove tarefas, dezenove decisões. **Fan-out em três ondas**, separadas por
arquivo compartilhado, não por tema:

- **Onda 1** (arquivos disjuntos entre si e disjuntos de tudo que vem depois):
  T1, T2, T3, T4, T6, T7, T11, T12, T13, T14, T15, T16, T17, T18.
- **Onda 2** (tocam `scripts/estado.cjs` ou `scripts/conferir-fluxo.cjs`,
  que a onda 1 não toca): T5, T8; depois T9, que toca os dois.
- **Onda 3**: T10 (#216) mexe em baterias que T3, T8 e T9 acabaram de editar
  (`testa-saude.sh`, `testa-conferir-fluxo.sh`), e T19 fecha a versão.

**Rodada 2 (emenda de 2026-09-12).** O `revisar` reprovou com 5 achados e a
fatia sem achado já está na main (PR #236, 12 Issues). A branch trouxe a main
por merge (`97363814`); o que resta no diff é só o das tarefas com achado. As
tarefas 24 a 32 fecham os achados (D20–D23) e as seis Issues novas (D24–D29):

- **Onda 4** (arquivos disjuntos entre si): T24, T25, T26, T27, T28, T29, T30, T32.
- **Onda 5**: T31 (toca `estado.cjs` e `testa-estado.sh` depois da T25), T33
  (README e travas, depois de tudo que muda comportamento), e por fim T19 (versão).

A T10 teve o `arquivos:` emendado com as conversões que ela fez além das 11
declaradas (é a única saída do creep, e a conversão fica).

**Restrição que vale para todas:** o repo é público — nenhum caminho desta
máquina em código, teste ou fixture; e-mail em `git config` de bateria é
`test@<email>`. Toda asserção de bateria tem os dois ramos (`if/else`): a forma
`cmd && ok=…; echo ok || …` é tautológica e foi o que a primeira versão de
`testa-estado-principal.sh` entregou. Bloco `mutacao` com `de:`/`para:` **literais**
(o subcomando `mutacoes` de T9 vai executá-los).

## O que não pode quebrar
- Todas as baterias `scripts/testa-*.sh` e `hooks/testa-*.sh` continuam verdes (CI roda todas).
- `estado.cjs`: os fluxos abertos hoje (`docs/rainforest/estado/*.json`) continuam legíveis; flags hoje aceitas por cada subcomando continuam aceitas.
- `despachar-codex.cjs`: caminhos Windows com `:`, `\`, `/`, `.`, `-`, `_` e espaço continuam aceitos.
- `conferir-mutacao.cjs`: bateria sem placar reconhecível segue com o veredito de hoje.
- Hook de abertura fora de repositório git ou sem `origin` não imprime nada novo e não estoura.

## Tarefas

### 1. Portaria deduplica worktrees na negação [tipo: implementar]
atende: D1
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-diagnostico.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `if (vistos.has(chave)) continue;`
  para: `if (false) continue;`
  bateria: `node hooks/testa-portaria-diagnostico.cjs`
  fixture: dois worktrees com o mesmo estado aberto listam o slug uma vez
pronto quando: com dois worktrees git reais apontando para o mesmo `docs/rainforest/estado/<slug>.json` aberto e uma sessão sem estágio ativo, a mensagem de negação contém a linha do `(slug, estágio)` **uma única vez** — provado por `node hooks/testa-portaria-diagnostico.cjs` devolvendo o caso novo `ok` e exit 0.

### 2. despachar-codex recusa metacaractere de shell nos valores interpolados [tipo: implementar]
atende: D2
arquivos: `scripts/despachar-codex.cjs`, `hooks/lib/cli-externo.cjs`, `scripts/testa-despachar-codex.sh`, `hooks/testa-cli-externo.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/despachar-codex.cjs`
  de: `if (!valorSeguroParaShell(`
  para: `if (false && !valorSeguroParaShell(`
  bateria: `bash scripts/testa-despachar-codex.sh`
  fixture: --saida com metacaractere e recusado antes de montar o comando
pronto quando: com `--saida 'x"; echo pwned; "'` (e, em casos separados, `--worktree` com `&`, modelo com `|` via config, esforço com `$`), `node scripts/despachar-codex.cjs` sai 1 imprimindo `valor invalido: --saida` (ou a flag/config correspondente) **sem** invocar o dublê do Codex (`RFM_TEST=1`), e com `--saida "C:/Users/Alguem Com Espaco/x.md"` continua aceitando — provado por `bash scripts/testa-despachar-codex.sh` devolvendo os casos novos `ok` e exit 0; `valorSeguroParaShell` exportada de `hooks/lib/cli-externo.cjs` tem caso próprio em `hooks/testa-cli-externo.sh` (aceita caminho Windows com espaço; recusa cada um de `" ' \` $ & | ; < > ^ % ! ( )` e quebra de linha).

### 3. saude.cjs: `avaliarConfigDir` sempre devolve `dir` [tipo: implementar]
atende: D3
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `return doInstall ? { ...doInstall, dir: configDir }`
  para: `return doInstall ? { ...doInstall }`
  bateria: `bash scripts/testa-saude.sh`
  timeout: 1200000
  fixture: duas config dirs, uma sem clone do marketplace e com instalacao em versao diferente
pronto quando: com duas config dirs sintéticas — a primeira com clone de `plugins/marketplaces/<nome>` em dia, a segunda sem esse clone mas com `installed_plugins.json` registrando versão diferente da do repo — `node scripts/saude.cjs --json` sai 0 e o item do plugin instalado sai com `nivel: "aviso"` e detalhe prefixado por `[<dir>]`, nunca `Erro fatal`/`path argument` — provado por `bash scripts/testa-saude.sh` devolvendo o caso novo `ok` e exit 0.

### 4. gate-publicacao-destino não nomeia a escotilha ao subagente; bateria de fuga para os quatro gates [tipo: implementar]
atende: D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`, `hooks/testa-fuga-de-escotilha.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `const ehSubagente = Boolean(agente);`
  para: `const ehSubagente = false;`
  bateria: `bash hooks/testa-fuga-de-escotilha.sh`
  fixture: gate-publicacao-destino com agent_id nao menciona .rainforest-gate-off
pronto quando: com payload contendo `agent_id` e `agent_type` e um arquivo rastreado com e-mail literal, o stderr de `hooks/gate-publicacao-destino.cjs` sai 2, contém `PARE e reporte` e **não** contém `.rainforest-gate-off` nem `RAINFOREST_GATE_OFF`; sem `agent_id` continua nomeando as duas saídas — provado por `bash hooks/testa-gate-publicacao-destino.sh` (caso novo) e por `bash hooks/testa-fuga-de-escotilha.sh`, que roda os quatro gates (`gate-worktree`, `gate-staging-total`, `gate-repo-alheio`, `gate-publicacao-destino`) com `agent_id` num repo git sintético e sai 0 só se nenhum stderr contém as duas strings.

### 5. estado.cjs recusa flag desconhecida antes de gravar [tipo: implementar]
atende: D5
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (desconhecidas.length > 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-estado.sh`
  fixture: marcar com --dry-run sai 1 e nao grava
pronto quando: com um estado em `design: pendente`, `node scripts/estado.cjs marcar --slug t --estagio design --status aprovado --dry-run --json '{"doc":"x"}'` sai 1 imprimindo `flag desconhecida: --dry-run` e o JSON de estado fica byte-idêntico (sha256 antes = depois); `iniciar --slug t --titulo x` e cada flag hoje aceita por `ler/marcar/proximo/exigir/liberar/listar/concluido` continuam saindo como saem hoje — provado por `bash scripts/testa-estado.sh` devolvendo o caso novo `ok`, os 172 casos existentes `ok` e exit 0.

### 6. conferir-entrega reprova commit vazio do agente [tipo: implementar]
atende: D6
arquivos: `scripts/conferir-entrega.cjs`, `scripts/testa-conferir-entrega.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-entrega.cjs`
  de: `if (arquivos.size === 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-entrega.sh`
  fixture: commit vazio com --paralelo e sujeira no principal reprova
pronto quando: com um worktree cujo commit entregue não altera arquivo nenhum em relação à base, `node scripts/conferir-entrega.cjs --worktree <wt> --base <hash> --head-antes <hash> --paralelo` sai ≠ 0 imprimindo `commit do agente vazio`, com e sem sujeira no principal; commit com mudança real e sujeira em arquivo alheio continua `APROVADO` com o aviso de hoje — provado por `bash scripts/testa-conferir-entrega.sh` devolvendo os três casos novos `ok` e exit 0.

### 7. poda-estagio delega ao resolvedor canônico [tipo: implementar]
atende: D7
arquivos: `hooks/lib/poda-estagio.cjs`, `scripts/testa-poda-estagio.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/poda-estagio.cjs`
  de: `require('./estagio-ativo.cjs').resolver(`
  para: `(() => null)(`
  bateria: `bash scripts/testa-poda-estagio.sh`
  fixture: branch fluxo/<slug> com estado aberto devolve {slug, estagio}
pronto quando: com `git checkout -b fluxo/<slug>` e `docs/rainforest/estado/<slug>.json` aberto em `design`, `node hooks/lib/poda-estagio.cjs --cwd <dir>` devolve `{slug, estagio: "design"}` — o mesmo que `hooks/lib/estagio-ativo.cjs` — e em branch sem estado correspondente devolve `null` — provado por `bash scripts/testa-poda-estagio.sh` devolvendo o caso `9. branch com prefixo fluxo/` `ok` e exit 0.

### 8. creep isenta `relatorios/` [tipo: implementar]
atende: D8
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `'relatorios/',`
  para: `'relatorios-x/',`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: relatorios/x.md no diff sem tarefa nao e creep
pronto quando: com um diff `base...head` que só acrescenta `relatorios/2026-09-08-x.md` e um plano sem tarefa que o cubra, `node scripts/conferir-fluxo.cjs creep --slug <slug> --base <b> --head <h>` sai 0 (`sem creep`); com `relatorio-solto.md` na raiz continua `RECUSADO` — provado por `bash scripts/testa-conferir-fluxo.sh` devolvendo os dois casos novos `ok` e exit 0.

### 9. Mutações do plano viram executável: `conferir-fluxo mutacoes` e `marcar verificar ok` o roda [tipo: implementar]
atende: D9
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/estado.cjs`, `scripts/testa-conferir-fluxo.sh`, `scripts/testa-estado.sh`, `skills/verificar/SKILL.md`, `skills/plano/SKILL.md`, `README.md`
depende de: 5, 8
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (mutacoes.status !== 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-estado.sh`
  fixture: marcar verificar ok com mutante sobrevivente e recusado
pronto quando: (a) com um plano cujo bloco `mutacao:` de uma tarefa aponta para fonte e bateria sintéticos em que o mutante **sobrevive** (bateria verde com e sem a mutação), `node scripts/conferir-fluxo.cjs mutacoes --slug <slug>` sai ≠ 0 imprimindo a tarefa e `mutante sobreviveu`; com mutante que **morre** sai 0 imprimindo `vermelho`; com `mutacao: n/a` ou `de:` que não casa no arquivo, pula listando `pulada` e não reprova por isso; (b) `node scripts/estado.cjs marcar --slug <slug> --estagio verificar --status ok --json '{"comando":"x","saida":"y"}'` no cenário do mutante sobrevivente sai 2 com `RECUSADO` e não grava; no cenário do mutante morto grava `verificar: ok` — provado por `bash scripts/testa-conferir-fluxo.sh` e `bash scripts/testa-estado.sh` devolvendo esses casos `ok` e exit 0. As skills `verificar` e `plano` e o README descrevem o subcomando com o mesmo nome e os mesmos exits que o código tem (conferido por `node scripts/conferir-fluxo.cjs mutacoes` sem args imprimir o uso com o mesmo texto).

### 10. Sandbox de bateria sempre no trap; guarda estática [tipo: teste]
atende: D10
arquivos: `scripts/testa-conferir-fluxo.sh`, `scripts/testa-observar.sh`, `scripts/testa-saude.sh`, `hooks/testa-memoria-recuperacao.sh`, `scripts/testa-memoria-somente-leitura.sh`, `hooks/testa-contexto-sessao.sh`, `scripts/testa-orcamento.sh`, `hooks/testa-memoria-criticos-ponta-a-ponta.sh`, `hooks/testa-ferramentas-nao-toca-abertura.sh`, `scripts/testa-caminho-pessoal.sh`, `scripts/testa-dependencias-de-bateria.sh`, `scripts/testa-sandbox-com-trap.sh`, `README.md`, `hooks/testa-memoria-marca.sh`, `hooks/testa-memoria-recuperacao-ponta-a-ponta.sh`, `hooks/testa-memoria-session-start.sh`, `scripts/testa-dados-batedor-repos.sh`, `scripts/testa-fila-de-repos.sh`, `scripts/testa-gate-do-agente.sh`, `scripts/testa-importar-claude-mem.sh`, `scripts/testa-limpar-branches.sh`, `scripts/testa-medir-injecao.sh`, `scripts/testa-memoria-backup.sh`, `scripts/testa-memoria-migracao-atomica.sh`, `scripts/testa-memoria.sh`, `scripts/testa-portoes-gate.sh`, `scripts/testa-recibo-gravar.sh`, `scripts/testa-verifica-fidelidade.sh`, `scripts/testa-backup-estado.sh`, `scripts/testa-registrar-erro.sh`
(emenda 2026-09-12: os 17 arquivos a partir de `testa-memoria-marca.sh` são as conversões para o idioma `SANDBOXES` que a T10 fez além das 11 declaradas — o `revisar` as apontou como creep, e a emenda é a única saída; a conversão fica, porque é o que a guarda estática cobra)
depende de: 3, 8, 9
paralela: nao
mutacao:
  arquivo: `scripts/testa-sandbox-com-trap.sh`
  de: `if [ "$n_mktemp" -gt 1 ] && ! grep -q 'SANDBOXES' "$f"; then`
  para: `if false; then`
  bateria: `bash scripts/testa-sandbox-com-trap.sh --autoteste`
  fixture: fixture com dois mktemp e sem SANDBOXES e reprovada
pronto quando: com um `testa-*.sh` sintético em pasta temporária contendo dois `mktemp -d` e nenhum `SANDBOXES`, `bash scripts/testa-sandbox-com-trap.sh --autoteste` reprova nomeando o arquivo; com um `mktemp -d` e sem `trap … EXIT` reprova; com um `mktemp -d` e `trap … EXIT` passa; e, rodando sem `--autoteste` sobre o repositório, sai 0 porque os 11 arquivos passaram para o idioma `SANDBOXES`/`nova_sandbox`/`cleanup` (ou `trap` simples nos 3 de um `mktemp`) — provado por `bash scripts/testa-sandbox-com-trap.sh --autoteste; bash scripts/testa-sandbox-com-trap.sh` ambos exit 0 e por cada uma das 11 baterias editadas continuar saindo 0.

### 11. conferir-mutacao lê o placar [tipo: implementar]
atende: D11
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (bateriaColapsou(placarBase, placarPos)) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: mutacao que derruba 9 de 34 assercoes sai 6
pronto quando: com fixture cuja bateria imprime `ok: 34   falhou: 0` íntegra e, mutada, quebra a bateria inteira (`ok: 0   falhou: 0` + exit ≠ 0 por `ReferenceError`), `node scripts/conferir-mutacao.cjs --arquivo <f> --de <x> --para <y> --bateria <b>` sai 6 imprimindo `queda desproporcional de asserções`; com mutante que derruba 1 de 34 (`ok: 33   falhou: 1`) sai 0 (`vermelho`); com bateria sem placar reconhecível mantém o exit de hoje — provado por `bash scripts/testa-conferir-mutacao.sh` devolvendo os três casos novos `ok` e exit 0.

Nota (2026-09-11): a tarefa 22 substituiu o critério de exit 6 — a proporção de 20% saiu, e o que reprova agora é a bateria ter colapsado (sem placar, ou `ok=0` e `falhou=0`). O `pronto quando` acima fica como registro do que esta tarefa entregou na época; o caso dos "9 de 34" hoje sai `vermelho`, não 6, e é a bateria da 22 que guarda a fronteira nova. O bloco `mutacao:` foi reapontado para o nome atual da função.


### 12. Abertura avisa principal atrasado e worktrees já integrados [tipo: implementar]
atende: D12
arquivos: `hooks/foco-session-start.cjs`, `hooks/lib/contexto-sessao.cjs`, `hooks/lib/principal-atrasado.cjs`, `hooks/testa-principal-atrasado.sh`
(emenda 2026-09-09: `contexto-sessao.cjs` entrou porque é ele quem monta o rodapé que o hook de abertura imprime — a seção nova não tem outro lugar por onde sair)
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/principal-atrasado.cjs`
  de: `if (atras > 0)`
  para: `if (atras > 999999)`
  bateria: `bash hooks/testa-principal-atrasado.sh`
  fixture: principal 3 commits atras de origin/main imprime a linha
pronto quando: com um repositório sintético cujo checkout principal está 3 commits atrás de `origin/main` (remoto local via `git clone --bare`) e um worktree linkado numa branch já contida em `origin/main`, `node -e "console.log(require('./hooks/lib/principal-atrasado.cjs').linhas({cwd}))"` devolve uma linha contendo `3 commit(s) atrás de origin/main` e `git -C <principal> pull --ff-only`, e outra nomeando o worktree como `já em origin/main`; em repositório sem `origin`, fora de git, ou em dia, devolve `[]` sem estourar; e o hook de abertura injeta essas linhas (bateria roda `node hooks/foco-session-start.cjs` com payload de SessionStart e confere o texto) — provado por `bash hooks/testa-principal-atrasado.sh` exit 0.

### 13. ferramentas-consulta: timeout por env e caso `incerto` [tipo: implementar]
atende: D13
arquivos: `hooks/ferramentas-consulta.cjs`, `hooks/testa-ferramentas-consulta.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/ferramentas-consulta.cjs`
  de: `return respondeu ? { achado: false } : { achado: false, incerto: true };`
  para: `return { achado: false };`
  bateria: `bash hooks/testa-ferramentas-consulta.sh`
  fixture: RFM_FERRAMENTAS_TIMEOUT_MS=1 anuncia prossigo sem garantia
pronto quando: com `RFM_FERRAMENTAS_TIMEOUT_MS=1` e um executável real a sondar, o hook sai 0, o stdout contém `prossigo sem garantia` e o ledger não recebe linha nova; sem a variável o timeout continua 2000 ms — provado por `bash hooks/testa-ferramentas-consulta.sh` devolvendo o caso novo `ok` e exit 0.

### 14. limpar-worktrees respeita sessão viva [tipo: implementar]
atende: D14
arquivos: `scripts/limpar-worktrees.cjs`, `scripts/testa-limpar-worktrees.sh`, `skills/limpar/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/limpar-worktrees.cjs`
  de: `if (sessaoViva) return 'de-outra-sessao';`
  para: `if (false) return 'de-outra-sessao';`
  bateria: `bash scripts/testa-limpar-worktrees.sh`
  fixture: worktree limpo com sessao viva de outro id nao e removido
pronto quando: com `sessoes.json` sintético (`RFM_ROOT`) contendo outra sessão com `prompt_ts` recente e `cwd` igual a um worktree limpo, `node scripts/limpar-worktrees.cjs` lista esse worktree como `de-outra-sessao` e `--remover` **não** o remove (ele continua em `git worktree list`); com a sessão com timestamp de 5 h atrás, volta a ser `limpo` e é removido — provado por `bash scripts/testa-limpar-worktrees.sh` devolvendo os dois casos novos `ok` e exit 0; `skills/limpar/SKILL.md` descreve o terceiro eixo com o mesmo nome de status que o código imprime.

### 15. Backup rotativo compartilhado [tipo: implementar]
atende: D15
arquivos: `scripts/lib/backup-rotativo.cjs`, `scripts/foco.cjs`, `scripts/ideias.cjs`, `scripts/divergencias.cjs`, `scripts/ferramentas.cjs`, `scripts/testa-backup-rotativo.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/lib/backup-rotativo.cjs`
  de: `while (candidatos.length > teto)`
  para: `while (false)`
  bateria: `bash scripts/testa-backup-rotativo.sh`
  fixture: 11 gravacoes com teto 10 deixam 10 backups
pronto quando: com `RFM_ROOT` numa pasta temporária, 11 chamadas seguidas a `node scripts/ideias.cjs plantar …` deixam exatamente 10 arquivos em `.ideias-backups/` e o mais antigo foi o removido; o mesmo para `divergencias.cjs` e `ferramentas.cjs` nas pastas de backup deles; `foco.cjs rotacionar --aplicar` continua com o comportamento de hoje (`bash scripts/testa-foco.sh` verde) — provado por `bash scripts/testa-backup-rotativo.sh` exit 0 e as baterias `testa-ideias.sh`, `testa-divergencias.sh`, `testa-ferramentas.sh`, `testa-foco.sh` continuando exit 0.

### 16. Perfil de trabalho: asserção de contagem e peça chamada [tipo: docs]
atende: D16
arquivos: `referencias/perfil-de-trabalho.md`, `agents/*.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de método; a sincronia fonte → nove agentes é o que `testa-perfil.sh` confere
pronto quando: com as duas linhas novas na fonte e `node scripts/perfil.cjs --aplicar` rodado, `bash scripts/testa-perfil.sh` sai 0 e `grep -c "asserção de contagem" agents/*.md` devolve 1 em cada um dos nove; apagar a linha só de `agents/executor.md` faz `testa-perfil.sh` sair ≠ 0 (rodar e desfazer).

### 17. atualizar-cli.sh com lock [tipo: implementar]
atende: D17
arquivos: `scripts/atualizar-cli.sh`, `scripts/testa-atualizar-cli.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/atualizar-cli.sh`
  de: `mkdir "$LOCK" 2>/dev/null || exit 0`
  para: `true`
  bateria: `bash scripts/testa-atualizar-cli.sh`
  fixture: duas execucoes simultaneas nao se atropelam
pronto quando: com duas invocações de `scripts/atualizar-cli.sh` disparadas em paralelo contra a mesma pasta sintética (dublê de rede que dorme 2 s), exatamente uma faz o trabalho e a outra sai 0 sem tocar em nada; lock com mtime > 5 min é removido e o trabalho roda; lock recente faz sair 0 sem tocar; dublê de rede falhando deixa cache e backup existentes intactos — provado por `bash scripts/testa-atualizar-cli.sh` devolvendo os quatro casos novos `ok` e exit 0.

### 18. conferir-versao busca origin/main antes de comparar [tipo: implementar]
atende: D18
arquivos: `scripts/conferir-versao.cjs`, `scripts/testa-conferir-versao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-versao.cjs`
  de: `if (!opts.semFetch) buscarOrigem(`
  para: `if (false) buscarOrigem(`
  bateria: `bash scripts/testa-conferir-versao.sh`
  fixture: origin/main local velho e remoto com versao igual recusa apos fetch
pronto quando: com dois clones de um remoto bare — o segundo bumpa `plugin.json` para `1.3.0` e faz push, o primeiro tem `origin/main` local ainda em `1.2.0` e declara `1.3.0` — `node scripts/conferir-versao.cjs` no primeiro sai 2 dizendo `nao e maior que a de origin/main (1.3.0)`, e com `--sem-fetch` sai 0 (comportamento antigo); com remoto inacessível imprime `aviso: fetch falhou` e segue com a ref local — provado por `bash scripts/testa-conferir-versao.sh` devolvendo os três casos novos `ok` e exit 0.

### 19. Versão 1.12.0 [tipo: configurar]
atende: D19
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33
paralela: nao
mutacao: n/a
  motivo: número de versão; a divergência entre os dois lugares é o que `testa-versao.sh` já pega
pronto quando: com `plugin.json` e o badge do README em `1.12.0` (emenda 2026-09-12: a main já está em 1.11.0; era 1.10.0 quando a tarefa foi escrita), `bash scripts/testa-versao.sh` sai 0 e `node scripts/conferir-versao.cjs` sai 0 comparando com `origin/main`.

### 20. Caixa de areia das baterias copia `scripts/lib/` [tipo: teste]
atende: D15
arquivos: `scripts/testa-backup-estado.sh`, `scripts/testa-registrar-erro.sh`
depende de: 15
paralela: sim
mutacao: n/a
  motivo: a tarefa não muda comportamento de produção — `foco.cjs` e `backup-rotativo.cjs` ficam intactos. O que muda é o `montar()` das duas caixas de areia, que deixou de refletir a dependência real criada por D15. A prova não é mutante: é a bateria sair de 19 e 2 falhas para 0 com o fonte de produção sem uma linha alterada, e a mesma bateria continuar vermelha se a cópia for retirada.
pronto quando: `bash scripts/testa-backup-estado.sh` e `bash scripts/testa-registrar-erro.sh` saem 0 (hoje saem 1, com 36 ok/19 falhas e 70 ok/2 falhas, idênticos em `9700092` e na branch — não é regressão de tarefa nenhuma), sem que `git diff` toque `scripts/foco.cjs`, `scripts/backup.cjs` ou `scripts/lib/backup-rotativo.cjs`; e retirar a cópia de `scripts/lib/` do `montar()` de qualquer uma das duas devolve a bateria ao vermelho.

Nota de origem (2026-09-11): D15 extraiu o rodízio para `scripts/lib/backup-rotativo.cjs` e pôs `require('./lib/backup-rotativo.cjs')` no topo de `foco.cjs`. As duas baterias montam a caixa de areia listando arquivo por arquivo, e a lista não conhecia a pasta nova — todo teste que executa o fonte real morre com `MODULE_NOT_FOUND` antes de exercitar o que ele mede. O conserto copia o **diretório** `scripts/lib/`, não o arquivo: lista de dependências mantida à mão é o defeito, e nomear só `backup-rotativo.cjs` o repete na próxima lib.

### 21. `marcar verificar ok` lê o plano declarado, e a fixture prova a recusa [tipo: implementar]
atende: D9
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: 9
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (mutacoes.status !== 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-estado.sh`
  fixture: t6b com plano em disco e mutante sobrevivente; verificar recusa com a mensagem da catraca
pronto quando: `node scripts/conferir-mutacao.cjs --arquivo scripts/estado.cjs --de 'if (mutacoes.status !== 0) {' --para 'if (false) {' --bateria 'bash scripts/testa-estado.sh'` sai 0 com `vermelho` (hoje sai com `bateria VERDE com o comportamento invertido`); a fixture `t6b` monta o cenário até `verificar` exigível **sem nenhum `marcar` intermediário falhando** (cada um conferido por exit), tem plano de verdade em disco com bloco `mutacao:` cujo mutante sobrevive, e o `marcar verificar ok` recusa com exit 2 **citando `catraca de mutações não passou`** — a asserção passa a exigir a mensagem, não só o código; e `node scripts/estado.cjs marcar --slug <s> --estagio verificar --status ok` num fluxo cujo `plano.arquivo` aponta para nome diferente de `<slug>.md` roda a catraca em vez de pulá-la.

### 22. Teto de queda do `conferir-mutacao` para de reprovar bateria pequena [tipo: implementar]
atende: D11
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `function bateriaColapsou(`
  para: `function bateriaColapsou_desligada(`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: mutacao que quebra o mecanismo (bateria toda vermelha) continua recusada com exit 6
pronto quando: uma mutação que derruba a bateria INTEIRA (todas as asserções, o caso que D11 existe para pegar) continua saindo 6; e uma mutação eficaz numa bateria pequena — 13 asserções, 10 sobrevivem, 3 caem, que é a T12 deste plano — passa a sair 0 com `vermelho`, porque as 10 verdes são a prova de que o mecanismo de teste não quebrou; provado por `bash scripts/testa-conferir-mutacao.sh` exit 0 com os dois casos novos, e por `node scripts/conferir-fluxo.cjs mutacoes --slug zerar-issues` deixar de listar a tarefa 12 como `pulada (exit 6)`.

Nota de origem (2026-09-11): a 21 nasceu da própria catraca da 9 reprovando a 9 — `conferir-fluxo mutacoes` sobre este plano devolveu `tarefa 9: mutante sobreviveu`. O `if` da catraca de `verificar` nunca era alcançado porque `estado.cjs` procurava o plano por nome fixo `<slug>.md`, ignorando `plano.arquivo` do estado: fluxo com plano de outro nome pula a validação inteira em silêncio. A 22 nasceu da 12 sair `pulada (exit 6)`: o teto por proporção fixa pune bateria pequena e focada, e o caminho mais curto para o exit 0 passaria a ser inflar a bateria com asserções irrelevantes.

### 23. Bloco `mutacao:` aceita `timeout:`, e a pulada diz por quê [tipo: implementar]
atende: D9
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`
depende de: 9
paralela: sim
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `'--raiz', RAIZ,`
  para: `'--raiz', RAIZ, '--timeout', '1',`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: timeout declarado no bloco chega ao conferir-mutacao
pronto quando: um bloco `mutacao:` com `timeout: <ms>` faz `conferir-fluxo.cjs mutacoes` passar `--timeout <ms>` ao `conferir-mutacao.cjs` (provado por fixture cuja bateria dorme mais que o padrão e passa com o timeout declarado, e reprova sem ele); bloco sem `timeout:` continua usando o padrão do `conferir-mutacao`; e cada linha `pulada` passa a carregar a razão que o `conferir-mutacao` imprimiu — hoje `stdio: 'pipe'` engole o stderr e `exit 4` vira `não mensurável` para três causas diferentes (baseline não-verde, `--de` ambíguo, baseline estourou o teto), que é informação demais perdida numa palavra só — provado por `bash scripts/testa-conferir-fluxo.sh` exit 0 com os casos novos.

Nota de origem (2026-09-12): a tarefa 3 aparece como `pulada (não mensurável)` nas três rodadas da catraca, e a razão só apareceu quando rodei o `conferir-mutacao` à mão: `RECUSADO: baseline estourou o teto de 300000 ms` — `scripts/testa-saude.sh` leva mais que o teto padrão, e a catraca precisa rodá-la duas vezes. A bateria não está errada, o teto é que não é declarável por tarefa. Enquanto isso, a cobertura da tarefa 3 está perdida em silêncio, e `pulada` não reprova.

### 24. `valorSeguroParaShell` recusa contrabarra final; `despachar-codex` normaliza o worktree [tipo: implementar]
atende: D20
arquivos: `hooks/lib/cli-externo.cjs`, `scripts/despachar-codex.cjs`, `hooks/testa-cli-externo.sh`, `scripts/testa-cli-externo.cjs`, `scripts/testa-cli-externo.sh`, `scripts/testa-despachar-codex.sh`
(emenda 2026-09-12: os casos de `valorSeguroParaShell` moram em `scripts/testa-cli-externo.cjs`, que `scripts/testa-cli-externo.sh` executa — a T2 os havia declarado em `hooks/testa-cli-externo.sh`)
depende de: 2
paralela: sim
mutacao:
  arquivo: `hooks/lib/cli-externo.cjs`
  de: `if (valor.endsWith('\\')) return false;`
  para: `if (false) return false;`
  bateria: `bash hooks/testa-cli-externo.sh`
  fixture: valor terminado em contrabarra e recusado
pronto quando: `valorSeguroParaShell` contém, antes do teste de regex, a linha literal `if (valor.endsWith('\\')) return false;` (uma única ocorrência no arquivo); com `C:\tmp\x\` e `C:\tmp\x\\` devolve `false`, com `C:\tmp\x` e `C:/Users/Alguem Com Espaco/x.md` devolve `true`; `scripts/despachar-codex.cjs` passa `--worktree` por `path.resolve` antes de validar, então `--worktree 'C:\tmp\x\'` (com o diretório existindo) é aceito e o dublê do Codex (`RFM_TEST=1`), ecoando o argv que recebeu, mostra `-C`, `-c` e `-o` como argumentos SEPARADOS — nunca um só; `--saida 'C:\tmp\x\'` continua recusado com `valor invalido: --saida` — provado por `bash hooks/testa-cli-externo.sh` e `bash scripts/testa-despachar-codex.sh` devolvendo os casos novos `ok` e exit 0.

### 25. `marcar verificar ok` passa `--plano` à catraca, e o `t6b` afirma o mutante [tipo: implementar]
atende: D21
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: 21
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `'--slug', slug, '--plano', arquivo_plano]`
  para: `'--slug', slug]`
  bateria: `bash scripts/testa-estado.sh`
  fixture: t6b — a saida do marcar verificar ok contem 'mutante sobreviveu' vindo do plano t6-mut.md
pronto quando: o `spawnSync` do `conferir-fluxo.cjs mutacoes` em `estado.cjs` recebe o array literal `['mutacoes', '--slug', slug, '--plano', arquivo_plano]` (é o mesmo `arquivo_plano` que o `existsSync` da linha acima já resolve por `docDoEstagio`); no `t6b` (plano `t6-mut.md`, slug `t6b`) a saída combinada do `marcar --estagio verificar --status ok` sai 2 e contém **as duas** strings `mutante sobreviveu` e `catraca de mutações não passou` (a asserção exige as duas; hoje só a segunda) — e com o `--plano` retirado a mesma chamada continua saindo 2 mas SEM `mutante sobreviveu`, que é o motivo errado que a fixture antiga aceitava; o comentário acima do bloco deixa de afirmar que o campo `plano.arquivo` é lido "pelo mesmo `docDoEstagio`" sem dizer que ele chega ao subprocesso — provado por `bash scripts/testa-estado.sh` exit 0 com `falhou=0`.

### 26. Guarda `testa-sandbox-com-trap.sh` fecha os três buracos [tipo: teste]
atende: D22
arquivos: `scripts/testa-sandbox-com-trap.sh`, `scripts/testa-ferramentas.sh`, `scripts/testa-limpar-worktrees.sh`, `hooks/testa-principal-atrasado.sh`, `scripts/testa-conferir-ponte.sh`, `scripts/testa-conferir-publicacao.sh`
(emenda 2026-09-12: os dois últimos chegaram pela main depois do plano, com 2 e 5 `mktemp -d` sem o idioma — a guarda os reprovou na integração e a conversão entra aqui)
depende de: 10
paralela: sim
mutacao:
  arquivo: `scripts/testa-sandbox-com-trap.sh`
  de: `sem_comentario "$f" | grep -q 'SANDBOXES'`
  para: `grep -q 'SANDBOXES' "$f"`
  bateria: `bash scripts/testa-sandbox-com-trap.sh --autoteste`
  fixture: autoteste (d) — dois mktemp -d com SANDBOXES so em comentario e reprovada
pronto quando: `checar_arquivo` usa uma função `sem_comentario()` (`grep -v '^[[:space:]]*#' "$1"`) para TODAS as buscas (`mktemp -d`, `SANDBOXES`, `trap`), com a string `sem_comentario "$f" | grep -q 'SANDBOXES'` ocorrendo exatamente uma vez no arquivo; e reprova, nomeando o arquivo e o motivo, cada um destes fixtures novos do `--autoteste`: (d) dois `mktemp -d` e `SANDBOXES` só dentro de comentário; (e) um `mktemp -d` com `trap 'echo tchau' EXIT` (a linha do trap, ou a função que ela nomeia, tem de conter `rm -rf`); (f) `mktemp -d` dentro de uma função sem `SANDBOXES+=` no corpo (conta como múltiplo e exige o idioma), enquanto (g) `mktemp -d` dentro de função cujo corpo tem `SANDBOXES+=` e um `trap cleanup EXIT` com `cleanup()` contendo `rm -rf` passa — os três casos antigos continuam; e `bash scripts/testa-sandbox-com-trap.sh` sem argumento sai 0 sobre o repositório, convertendo para o idioma os `testa-*.sh` que a guarda endurecida reprovar (os três listados em `arquivos:` perderam a conversão no merge da main; qualquer outro que reprove entra por emenda deste `arquivos:`, nunca por afrouxar a regra) — provado por `bash scripts/testa-sandbox-com-trap.sh --autoteste; bash scripts/testa-sandbox-com-trap.sh` ambos exit 0 e cada bateria convertida continuando exit 0.

### 27. `testa-ferramentas-consulta.sh` captura o exit do hook, não do `unset` [tipo: teste]
atende: D23
arquivos: `hooks/testa-ferramentas-consulta.sh`
depende de: 13
paralela: sim
mutacao:
  arquivo: `hooks/ferramentas-consulta.cjs`
  de: `anunciar(sonda.incerto ? "incerto" : "bloqueio", executavel);`
  para: `anunciar(sonda.incerto ? "incerto" : "bloqueio", executavel); if (sonda.incerto) process.exit(1);`
  bateria: `bash hooks/testa-ferramentas-consulta.sh`
  fixture: TIMEOUT 1 — 'ok exit 0 (D10)' passa a falhar quando o hook sai 1 no ramo incerto
pronto quando: nos dois casos de timeout (`RFM_FERRAMENTAS_TIMEOUT_MS=1` e `=abc`) a linha `EXIT=$?` vem IMEDIATAMENTE após a linha `SAIDA=$(printf ... | node "$HOOK" 2>&1)` — nenhum comando entre as duas, `unset` só depois — e a linha morta `SAIDA=$(RFM_FERRAMENTAS_TIMEOUT_MS=1 bash -c ...)` e a `UNSET_TIMEOUT=$(unset ...)` saem; com o hook íntegro a bateria sai 0, e com o hook saindo 1 no ramo incerto (a mutação acima) a asserção `ok exit 0 (D10)` do caso TIMEOUT 1 vira FALHA e a bateria sai ≠ 0 — provado por `bash hooks/testa-ferramentas-consulta.sh` exit 0 e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 28. `conferir-mutacao` roda a bateria em bash no Windows e sem bytecode Python [tipo: implementar]
atende: D24, D25
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: 22
paralela: sim
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `PYTHONDONTWRITEBYTECODE: '1',`
  para: `PYTHONDONTWRITEBYTECODE_desligado: '1',`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: bateria que grava $PYTHONDONTWRITEBYTECODE num arquivo e afirma '1'
pronto quando: `rodaBateria` monta o comando por uma função `comandoDaBateria(bateria)` que devolve `{ cmd, args, shell }`: em `process.platform === 'win32'` com `bash` resolvível no PATH devolve `{ cmd: 'bash', args: ['-c', bateria], shell: false }`; em win32 sem `bash` e com `;`, `&&` ou `||` na bateria, `main()` sai 1 imprimindo `bateria com encadeamento de shell e cmd.exe nao separa comandos — instale o Git Bash ou remova o encadeamento`; fora do Windows continua `shell: true`; o `env` do `spawnSync` é `{ ...process.env, PYTHONDONTWRITEBYTECODE: '1' }` (a chave literal `PYTHONDONTWRITEBYTECODE: '1',` ocorre uma vez no arquivo) no baseline e na pós-mutação; a ajuda deixa de dizer que `SHELL=/bin/bash` tem efeito no Windows. Casos novos em `scripts/testa-conferir-mutacao.sh`: (a) só quando `uname -o` contém `Msys`: `--bateria 'touch marca-a; touch marca-b'` com `--raiz` numa sandbox deixa `marca-a` e `marca-b` e NÃO deixa arquivo chamado `touch` nem `marca-a;` (cmd.exe teria criado os dois errados); (b) fixture cuja bateria roda `printf '%s' "$PYTHONDONTWRITEBYTECODE" > env.txt` e o teste afirma que `env.txt` contém exatamente `1` nas duas rodadas; (c) se `python`/`python3` existir no PATH: módulo com `VALOR = 1.5e9`, mutação para `0.5e9` (mesmo tamanho), bateria em Python que importa o módulo — depois da catraca, não existe `__pycache__/*.pyc` do módulo e uma segunda execução da bateria sobre o fonte restaurado sai verde; sem Python, o caso imprime `(pulado: sem python)` e não conta — provado por `bash scripts/testa-conferir-mutacao.sh` exit 0 com os casos novos `ok`.

### 29. Gate `gate-verificador-staged`: o verificador do repo barra o commit [tipo: implementar]
atende: D26
arquivos: `hooks/gate-verificador-staged.cjs`, `hooks/testa-gate-verificador-staged.sh`, `hooks/hooks.json`, `hooks/testa-fuga-de-escotilha.sh`
depende de: 4
paralela: sim
mutacao:
  arquivo: `hooks/gate-verificador-staged.cjs`
  de: `if (resultado.status !== 0) {`
  para: `if (false) {`
  bateria: `bash hooks/testa-gate-verificador-staged.sh`
  fixture: repo sintetico com verificador que reprova SEGREDO e arquivo staged contendo SEGREDO -> exit 2
pronto quando: com payload `PreToolUse` de `Bash` cujo `command` é `git commit -m x` num repo git sintético que tem `.rainforest/config.json` com `"verificador-staged": "bash scripts/verifica.sh"` (o script sai 1 se algum argumento contém `SEGREDO`) e um arquivo staged contendo `SEGREDO`, o gate sai 2 e o stderr contém a saída do verificador e `BLOQUEADO`; com o mesmo arquivo SUJO no working tree mas o conteúdo STAGED limpo, sai 0 (é o blob staged que se olha — `git show :<caminho>`); sem verificador declarado e com `scripts/check-personal-data.py` presente, ele é chamado com os caminhos materializados; sem nenhum verificador, sai 0; comando que não é `git commit` sai 0 sem rodar nada; com `agent_id` no payload o stderr não contém `.rainforest-gate-off` nem `RAINFOREST_GATE_OFF`, e sem `agent_id` nomeia as saídas como os irmãos; `hooks/hooks.json` registra o gate ao lado de `gate-git-verificacao.cjs`; `hooks/testa-fuga-de-escotilha.sh` passa a rodar cinco gates — provado por `bash hooks/testa-gate-verificador-staged.sh` e `bash hooks/testa-fuga-de-escotilha.sh` exit 0.

### 30. Regra `telefone` isenta id de plataforma por prefixo [tipo: implementar]
atende: D27
arquivos: `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: `if (PREFIXO_DE_ID_DE_PLATAFORMA.test(antes)) return false;`
  para: `if (false) return false;`
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: linha com actions/runs/34692512345 passa sem achado
pronto quando: existe a constante `PREFIXO_DE_ID_DE_PLATAFORMA` (regex ancorada no FIM do trecho anterior ao match: `runs/`, `jobs/`, `issuecomment-`, `pull/`, `issues/`, `/commit/`, `discussion_r`) e, no `so_se` da regra `telefone`, `antes` é `linha.substring(0, m.index)` e a linha literal `if (PREFIXO_DE_ID_DE_PLATAFORMA.test(antes)) return false;` ocorre uma vez; `node scripts/conferir-publicacao.cjs -` com stdin `https://github.com/x/y/actions/runs/34692512345` sai 0, com `#issuecomment-2345678901` sai 0, com `pull/12345678901` sai 0; com `5547999998888` continua saindo 2 (`telefone`), e com `contato: 47 99999-8888` idem; `runs/` sem dígito colado (`runs/ 5547999998888`) continua 2 — provado por `bash scripts/testa-conferir-publicacao.sh` exit 0 com os casos novos.

### 31. `marcar` respeita a ordem dos estágios e valida o carimbo [tipo: implementar]
atende: D28
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`, `skills/executar/SKILL.md`
depende de: 25
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const posterior_aberto = estagioPosteriorAberto(estado, estagio, status);`
  para: `const posterior_aberto = null;`
  bateria: `bash scripts/testa-estado.sh`
  fixture: marcar executar parcial com revisar parcial e em_voo nao vazio -> exit 2, arquivo intacto
pronto quando: com `revisar` em `parcial` (com `em_voo` não vazio) ou em `ok`, `node scripts/estado.cjs marcar --slug <s> --estagio executar --status parcial --json '{...}'` sai 2, o stderr contém `revisar` e o JSON de estado fica byte a byte igual (`cmp` sem saída); com `revisar` em `reprovado` a mesma chamada continua saindo 0 (é a reabertura sancionada — e é o estado real do fluxo `zerar-issues` hoje); `marcar --estagio executar --status parcial --json '{"carimbos":[{"tarefa":99,"hash_base":"<sha>"}]}'` com `tarefas: 1` gravado sai 2 nomeando `99`, e sem `tarefas` gravado continua aceitando; `marcar --estagio revisar --status parcial` com `executar` em `pendente` sai 2 nomeando `executar` (a ordem de `PRE_REQUISITOS`), enquanto `marcar --estagio design --status aprovado` num fluxo recém-iniciado continua saindo 0; a função chama-se `estagioPosteriorAberto` e a linha `const posterior_aberto = estagioPosteriorAberto(estado, estagio, status);` ocorre uma vez; e `skills/executar/SKILL.md` diz, no parágrafo do carimbo, que o exemplo se prova num slug de caixa de areia (`iniciar --slug caixa`), nunca no slug em curso — provado por `bash scripts/testa-estado.sh` exit 0 com os casos novos e os 217 existentes `ok`.

### 32. Revisor não muta: molde do briefing, recusa na primeira linha e mensagem do gate [tipo: implementar]
atende: D29
arquivos: `skills/revisar/SKILL.md`, `agents/revisor.md`, `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `const restauro = linhaDeRestauro(entrada.command || '', estado.toplevel);`
  para: `const restauro = '';`
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: subagente rodando git checkout -- x.txt no checkout principal e barrado e o stderr traz o comando de restauro para a janela
pronto quando: com payload de subagente (`agent_id` presente) cujo `command` é `git checkout -- x.txt` (e, em caso separado, `git restore x.txt`) num repo git sintético que é checkout principal, o gate sai 2 e o stderr contém `a restauracao e da janela principal` e `git -C <toplevel> checkout -- x.txt` (toplevel real do fixture), além do `PARE e reporte` de hoje; o mesmo payload com `git status` não ganha a linha; a função chama-se `linhaDeRestauro(cmd, toplevel)` e devolve `''` quando o comando não é restauro; `skills/revisar/SKILL.md` ganha a seção `## Molde do briefing do revisor` com a cláusula literal "não mute fonte nenhum; quando o achado só fecha com mutação, descreva-a (arquivo, linha a inverter, teste que deveria quebrar) — quem a executa é um `tester` isolado", e `agents/revisor.md` acrescenta ao item (i) que briefing que peça mutação é recusado na PRIMEIRA linha do relato, antes de qualquer leitura; `bash scripts/testa-teto-skills.sh` e `bash scripts/testa-perfil.sh` continuam exit 0 — provado por `bash hooks/testa-gate-worktree.sh` exit 0 com os casos novos.

### 33. README e travas: `mutacoes --plano`, guarda de sandbox e gate novo [tipo: docs]
atende: D21, D22, D26
arquivos: `README.md`, `docs/travas-mecanicas.md`
depende de: 25, 26, 29
paralela: nao
mutacao: n/a
  motivo: texto; a coerência com o código é o critério abaixo, e `testa-mapa-regras.sh` confere que todo arquivo citado existe
pronto quando: a linha de `scripts/conferir-fluxo.cjs` na tabela do README nomeia o subcomando `mutacoes --slug <slug> [--plano <arquivo>]` com os mesmos exits que `node scripts/conferir-fluxo.cjs mutacoes` sem args imprime; existe linha para `scripts/testa-sandbox-com-trap.sh` descrevendo as três regras da D22 (as mesmas do cabeçalho do script); a tabela de gates tem a linha de `gate-verificador-staged.cjs` com a ordem de descoberta da D26, e a soma de casos das baterias dos gates é re-medida (a última linha de cada `hooks/testa-gate-*.sh`, incluindo o novo) e a data atualizada; `docs/travas-mecanicas.md` cita o gate novo; `bash scripts/testa-mapa-regras.sh` sai 0 — provado por esses comandos e por `grep -c 'gate-verificador-staged' README.md docs/travas-mecanicas.md` devolvendo ≥ 1 em cada.
