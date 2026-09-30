# Seis travas do semear de 2026-09-30

## Objetivo
Transformar em mecanismo as seis famílias de defeito que o `semear` de 2026-09-30
achou reincidentes nas observações — critério que já passa na base, base de
worktree de agente acertada por texto, despacho anunciado sem despacho, design sem
varredura do que já existe, trava testada só pelo que barra, e edição por literal
sem asserção. Todas as decisões seguem a recomendada da rodada 1; o dono delegou
("pode fazer tudo como recomendado") e aprovou design e plano de antemão.

## Decisões fechadas
- **D1 — Critério do plano ganha campo `prova:` executável, e o `marcar --estagio plano` exige que ele falhe na base** — porquê: `prova-real-que-mede-outro-portao` (sete entregas), `criterio-executavel-precisa-ser-provado-ao-escrever-o-plano`, `obs-2026-09-18-env-antes-do-cano-aponta-raiz-real`. Tarefa de tipo `implementar|teste` declara `prova: \`<comando>\``; o `marcar` roda cada uma numa cópia descartável (worktree destacado) do HEAD atual, com timeout, e recusa (exit 2) se alguma sair 0. Tarefa `docs|pesquisa|configurar` é isenta. Critério verde na base por natureza declara `prova-na-base: verde — <motivo>` e é aceito com o motivo registrado. Extrair o comando das crases da prosa foi recusado (ver descartado).
- **D2 — `scripts/preparar-worktree.cjs` é a única instrução de base para agente, e `conferir-entrega --base` passa a ser obrigatório** — porquê: `executor-pula-ff-only-e-commita-na-base-velha` (2 de 6), `obs-2026-09-08-worktree-de-agente-nasceu-na-main-e-o-plano-nao-estava-la`, `obs-2026-09-08-conserto-provado-fora-da-branch`; hoje o ff-only é prosa em cinco `agents/*.md`, e `executor.md` (lista de hashes velhos) diverge de `regra-11.md`/`executar` (`--is-ancestor`). O script recebe `--hash <H> [--exige <arquivo>]`, faz `merge --ff-only H` quando HEAD é ancestral de H, confere HEAD == H e a existência de cada `--exige`, e sai ≠ 0 com a causa em qualquer divergência. `conferir-entrega` sem `--base` sai 2 em vez de avisar.
- **D3 — Hook de Stop `gate-turno-prometido.cjs` bloqueia (exit 2) turno que promete ação sem executá-la** — porquê: `janela-parou-de-despachar-em-silencio` (três reautorizações), `anuncio-de-despacho-sem-despacho-no-mesmo-turno`, `espera-por-servico-externo-parece-travamento-para-o-usuario`. Dois casos: (a) última resposta de texto do turno promete despacho no futuro/andamento ("vou despachar", "despachando", "disparo agora") e o turno não teve `tool_use` `Agent`/`Task`; (b) a resposta diz que espera máquina ("CI rodando", "aguardando o CI/build") e o turno não teve Bash com `run_in_background`, `Monitor` nem `ScheduleWakeup`. `stop_hook_active === true` sai 0 (sem laço). Só age na sessão principal (sem `agent_id`). Colhe a ideia `checador-deterministico-de-conformidade-de-regra-no-stop` como primeiro caso concreto.
- **D4 — `scripts/varrer.cjs` grava a varredura, e o design aprovado exige seção `## Varredura` citando o arquivo** — porquê: `varri-so-a-main-e-duplique-feature-2026-09-15` (#253 reimplementada), `desenhei-sem-varrer-as-issues`, `conferir-se-o-repo-ja-sabia-antes-de-chamar-de-descoberta`. `varrer.cjs --slug <s> <termo>...` consulta Issues (abertas e fechadas), PRs (todos os estados), branches remotas, `git log --all --grep` e `ideias.jsonl`, e grava `docs/rainforest/varredura/<slug>.txt` com termos, comandos e saída. O `conferir-fluxo design` recusa design sem a seção ou cujo arquivo citado não exista ou esteja vazio. Vale só para design novo: aprovado antes da entrega não é reconferido.
- **D5 — Replay de comandos reais contra as travas: extrator local + fixture curada versionada** — porquê: `trava-entrega-os-casos-que-ela-nao-pode-barrar` (relatorios/2026-09-01-trava-verde-que-so-testava-escrita.md), `gate-por-parser-de-shell-e-poco-sem-fundo`, `obs-2026-09-04-parser-de-shell-a-mao-troca-um-falso-positivo-por-outro`. `scripts/extrair-corpus-comandos.cjs` lê transcrições locais (os config dirs) e emite candidatos (comandos Bash que rodaram sem bloqueio de hook); uma fixture curada e limpa (`hooks/fixtures/corpus-comandos/legitimos.jsonl`, sem caminho de cliente, nome ou segredo, passada por varredura de segredo) é versionada; `hooks/testa-corpus-comandos.cjs` roda cada gate PreToolUse que avalia Bash contra cada comando nos contextos principal e subagente, e fica vermelho em qualquer bloqueio não listado em `esperados`. Com `RFM_CORPUS_LOCAL=<arquivo>` roda também o corpus completo da máquina.
- **D6 — `scripts/substituir.cjs` para edição literal com asserção, sem hook que obrigue** — porquê: `literal-com-escape-e-erro-que-nao-da-erro` (três vezes num dia), `substituicao-de-texto-sem-assercao-entrega-codigo-morto`. `--arquivo F --de A --para B [--ocorrencias N]`: lê de/para de arquivo (nada passa pelo shell), conta ocorrências (padrão 1), troca por split/join, relê e confere que o texto novo está lá e o antigo sumiu (quando o novo não o contém); sai ≠ 0 em contagem divergente. Citado no `modo-dev` e nos `agents/*.md` que editam.
- **D7 — As quatro observações já resolvidas no código são colhidas no `fechar`** — porquê: o semear achou `briefing-que-proibe-background-nao-impede-o-background` (#347), `rainforest-conferir-mutacao-envenena-o-pycache` e `catraca-bateria-vai-para-o-cmd-no-windows` (D25 do `conferir-mutacao.cjs`) e `limpar-remove-worktree-limpo-de-outra-sessao-sem-perguntar` (`limpar-worktrees.cjs` respeita `git worktree lock`) ainda marcadas `plantada`.

## Varredura
Varredura manual (o `varrer.cjs` nasce nesta entrega), 2026-09-30, base `038e9905`:
PR aberta única #361 (`fluxo/enxertos-poda-impressao`, vigias — não colide);
Issues por "pronto quando", "ff-only", "Stop", "varredura", "corpus", "substitu" —
todas fechadas, nenhuma com este mecanismo (#4/#53 trataram a base determinística,
#180 o turno que termina antes do agente, #192 background); nenhuma branch remota
com os temas.

## Avaliado e descartado
- Extrair o comando do `pronto quando:` das crases da prosa — é parser de texto livre, a mesma família que D5 existe para conter; prosa real mistura vários trechos em crase (`zerar-issues-9.md:99`).
- Hook PreToolUse que obrigue o `substituir.cjs` — seria mais uma trava que decide lendo o texto do comando shell (`gate-por-parser-de-shell-e-poco-sem-fundo`).
- Stop hook só avisando — aviso é texto, e o texto falhou três vezes (`janela-parou-de-despachar-em-silencio`).
- Corpus completo versionado — o repositório é público e as transcrições carregam caminho, cliente e eventualmente credencial.

## Fora de escopo
- Reconferir designs e planos já aprovados contra D1 e D4.
- Consertar os gates que o replay de D5 eventualmente reprovar: cada achado vira Issue, não conserto nesta entrega (salvo se bloquear a própria bateria).
- Outros casos de conformidade no Stop além dos dois de D3.

## Em aberto
