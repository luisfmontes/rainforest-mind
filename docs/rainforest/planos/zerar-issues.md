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
arquivos: `scripts/testa-conferir-fluxo.sh`, `scripts/testa-observar.sh`, `scripts/testa-saude.sh`, `hooks/testa-memoria-recuperacao.sh`, `scripts/testa-memoria-somente-leitura.sh`, `hooks/testa-contexto-sessao.sh`, `scripts/testa-orcamento.sh`, `hooks/testa-memoria-criticos-ponta-a-ponta.sh`, `hooks/testa-ferramentas-nao-toca-abertura.sh`, `scripts/testa-caminho-pessoal.sh`, `scripts/testa-dependencias-de-bateria.sh`, `scripts/testa-sandbox-com-trap.sh`, `README.md`
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

### 19. Versão 1.10.0 [tipo: configurar]
atende: D19
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22
paralela: nao
mutacao: n/a
  motivo: número de versão; a divergência entre os dois lugares é o que `testa-versao.sh` já pega
pronto quando: com `plugin.json` e o badge do README em `1.10.0`, `bash scripts/testa-versao.sh` sai 0 e `node scripts/conferir-versao.cjs` sai 0 comparando com `origin/main`.

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
