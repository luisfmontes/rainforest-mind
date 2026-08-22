# Plano: Atualizar a CLI por script, e a barra avisar quando a sessao esta atrasada

Design: docs/rainforest/design/2026-08-22-atualizar-cli-e-aviso-de-versao.md

## Estado inicial

A maquina ja esta na 2.1.231 — a atualizacao de hoje foi feita a mao pela janela
principal, e e dela que sai a receita da tarefa 1. O backup
`claude-2.1.220.exe.bak` (265 MB) esta na pasta do pacote e **fica**: as 4 sessoes
abertas ainda rodam a partir dele. Nenhuma tarefa deste plano toca a instalacao
real (D8).

## O que nao pode quebrar

- A barra continua renderizando nos **dois** perfis, e nenhum segmento novo pode
  travar: rede so no refresher destacado, e todo caminho de falha e segmento
  ausente, nunca excecao (D6).
- Os **16** casos de `statusline/testa-statusline-prazo.py` continuam passando.
  Caso que quebrar e achado para reportar, nunca teste para afrouxar.
- `bash scripts/testa-saude.sh` continua saindo 0 com 28 ok.
- O CI continua achando pelo menos 15 baterias no glob
  `scripts/testa-*.sh hooks/testa-*.sh`.
- Nenhuma bateria pode chamar `winget` de verdade, nem renomear o `claude.exe`
  real (D8). Bateria que mexe na instalacao reprova a tarefa.
- A jornada continua **nao** sendo inferida dentro da statusline (regra 8).

## Tarefas

### 1. O script de atualizacao, com rollback e um backup so [tipo: implementar]
atende: D1, D2, D3
arquivos: `scripts/atualizar-cli.sh`
depende de: nenhuma
paralela: sim
pronto quando: contra uma arvore sintetica apontada por `ATUALIZAR_CLI_PACOTE`
(pasta com um `claude.exe` falso) e um `winget` falso no PATH:
(a) execucao feliz — o falso `winget` grava um `claude.exe` novo cuja
`--version` imprime `9.9.9`: o script sai **0**, a pasta fica com `claude.exe`
(o novo) e **exatamente um** `.bak`, e a saida cita a versao velha e a nova;
(b) rollback — o falso `winget` sai 1 sem gravar nada: o script sai **diferente
de 0**, e a pasta volta a ter `claude.exe` com o conteudo original e **zero**
`.bak` sobrando (nome e conteudo conferidos por `diff`);
(c) rollback por versao que nao subiu — o falso `winget` grava um exe cuja
`--version` imprime a **mesma** versao de antes: sai diferente de 0 e restaura
igual ao caso (b);
(d) poda — com dois `.bak` antigos ja na pasta antes da execucao feliz, sobra
**um** ao final. Provado pelos quatro cenarios com `ls` e `diff` colados.
O script **nao** roda `winget upgrade` quando `ATUALIZAR_CLI_PACOTE` aponta para
pasta inexistente: sai diferente de 0 sem tocar em nada.

### 2. A bateria do script de atualizacao [tipo: teste]
atende: D8
arquivos: `scripts/testa-atualizar-cli.sh`
depende de: 1
paralela: nao
pronto quando: `bash scripts/testa-atualizar-cli.sh` sai **0** e imprime a
contagem dos cinco cenarios da tarefa 1 no formato `N/N casos passaram`; e,
mutando o `atualizar-cli.sh` (apagar a linha do rename de volta no rollback),
sai **diferente de 0**. A bateria monta tudo em `mktemp -d` limpo por um unico
`trap ... EXIT`, e **nao** existe no seu texto nenhuma chamada a `winget` real
nem ao caminho `.../WinGet/Packages/Anthropic.ClaudeCode...` — provado por
`grep -c` devolvendo 0 para os dois padroes fora das variaveis de ambiente.

### 3. Refresher que busca o estavel do CDN em segundo plano [tipo: implementar]
atende: D5
arquivos: `statusline/statusline-versao.sh`
depende de: nenhuma
paralela: sim
pronto quando: `bash statusline/statusline-versao.sh` sai **0** e deixa em
`$TEMP/claude-statusline-versao.txt` uma linha casando `^[0-9]+\.[0-9]+\.[0-9]+$`
igual ao que `curl -s https://downloads.claude.ai/claude-code-releases/stable`
devolve; com a rede indisponivel (`RAINFOREST_VERSAO_URL=http://127.0.0.1:1/x`)
sai **0** e **nao** cria nem trunca o cache existente; e duas execucoes
simultaneas nao se atropelam — o lock por `mkdir` e o mesmo do
`statusline-jornada.sh`, incluindo a limpeza de lock orfao acima de 5 min.

### 4. O segmento de versao na barra [tipo: implementar]
atende: D4, D6
arquivos: `statusline/statusline.py`
depende de: 3
paralela: nao
pronto quando: com `$TEMP/claude-statusline-versao.txt` contendo `2.1.231` e um
transcript sintetico cuja ultima linha tem `"version":"2.1.220"`, a barra imprime
um segmento contendo `2.1.220` e o simbolo de atraso; com o transcript em
`"version":"2.1.231"`, o segmento **nao aparece**; sem o arquivo de cache, sem o
transcript, com transcript vazio e com JSON invalido na ultima linha, a barra
imprime as demais secoes e sai **0** nos quatro casos. A comparacao e
**numerica por componente**: `2.1.9` e mais velho que `2.1.10` (comparacao de
string diria o contrario). A leitura do transcript e **so da cauda** — no maximo
os ultimos 8 KB, por `seek`, porque transcript passa de 100 MB. Provado pelos
casos acima rodando `printf '%s' '<json>' | python statusline/statusline.py`.

### 5. A bateria do segmento de versao [tipo: teste]
atende: D7
arquivos: `statusline/testa-statusline-versao.py`
depende de: 4
paralela: nao
pronto quando: `python statusline/testa-statusline-versao.py statusline/statusline.py`
sai **0** e imprime `N/N casos passaram`, cobrindo os oito casos da tarefa 4
(atrasado, em dia, sem cache, sem transcript, transcript vazio, JSON invalido,
`2.1.9` vs `2.1.10`, e cache com lixo em vez de versao); e, mutando o
`statusline.py` (trocar a comparacao numerica por comparacao de string), sai
**diferente de 0** — a mutacao tem de morrer no caso `2.1.9` vs `2.1.10`.
Carrega o modulo por `exec` num namespace com `__name__` e `__file__`, como a
bateria de prazo ja faz.

### 6. O invocador do CI passa a rodar as duas baterias [tipo: implementar]
atende: D7
arquivos: `scripts/testa-statusline.sh`
depende de: 2, 5
paralela: nao
pronto quando: `bash scripts/testa-statusline.sh` roda **as duas** baterias
python, sai **0** e imprime as duas contagens; com **qualquer** uma das duas
mutada, sai **diferente de 0** (provado nas duas direcoes, uma mutacao de cada
vez — invocador que so propaga o codigo da primeira e o defeito que esta tarefa
existe para nao ter); e `ls scripts/testa-*.sh hooks/testa-*.sh | grep -c .`
devolve **38** (eram 37 depois da esteira de ontem).
