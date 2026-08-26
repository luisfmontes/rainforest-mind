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

### 1. O bloco de commit e push sai, e a falha passa a falar [tipo: implementar]
atende: D1, D2, D3, D5
arquivos: `vigias/run-vigia.ps1`, `scripts/testa-run-vigia-backup.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: a chamada de backup do bloco `sentinela-foco`, que substituiu o `git add`/`commit`/`push`
  para: `git -C $root add FOCO.md ideias.jsonl vigias/ERROS.md 2>$null; git -C $root commit -m "Backup diario do estado (sentinela)"; git -C $root push origin main`
  bateria: `bash scripts/testa-run-vigia-backup.sh`
  fixture: o caso "o sentinela nao commita nem empurra em raiz nenhuma" de `scripts/testa-run-vigia-backup.sh`
pronto quando: num repositório git de caixa montado pela própria bateria, rodar o caminho `sentinela-foco` fora de `-Teste` **com** `RFM_ROOT` e **sem** `RFM_ROOT`, e provar por `git log --oneline` das duas raízes que a contagem de commits é **idêntica** antes e depois — nenhum commit novo, nenhum push tentado (remota da caixa apontando para pasta local, e `git log` dela conferido); e, forçando o backup a falhar (raiz de dados somente-leitura), provar que uma linha nomeando a falha aparece no `ERROS.md` com o mesmo formato `- <data> [<vigia>]: <motivo>` dos outros erros do script — colando o conteúdo do arquivo, não o relato

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

### 3. O sentinela chama o backup, e a bateria prova que ele chama [tipo: implementar]
atende: D4, D6
arquivos: `vigias/run-vigia.ps1`, `scripts/testa-run-vigia-backup.sh`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: a linha que invoca `node scripts/foco.cjs backup` no fim do `sentinela-foco`
  para: um comentário (linha removida do caminho de execução)
  bateria: `bash scripts/testa-run-vigia-backup.sh`
  fixture: o caso "o sentinela chama o backup do FOCO.md" de `scripts/testa-run-vigia-backup.sh`
pronto quando: rodando o caminho `sentinela-foco` fora de `-Teste` contra uma caixa com `FOCO.md`, aparece **um** arquivo novo em `<caixa>/.foco-backups/` — contado por `ls | wc -l` antes e depois —, e rodando com `-Teste` **nenhum** aparece, com a linha "modo teste" no log; o teto de cópias vai na chamada como número explícito, não como padrão implícito (D4 e o `Em aberto` do design sobre as 293 cópias sem poda)

### 4. Trava: `git push` não volta ao run-vigia.ps1 [tipo: implementar]
atende: D1
arquivos: `scripts/testa-run-vigia-backup.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: um comentário qualquer do arquivo
  para: `git -C $root push origin main`
  bateria: `bash scripts/testa-run-vigia-backup.sh`
  fixture: o caso "nenhum git push no run-vigia.ps1" de `scripts/testa-run-vigia-backup.sh`
pronto quando: a bateria varre o `vigias/run-vigia.ps1` procurando `git push` e `git commit` **em linha de execução, não em comentário**, e fica vermelha quando qualquer um dos dois é reintroduzido — provado aplicando a mutação acima e colando a saída vermelha, e provado no sentido contrário deixando a mesma string num comentário e mostrando que continua verde

### 5. Documentar o que mudou no vigia [tipo: documentar]
atende: D1, D2, D3, D4, D5, D6
arquivos: `vigias/_comum.md`
depende de: 3, 4
paralela: nao
mutacao:
  arquivo: `vigias/_comum.md`
  de: a linha que diz que o sentinela não commita nem empurra
  para: uma linha em branco
  bateria: `bash scripts/testa-conferir-encoding.sh`
  fixture: o caso de acentuação de `vigias/_comum.md` em `scripts/testa-conferir-encoding.sh`
pronto quando: `vigias/_comum.md` diz, em texto, que o sentinela **não** commita nem empurra e que o backup do `FOCO.md` é local e rotativo, com o número do teto escrito; e `bash scripts/testa-conferir-encoding.sh` fica verde, provando que os acentos sobreviveram à edição — foi um diff sem acento que criou retrabalho em 2026-08-25
