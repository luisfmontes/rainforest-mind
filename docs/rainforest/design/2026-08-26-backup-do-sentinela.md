# Design — o backup diário do sentinela

Issue #118. Aberta apurando a #112 e separada dela de propósito: a #112 decide em
que raiz o `vigias/ERROS.md` mora; esta decide o que o `sentinela-foco` faz no
fim da ronda, que é outra coisa e mais grave.

Data: 2026-08-26.

## Objetivo

Parar a publicação automática para um repositório público, e dar backup de
verdade ao único arquivo de estado que não tem nenhum.

Hoje o `sentinela-foco` termina a ronda executando `git add FOCO.md
ideias.jsonl vigias/ERROS.md`, seguido de `commit` e `push origin main`. Esse
`add` não pode funcionar em nenhuma das duas raízes possíveis, o erro é engolido
por `2>$null`, e o que sobra — `vigias/ERROS.md`, que é rastreado no plugin — é
commitado e empurrado sozinho, por tarefa agendada, para a `main` de um repo
público. Duas vezes até hoje. O backup que dá nome ao commit nunca aconteceu.

Pronto quando: nenhum commit automático nasce em nenhuma das duas raízes, falha
de backup aparece no `ERROS.md` em vez de sumir, e o `FOCO.md` passa a ter cópia
rotativa como os outros arquivos de estado já têm.

## O que foi medido antes de decidir

Tudo abaixo é saída de comando, não leitura de código:

```
$ powershell (Get-ScheduledTask -TaskName 'sentinela-foco').Actions
Execute   : powershell.exe
Arguments : -NoProfile -ExecutionPolicy Bypass -File <plugin>\vigias\run-vigia.ps1
            -Vigia sentinela-foco -Cwd "<pasta de comms>"

$ printenv RFM_ROOT
RFM_ROOT nao definido nesta sessao        # nem em User, nem em Machine

$ ls -d "$USERPROFILE/.rainforest/.git"
dados NAO e repo git

$ git ls-files | grep -E '^(FOCO\.md|ideias\.jsonl)$'
FOCO.md e ideias.jsonl NAO sao versionados no repo do plugin

$ git log --oneline --all --grep='Backup diario do estado'
bb77232 Backup diario do estado (sentinela)     2026-08-10   vigias/ERROS.md | 1 +
17ba994 Backup diario do estado (sentinela)     2026-08-07   vigias/ERROS.md | 1 +
```

A tarefa agendada não define `RFM_ROOT`, então `$root` é o **plugin** — um
repositório público.

Estado de backup que **já existe** hoje, medido na pasta de dados:

| arquivo | backup automático | quantos |
|---|---|---|
| `ideias.jsonl` | `.ideias-backups/`, a cada escrita | 293 |
| `divergencias.jsonl` | `.divergencias-backups/` | sim |
| `ferramentas.jsonl` | `.ferramentas-backups/` | sim |
| `rainforest.db` | `.rainforest-backups/` | 2, de 2026-08-20 |
| **`FOCO.md`** | **nenhum** | um `.bak-20260825` feito à mão |

Nada disso sai da máquina.

## Decisões fechadas

- **D1 — o `git push origin main` sai do script, incondicionalmente.**
  Porque: tarefa agendada empurrando para a `main` de um repositório **público**,
  sem ninguém olhando e com mensagem enlatada, não é backup — é publicação
  automática. Já aconteceu duas vezes. As duas alternativas que a issue levanta
  concordam nisto, então não é escolha: é remoção.

- **D2 — o `commit` automático sai junto.**
  Porque: sem o push ele viraria commit local órfão num repositório de trabalho,
  sujando o histórico da `main` do plugin com "Backup diario do estado" que não
  faz backup de nada. O par commit+push nasceu junto e sai junto.

- **D3 — falha de backup passa a falar.**
  O `2>$null` sai. Qualquer caminho de backup que não conseguir gravar escreve
  uma linha no `ERROS.md`, no mesmo formato dos outros erros do script.
  Porque: este defeito viveu 19 dias invisível **por causa** do `2>$null`. Um
  backup que falha calado é pior que backup nenhum — o nenhum pelo menos não
  mente.

- **D4 — o backup que passa a existir é local e rotativo, do `FOCO.md`, no molde do `.ideias-backups`.**
  Porque: a tabela acima mostra que o único arquivo de estado sem backup é o
  `FOCO.md`, e o mecanismo para isso já existe neste repo e já roda 293 vezes sem
  incidente. Não precisa de remota, de credencial em tarefa agendada, nem de
  transformar `~/.rainforest` em repositório git.

- **D5 — a raiz do backup não se decide aqui.**
  Porque: é exatamente a pergunta da #112. Depois da D1 e da D2 não sobra `git -C
  $root` nenhum neste bloco, então a #112 fica livre para decidir a raiz do
  `ERROS.md` sem este bloco pesando na balança.

- **D6 — o backup do `FOCO.md` roda pelo Node, não pelo PowerShell.**
  Porque: o `.ideias-backups` é escrito por `scripts/ideias.cjs`, o
  `.rainforest-backups` por `scripts/memoria.cjs`. Reimplementar rotação em
  PowerShell seria a segunda cópia da mesma regra, e cópia mantida à mão diverge
  calada — é o argumento que o próprio `run-vigia.ps1` já usa, no comentário do
  toggle, para chamar o Node em vez de reimplementar a cadeia de três níveis.

- **D7 — a cauda de backup sai do `run-vigia.ps1` e vira `vigias/backup-estado.ps1`.**
  Porque: enquanto o bloco morava no fim do `run-vigia.ps1`, chegar nele exigia
  node no PATH, o toggle `vigias` ligado, destino de WhatsApp configurado, a
  bridge de pé na porta 3005 e o `claude.exe` respondendo — ou seja, uma bateria
  que provasse o bloco **por execução enviaria uma mensagem de WhatsApp de
  verdade**. A primeira tentativa desta tarefa contornou isso fabricando uma
  cópia do bloco e rodando a cópia; com `git push origin main` reintroduzido no
  arquivo real, essa bateria saía `9 ok, 0 falha(s)`. Separado, o pedaço roda
  numa caixa sem bridge, sem claude e sem toggle, e passa a ser provável por
  execução. Esta decisão nasceu **durante** a execução, em 2026-08-26, porque o
  critério que o plano tinha escrito não era alcançável com segurança.

- **D8 — o `vigias/backup-estado.ps1` é ASCII puro.**
  Porque: o PowerShell 5.1 lê `.ps1` sem BOM como CP-1252. Um travessão em UTF-8
  (`E2 80 94`) chega como três caracteres, e o último deles é uma aspa curva que
  **abre uma string**. Três travessões nos comentários deixaram o parser com
  string não terminada, reportando erro a 60 linhas da causa. É a mesma família
  do `` que quebrou um fallback em 2026-08-25 e do `` que comeu um pedaço
  de caminho hoje: caractere que parece decoração e é sintaxe.

## Avaliado e descartado

- **Transformar `~/.rainforest` em repositório git com remota privada.** Dá
  versionamento e cópia fora da máquina de uma vez. Descartado: devolve o
  problema que a D1 acabou de tirar — tarefa agendada empurrando sozinha, agora
  com credencial de repo privado dentro do Agendador. E o custo de montar não é
  do tamanho do buraco, que é um arquivo sem backup.

- **Consertar o `git add` para apontar na raiz certa.** É a leitura óbvia da
  issue: o `add` está quebrado, então conserta o `add`. Descartado porque
  conserta o sintoma na direção errada — um `add` que funciona é um `push`
  automático que funciona, e é o `push` que não deveria existir. A #112 mostra
  que nem a raiz está decidida; consertar o alvo antes de decidir o destino é
  ordem invertida.

- **Copiar o `FOCO.md` para dentro do plugin para o `add` achar.** Fecharia o
  erro com uma linha. Descartado: o repo é público e o `FOCO.md` tem 9 KB de
  foco, prazos e nomes de pessoas. Seria trocar um defeito silencioso por um
  vazamento.

## Fora de escopo

- **Cópia fora da máquina.** Nenhuma decisão aqui entrega isso, e a D4 não finge
  entregar. É issue própria, e a primeira pergunta dela é *para onde*, não *com
  qual ferramenta*.

- **A raiz do `vigias/ERROS.md`.** É a #112, e continua aberta.

- **O resto do `sentinela-foco`.** Ele faz triagem e ronda de foco; nada disso é
  tocado aqui.

- **Reescrever o histórico público** por causa de `bb77232` e `17ba994`.

## Em aberto

- **Os dois commits que já foram empurrados** ficam no histórico público. Cada um
  acrescentou uma linha ao `vigias/ERROS.md`, que é arquivo do próprio repo — não
  há dado pessoal neles. Reescrever histórico de repositório público por isso
  custa mais do que vale. Registrado para não parecer esquecimento.

- **Quantas cópias o rodízio do `FOCO.md` guarda** não foi decidido: o
  `.ideias-backups` está em 293 sem poda nenhuma, o que é um rodízio que não
  roda. Herdar esse comportamento é herdar o mesmo problema, mas resolver poda
  aqui é escopo de outra coisa. Fica no plano como número explícito, não como
  omissão.

- **Se a tarefa agendada precisa ser reregistrada** depois da mudança não foi
  medido — o script muda, a linha de comando não, então em princípio não. Mas
  ninguém rodou para confirmar.
