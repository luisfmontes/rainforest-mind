# Plano: o backup diário do sentinela (#118)

Design: docs/rainforest/design/2026-08-26-backup-do-sentinela.md

## O que não pode quebrar

- **Nenhum commit ou push automático nasce, em raiz nenhuma.** É o motivo desta
  entrega existir (D1, D2). Trava que fica vermelha se `git push` voltar ao
  script.
- **O `sentinela-foco` continua rodando o resto da ronda.** Triagem e ronda de
  foco não são tocadas — só o bloco de backup no fim.
- **Nada é escrito fora de `~/.rainforest`** — nem PATH, nem env, nem config, nem
  a tarefa agendada (regra 15). A tarefa agendada é lida, nunca reescrita.
- **O `FOCO.md` real nunca é usado como caixa de teste.** Toda bateria roda com
  `RFM_ROOT` apontando para sandbox — este arquivo tem 9 KB de prazos e nomes de
  pessoas.
- **O repo é público:** nenhum caminho desta máquina, usuário ou credencial entra
  em arquivo versionado. As cópias de backup vão para a raiz de dados e ficam
  ignoradas pelo git.
- **Falha de backup aparece.** Nenhum caminho novo pode terminar em `2>$null`,
  `catch {}` vazio ou equivalente (D3) — foi exatamente isso que escondeu o
  defeito por 19 dias.

## Tarefas

### 1. A cauda de backup sai do run-vigia.ps1 e vira vigias/backup-estado.ps1 [tipo: implementar]
atende: D1, D2, D3, D5, D7, D8
arquivos: `vigias/run-vigia.ps1`, `vigias/backup-estado.ps1`, `scripts/testa-backup-estado.sh`

> Reescrita em 2026-08-26, durante a execução. A redação anterior mandava provar
> rodando o caminho `sentinela-foco` inteiro numa caixa — e isso **não é
> alcançável com segurança**: para chegar no bloco é preciso a bridge do WhatsApp
> de pé e o `claude.exe` respondendo, então a bateria enviaria uma mensagem de
> verdade. O agente que recebeu o critério original contornou fabricando uma
> cópia do bloco e rodando a cópia; a bateria dele saía `9 ok, 0 falha(s)` com
> `git push origin main` de volta no arquivo real. O critério errado era meu, e a
> saída é a D7: extrair o pedaço para que ele seja executável de verdade.

depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `vigias/backup-estado.ps1`
  de: `if ($codigo -ne 0) {`
  para: `if ($false) {`
  bateria: `bash scripts/testa-backup-estado.sh`
  fixture: o caso "falha de backup FALA no ERROS.md" de `scripts/testa-backup-estado.sh`
pronto quando: a bateria **executa** o `vigias/backup-estado.ps1` real numa caixa de `mktemp -d` com dois repositórios git que **têm commit** (senão `git log` falha nas duas pontas e a comparação passa por vazio — foi assim que a primeira versão ficou verde) e remota apontando para pasta local; e prova que a contagem de commits é idêntica antes e depois nos quatro repositórios, que `-Teste` não escreve backup nenhum, e que forçar a falha põe uma linha no `ERROS.md` no formato `- <data> [<vigia>]: <motivo>` — com o conteúdo do arquivo colado, não o relato

### 2. Backup rotativo do FOCO.md: `node scripts/foco.cjs backup` [tipo: implementar]
atende: D4, D6
arquivos: `scripts/foco.cjs`, `scripts/testa-foco.sh`, `.gitignore`

> O `.gitignore` entra aqui, e não fica implícito: o destino é
> `<raiz>/.foco-backups/`, e a raiz de dados pode ser um diretório de projeto
> versionado quando alguém usa `<projeto>/.rainforest`. Foi um `ferramentas.jsonl`
> commitado com dois caminhos desta máquina dentro, em 2026-08-25, que ensinou
> que a trava pertence à tarefa que decide onde o arquivo mora.

depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/foco.cjs`
  de: o corte do rodízio no subcomando `backup` — a comparação que apaga a cópia mais antiga quando o teto é ultrapassado
  para: um `return` antes dela, que nunca poda
  bateria: `bash scripts/testa-foco.sh`
  fixture: o caso "o rodizio do backup guarda no maximo o teto de copias" de `scripts/testa-foco.sh`
pronto quando: com `RFM_ROOT` numa caixa contendo um `FOCO.md` de conteúdo conhecido, `node scripts/foco.cjs backup` cria `<caixa>/.foco-backups/foco-<timestamp>.md` **byte a byte igual** ao original (provado por `cmp`), rodar N+1 vezes deixa exatamente N arquivos com as **mais novas** preservadas (provado por `ls` e pela data no nome), rodar com o `FOCO.md` ausente sai diferente de zero dizendo qual arquivo não achou — e não cria diretório nenhum —, e `git check-ignore .foco-backups/qualquer.md` confirma que o destino está
ignorado — o caminho tem de ser **de dentro** do diretório, porque padrão
terminado em barra só casa diretório e o diretório pode não existir na hora da
pergunta; a primeira redação deste critério dizia `.foco-backups` e fez a bateria
da tarefa 2 acusar falha onde o `.gitignore` estava correto

### 3. O run-vigia.ps1 chama o backup extraído [tipo: implementar]
atende: D4, D6, D7
arquivos: `vigias/run-vigia.ps1`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: `$argsBackup = @(`
  para: `git -C $root push origin main` seguido da linha original
  bateria: `bash scripts/testa-backup-estado.sh`
  fixture: o caso "o run-vigia.ps1 nao volta a commitar nem empurrar" de `scripts/testa-backup-estado.sh`
pronto quando: o `run-vigia.ps1` invoca o `backup-estado.ps1` passando `-Vigia`, `-Root`, `-Plugin`, `-Log` e repassando o `-Teste`, por vetor de argumentos e não por interpolação; o teto de cópias vai como número explícito dentro do `backup-estado.ps1`, com o porquê escrito; e a chamada é ASCII puro, sem travessão e sem escape que o PowerShell 5.1 leia como aspa

### 4. Trava: git add, commit e push não voltam ao run-vigia.ps1 [tipo: implementar]
atende: D1, D7
arquivos: `scripts/testa-backup-estado.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `vigias/backup-estado.ps1`
  de: `$foco = Join-Path $Plugin "scriptsoco.cjs"`
  para: `git push origin main` seguido da linha original
  bateria: `bash scripts/testa-backup-estado.sh`
  fixture: o caso "nenhum git no backup-estado.ps1, fora de comentario" de `scripts/testa-backup-estado.sh`
pronto quando: a trava varre **linha de execução**, não o arquivo inteiro, nos dois `.ps1`; fica vermelha quando `git add`, `git commit` ou `git push` voltam ao caminho executado; e fica **verde** com as mesmas strings no comentário que explica por que elas saíram — provado nos dois sentidos, porque uma trava que obriga a apagar a explicação é uma trava que apaga a razão

### 5. Documentar o que mudou no vigia, e amarrar a doc ao código [tipo: documentar]
atende: D1, D2, D3, D4, D5, D6, D7, D8
arquivos: `vigias/_comum.md`, `scripts/testa-backup-estado.sh`

> Reescrita em 2026-08-26. A redação anterior mandava provar esta tarefa com
> `scripts/testa-conferir-encoding.sh`, e o `conferir-mutacao.cjs` recusou: essa
> bateria mede acento, não conteúdo — apagando a linha inteira ela continuava
> verde. Teste de prosa também não serve. O que serve é o único número que vive
> em **dois** lugares: o teto de cópias, declarado no `backup-estado.ps1` e
> prometido no `_comum.md`. Se um mudar e o outro não, o vigia lê uma promessa
> que o código não cumpre.

depende de: 3, 4
paralela: nao
mutacao:
  arquivo: `vigias/backup-estado.ps1`
  de: `$TETO_COPIAS = 30`
  para: `$TETO_COPIAS = 7`
  bateria: `bash scripts/testa-backup-estado.sh`
  fixture: o caso "o _comum.md nao pode divergir do codigo" de `scripts/testa-backup-estado.sh`
pronto quando: o `vigias/_comum.md` diz, em texto, que o sentinela **não** commita nem empurra, que o backup é local e rotativo do `FOCO.md`, e o teto em número; a bateria extrai o teto do `.ps1` e exige o mesmo número no `.md`, ficando vermelha quando os dois divergem; e `bash scripts/testa-conferir-encoding.sh` fica verde, provando que os acentos sobreviveram à edição
