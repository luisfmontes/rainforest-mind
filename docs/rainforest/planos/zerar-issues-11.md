# Plano: Zerar as Issues abertas, rodada 11 — mensagem do `bash $t` (#337) e trava de gatilho sob demanda (#302)

Design: docs/rainforest/design/zerar-issues-11.md

## O que não pode quebrar
- `gate-fechar-issue` continua barrando tudo que barra hoje, incluindo `bash $t` sem aspas, `bash -c "$x"` e `eval "$x"` (→ 2), e continua liberando `bash "$t"` (→ 0).
- `bash scripts/varrer-baterias.sh` continua sem rede, credencial nem custo: nenhuma bateria chama o `claude` de verdade.
- Os 21 `evals/*/case.yaml` entram byte a byte como estão no `origin/fluxo/eval-gatilho-302`.

## Tarefas

### 1. Mensagem do bloqueio de wrapper ilegível orienta `bash "$t"` (#337) [tipo: implementar]
atende: D1
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `      `Rodando um arquivo cujo caminho está numa variável? Ponha aspas: bash "$t" passa, bash $t não.\n\n` : ``) +`
  para: `      `` : ``) +`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, caso "(#337) for t in a b; do bash $t; done"
pronto quando: com o payload PreToolUse real (`{"tool_name":"Bash","tool_input":{"command":...}}`), `for t in a b; do bash $t; done` e `f=x.sh; bash $f 2>&1 | tail -1` saem **2** com `bash "$t"` no stderr; `for t in a b; do bash "$t"; done` sai 0; `bash -c "$x"` sai 2 — provado por `bash hooks/testa-gate-fechar-issue.sh` com 0 falhas e os casos "(#337)" impressos.

### 2. Trava de gatilho sob demanda com `claude` falso (#302) [tipo: implementar]
atende: D2, D3, D4
arquivos: `evals/**` (21 casos + `evals/README.md`), `.gitignore`, `scripts/eval-gatilho.sh`, `scripts/testa-eval-gatilho.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/eval-gatilho.sh`
  de: `    if [ $((ok_rodadas * 2)) -gt "$rodadas" ]; then`
  para: `    if true; then`
  bateria: `bash scripts/testa-eval-gatilho.sh`
  fixture: testa-eval-gatilho.sh, caso "trava: caso com 1 de 3 rodadas verdes reprova"
pronto quando: `bash scripts/testa-eval-gatilho.sh` (sem rede; `CLAUDE_BIN` apontando para um `claude` falso criado pela bateria em `mktemp -d`, que registra os argumentos de cada chamada e decide o exit por um roteiro) imprime cada caso e termina com 0 falhas, cobrindo: (a) `trava --case <glob>` chama o CLI uma vez por caso **e por rodada** (3 por padrão, `--rodadas N` muda), sempre com `plugin eval`, `--ablation none`, `--runs 1`, `--threshold 1.0`, `--no-publish`, `--trust-plugin` e `--case <nome exato do caso>` (nome lido do `name:` do `case.yaml`); (b) 2 de 3 rodadas em exit 0 → caso aprovado, 1 de 3 → reprovado, e a trava sai 1 se algum caso reprovar e 0 se todos passarem; (c) exit 2 do CLI (teto de custo) interrompe a trava na hora com exit 2 e mensagem dizendo teto; (d) `mutacao <skill>` roda contra uma **cópia** (diretório temporário com os arquivos rastreados) onde a linha `description:` de `skills/<skill>/SKILL.md` foi trocada, deixa a árvore real intacta (`git status --porcelain` vazio antes e depois), usa só os casos `gatilho-<skill>-vs-*-pos*`, sai 0 quando a trava fica vermelha e 3 quando fica verde (mutação não percebida); o `claude` falso reprova quando acha a description sabotada no diretório que recebeu; (e) `baseline` chama o CLI uma vez com `--ablation with-without`; (f) sem `claude` resolvível sai 127 com mensagem. `bash -n scripts/eval-gatilho.sh` limpo. Os 21 `case.yaml` idênticos aos do `origin/fluxo/eval-gatilho-302` (`git diff origin/fluxo/eval-gatilho-302 -- evals/*/case.yaml` vazio), e o `evals/README.md` ganha uma seção no topo dizendo como rodar a trava, a mutação e o baseline pelo script, a emenda do critério 3 (sob demanda, fora do CI) e que o critério 4 ainda não rodou pago.

### 3. Registro e versão [tipo: docs]
atende: D5, D6
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto de registro e versão, sem comportamento a inverter
pronto quando: o CHANGELOG ganha a versão minor sobre `origin/main` descrevendo o efeito medido (mensagem nova do bloqueio; script de trava e o que a bateria prova; o que não rodou pago); o README cita `scripts/eval-gatilho.sh` onde lista scripts e o badge acompanha a versão; `bash scripts/testa-versao.sh` com 0 falhas.

## Emendas da integração (2026-09-28)
- **Tarefa 2:** na leitura do script entregue, `mutacao` tratava qualquer saída ≠ 0 da trava como "mutação detectada" — teto de custo (2) e nenhum caso casado (que também saía 1) viravam exit 0. Agora nenhum caso casado sai 4, e a mutação só conta como detectada com exit 1; o resto é repassado como inconclusivo. O script também vai para a raiz do repositório (`git rev-parse --show-toplevel`) antes de ler `evals/`. Dois casos novos na bateria (13/0); mutação na linha `  if [ "$exit_trava" -ne 1 ]; then` → `  if false; then`: vermelha.
- **Revisão 1 (reprovada):** `mutacao` declarava detecção (exit 0) quando o CLI falhava por qualquer motivo alheio à sabotagem — a saída do CLI era descartada e todo exit ≠ 0/2 contava como rodada reprovada. Conserto: só exit 1 (score abaixo do `--threshold`, contrato do CLI) é veredito; exit fora de 0/1/2, ou exit 1 com ` error: ` na linha da rodada (timeout, max_turns — formato da saída real registrada em `evals/README.md`), aborta a trava com 5 mostrando a saída do CLI, e a mutação repassa como inconclusiva. `trap` limpa a cópia em Ctrl-C; os exits estão documentados no cabeçalho e no `evals/README.md`. Não-bloqueante acatado: a orientação de `bash "$t"` só aparece quando o segmento é `bash|sh $VAR` (a mutação da tarefa 1 passa a mirar a linha com o ternário). Casos novos: (g) nas duas formas (15/0) e o controle `bash -c "$x"` sem a orientação (246/0); mutações `1) ;;` → `*) ;;` e `exit_cli=5` → `exit_cli=1`, as duas vermelhas.
- **Revisão 2 (ok):** não-bloqueante registrado como limite — o ` error: ` é procurado na saída inteira do CLI, então uma reprovação legítima cujo texto do juiz contenha a substring vira abortada (5) em vez de reprovação. Erra para o lado seguro (nunca vira "aprovado" nem "detectada"); a primeira rodada paga mostra se vale casar só a linha da rodada.
