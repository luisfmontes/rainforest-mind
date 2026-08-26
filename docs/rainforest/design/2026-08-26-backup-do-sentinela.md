# Design — o backup diário do sentinela

Issue #118. Aberta apurando a #112 e separada dela de propósito: a #112 decide em
que raiz o `vigias/ERROS.md` mora; esta decide o que o `sentinela-foco` faz no
fim da ronda, que é outra coisa e mais grave.

Data: 2026-08-26.

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
repositório público. O `git add FOCO.md ideias.jsonl vigias/ERROS.md` falha para
os dois primeiros (não existem lá) e acerta o terceiro (é rastreado lá). O
`2>$null` engole a falha. Sobra `$staged` não-vazio, e o script commita e
empurra.

Estado de backup que **já existe** hoje, medido na pasta de dados:

| arquivo | backup automático | quantos |
|---|---|---|
| `ideias.jsonl` | `.ideias-backups/`, a cada escrita | 293 |
| `divergencias.jsonl` | `.divergencias-backups/` | sim |
| `ferramentas.jsonl` | `.ferramentas-backups/` | sim |
| `rainforest.db` | `.rainforest-backups/` | 2, de 2026-08-20 |
| **`FOCO.md`** | **nenhum** | um `.bak-20260825` feito à mão |

Nada disso sai da máquina.

## Decisões

**D1 — o `git push origin main` sai do script, incondicionalmente.**
Porque: tarefa agendada empurrando para a `main` de um repositório **público**,
sem ninguém olhando e com mensagem enlatada, não é backup — é publicação
automática. Já aconteceu duas vezes. As duas alternativas que a issue levanta
concordam nisto, então não é escolha: é remoção.

**D2 — o `commit` automático sai junto.**
Porque: sem o push ele viraria commit local órfão num repositório de trabalho,
sujando o histórico da `main` do plugin com "Backup diario do estado" que não faz
backup de nada. O par commit+push nasceu junto e sai junto.

**D3 — falha de backup passa a falar.**
O `2>$null` sai. Qualquer caminho de backup que não conseguir gravar escreve uma
linha no `ERROS.md`, no mesmo formato dos outros erros do script.
Porque: este defeito viveu 19 dias invisível **por causa** do `2>$null`. Um
backup que falha calado é pior que backup nenhum — o nenhum pelo menos não
mente.

**D4 — o backup que passa a existir é local e rotativo, do `FOCO.md`, no molde
do `.ideias-backups`.**
Porque: a tabela acima mostra que o único arquivo de estado sem backup é o
`FOCO.md`, e o mecanismo para isso já existe neste repo e já roda 293 vezes sem
incidente. Não precisa de remota, de credencial em tarefa agendada, nem de
transformar `~/.rainforest` em repositório git.
O que esta decisão **não** resolve, e admite: continua sem cópia fora da
máquina. Isso é um problema separado, de outra natureza (destino, credencial,
privacidade), e não se resolve de carona num vigia.

**D5 — o `$root` do backup não se decide aqui.**
Porque: é exatamente a pergunta da #112. Depois da D1 e da D2 não sobra `git -C
$root` nenhum neste bloco, então a #112 fica livre para decidir a raiz do
`ERROS.md` sem este bloco pesando na balança.

## Em aberto

- **Se o Luís quer cópia fora da máquina**, D4 não entrega isso e nenhuma
  decisão aqui entrega. Precisa de issue própria, e a primeira pergunta dela é
  para onde — não com que ferramenta.
- **Os dois commits que já foram empurrados** (`bb77232` e `17ba994`) ficam no
  histórico público. Cada um acrescentou uma linha ao `vigias/ERROS.md`, que é
  arquivo do próprio repo — não há dado pessoal neles. Reescrever histórico de
  repositório público por causa disso custa mais do que vale, então **não** se
  mexe. Registrado para não parecer esquecimento.
- **Se o `sentinela-foco` deve continuar rodando** depois de perder o bloco de
  backup: ele faz outras coisas (triagem, ronda de foco), então sim — mas isso
  não foi medido nesta apuração.
