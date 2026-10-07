# Plano: Transferir sessão entre contas do Claude Code

Design: docs/rainforest/design/2026-10-06-transferir-entre-contas.md

## O que não pode quebrar
- `/transferir` sem argumento continua indo para o Codex, com a chave `transfer-codex` exigida como hoje (exit 3 desligada).
- A bateria `scripts/testa-transferir-para-codex.sh` continua verde nos casos que já tem.
- Nenhum teste lê ou escreve em `~/.claude` ou `~/.claude-personal` reais: tudo em caixa de areia (`RFM_TEST=1` + `RFM_HOME`), como a bateria do Codex já faz.
- A sessão de origem nunca é alterada nem apagada pela transferência (D4).

## Tarefas

### 1. Lib de contas + script `transferir-entre-contas.cjs` + bateria [tipo: implementar]
atende: D3, D4, D5, D6, D7, D8, D9
arquivos: `hooks/lib/contas-claude.cjs`, `scripts/transferir-entre-contas.cjs`, `scripts/testa-transferir-entre-contas.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-transferir-entre-contas.sh`
mutacao:
  arquivo: `scripts/transferir-entre-contas.cjs`
  de: `if (existe && !opts.forcar)`
  para: `if (false)`
  bateria: `bash scripts/testa-transferir-entre-contas.sh`
  fixture: `testa-transferir-entre-contas.sh, caso "destino ja tem a sessao: recusa sem --forcar e nao altera o destino"`
pronto quando: com o transcript REAL de uma sessão descartável criada por `claude -p --model haiku --output-format json "Memorize a palavra-senha <PALAVRA> e responda apenas: ok"` na conta de trabalho (sem `CLAUDE_CONFIG_DIR`), `CLAUDE_CODE_SESSION_ID=<id> node scripts/transferir-entre-contas.cjs` copia `<id>.jsonl` (e a pasta `<id>/` se existir) para `~/.claude-personal/projects/<mesmo slug>/`, deixa a origem com o mesmo sha256, imprime como últimas linhas `cd "<cwd do transcript>"` e `CLAUDE_CONFIG_DIR="<home>/.claude-personal" claude --resume <id>`, e rodar essa linha com `-p "Qual era a palavra-senha? Responda so a palavra."` devolve `<PALAVRA>`; uma segunda execução sai com exit 4 e a mensagem cita `--forcar`. Os arquivos da sessão descartável são apagados das duas contas ao fim — provado pela sequência acima rodada à mão no `verificar`, com a saída colada.

Requisitos que a implementação segue (vêm do design, não são opção):
- `hooks/lib/contas-claude.cjs` exporta funções puras com `home` injetável: `contaAtual(env, home)` → `'trabalho'` (CLAUDE_CONFIG_DIR vazio ou `<home>/.claude`) | `'pessoal'` (`<home>/.claude-personal`) | `null` (qualquer outra pasta); `outraConta(conta)`; `dirConta(conta, home)`; `dentroDeProjetos(caminho, home)` → true se o caminho resolvido está sob `<home>/.claude/projects` ou `<home>/.claude-personal/projects`. Home = `RFM_HOME` só com `RFM_TEST=1`, senão `os.homedir()` (mesma convenção do script do Codex).
- O script acha o transcript por `CLAUDE_CODE_SESSION_ID` procurando `<conta atual>/projects/*/<id>.jsonl`; sem a variável ou sem o arquivo, exit 1 com mensagem que diz qual faltou.
- Destino: `outraConta` por padrão; `--para pessoal|trabalho` explícito; `--para` igual à conta atual ou valor desconhecido → exit 1. Conta atual `null` → exit 1 citando o `CLAUDE_CONFIG_DIR` lido.
- Cópia: `<id>.jsonl` e, se existir, a pasta irmã `<id>/` inteira, para `<destino>/projects/<mesmo slug>/`. A colisão é testada exatamente pela linha `if (existe && !opts.forcar)` (alvo da mutação), com `existe` = o `.jsonl` destino existe; recusa sai exit 4 sem tocar no destino.
- O `cwd` da linha de retomada sai do campo `cwd` da primeira linha do transcript que o tenha; sem nenhum, exit 1.
- Saída final: linha `cd "<cwd>"`, depois a linha de retomada (com `CLAUDE_CONFIG_DIR="<dir>" ` antes quando o destino é a pessoal; sem prefixo quando é a de trabalho), e uma linha dizendo para fechar a janela de origem.
- Fixtures da bateria em formato de transcript REAL (linhas com `type`, `sessionId`, `cwd`, `message`), nunca campos inventados; casos mínimos: cópia feliz pessoal→trabalho e trabalho→pessoal com pasta `<id>/` junto; origem com hash intacto; colisão sem `--forcar` (exit 4, destino intacto); colisão com `--forcar` (sobrescreve); `--para` igual à atual (exit 1); sem `CLAUDE_CODE_SESSION_ID` (exit 1); `CLAUDE_CONFIG_DIR` desconhecido (exit 1); transcript sem `cwd` (exit 1). Zero caso pulado.

### 2. `/transferir` para Codex aceita transcript das duas contas [tipo: implementar]
atende: D10
arquivos: `scripts/transferir-para-codex.cjs`, `scripts/testa-transferir-para-codex.sh`
depende de: 1
paralela: nao
prova-na-base: verde — a bateria do Codex já existe e é verde na base por invariante; o caso que falharia (transcript em .claude-personal) nasce nesta tarefa, e a falha da base fica provada pela mutação, que devolve a lib ao comportamento da base
mutacao:
  arquivo: `hooks/lib/contas-claude.cjs`
  de: `const PASTAS_DE_CONTA = ['.claude', '.claude-personal'];`
  para: `const PASTAS_DE_CONTA = ['.claude'];`
  bateria: `bash scripts/testa-transferir-para-codex.sh`
  fixture: `testa-transferir-para-codex.sh, caso novo "transcript em .claude-personal/projects e aceito"`
pronto quando: com um transcript em formato real posto em `<RFM_HOME>/.claude-personal/projects/<slug>/<id>.jsonl` e o dublê do Codex, `node scripts/transferir-para-codex.cjs --source <esse arquivo>` sai 0 com `codex resume <id>` na última linha (hoje sai exit 2 citando `.claude/projects`), e um transcript fora das duas pastas continua saindo exit 2 — provado pelos casos novos de `bash scripts/testa-transferir-para-codex.sh`, com os casos antigos ainda verdes.

`validarCaminhoTranscript` passa a usar `dentroDeProjetos` da lib da tarefa 1, e a lib declara as pastas exatamente na linha `const PASTAS_DE_CONTA = ['.claude', '.claude-personal'];` (alvo da mutação). A mensagem do exit 2 cita as duas pastas.

### 3. Despacho do `/transferir` por destino [tipo: implementar]
atende: D2
arquivos: `scripts/transferir.cjs`, `commands/transferir.md`, `scripts/testa-transferir.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-transferir.sh`
mutacao:
  arquivo: `scripts/transferir.cjs`
  de: `const paraClaude = argv[0] === 'claude';`
  para: `const paraClaude = false;`
  bateria: `bash scripts/testa-transferir.sh`
  fixture: `testa-transferir.sh, caso "primeiro argumento claude despacha para transferir-entre-contas"`
pronto quando: com `$ARGUMENTS` como o harness passa ao comando (`claude`, `claude --para trabalho`, vazio, `--ultimas 3`), `node scripts/transferir.cjs <args>` executa `transferir-entre-contas.cjs` com o resto dos argumentos quando o primeiro é `claude`, e `transferir-para-codex.cjs` com os argumentos intactos em qualquer outro caso, repassando o exit code do filho — provado por `bash scripts/testa-transferir.sh` com scripts-filho dublês que gravam argv e saem com código conhecido; e `commands/transferir.md` chama `scripts/transferir.cjs $ARGUMENTS` (não mais o script do Codex direto), conferido no mesmo teste lendo o comando que o `.md` executa.

### 4. README, CHANGELOG e versão [tipo: docs]
atende: D1, D7
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: só texto e número de versão; nenhum comportamento a inverter
pronto quando: com a tabela de comandos do README, a linha do `/transferir` descreve os dois destinos coerentes com D2/D3/D7 (Codex exige `transfer-codex`; `claude` vai para a outra conta sem chave e só nesta máquina, D1), o CHANGELOG ganha a entrada da versão nova citando D10 como conserto, e a versão sobe um MINOR acima da que estiver na `origin/main` no momento do `fechar` nos dois `plugin.json`, no badge do README e no CHANGELOG — provado por `node -e` que lê os dois `plugin.json` e o badge e compara entre si e com `git show origin/main:.claude-plugin/plugin.json` (MINOR +1, PATCH 0), e pela leitura da linha da tabela contra D1/D2/D3/D7 no `revisar`.
