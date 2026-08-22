# Plano: Statusline versionada no plugin, e os temporarios da bateria de saude

Design: docs/rainforest/design/2026-08-20-statusline-no-plugin-e-temp-da-bateria.md

## Estado inicial (feito pela janela principal antes das tarefas)

`statusline.py`, `statusline-jornada.sh` e `testa-statusline-prazo.py` foram
copiados de `~/.claude/` para `statusline/` no repositorio, byte a byte, sem
alteracao. A copia sai da janela principal de proposito: a origem esta **fora**
do worktree de qualquer subagente (regra 15). Os arquivos originais em
`~/.claude/` continuam no lugar e continuam sendo os que rodam ate a tarefa 7 —
a barra do Luis nao pode ficar quebrada no meio da esteira.

## O que nao pode quebrar

- A barra continua renderizando nos **dois** perfis **sem** editar o
  `settings.json` de nenhum dos dois: os dois apontam para
  `~/.claude/statusline-command.sh`, e esse caminho nao muda.
- Os **8** casos que a bateria de prazo ja cobre continuam passando. Caso que
  quebrar e achado para reportar, nunca teste para afrouxar.
- `bash scripts/testa-saude.sh` continua saindo 0 com 28 ok.
- O CI continua achando **pelo menos 15** baterias no glob
  `scripts/testa-*.sh hooks/testa-*.sh` — a guarda contra glob quebrado fica
  como esta.
- A jornada continua **nao** sendo inferida dentro da statusline (regra 8): o
  numero segue vindo do `scripts/jornada.cjs`, por cache, em segundo plano.
- Nenhum segmento pode travar a barra: todo subprocesso com timeout, todo
  segmento que falhar simplesmente nao aparece.

## Tarefas

### 1. statusline.py acha os vizinhos por caminho relativo a si mesmo [tipo: implementar]
atende: D1, D2
arquivos: `statusline/statusline.py`, `statusline/statusline-jornada.sh`
depende de: nenhuma
paralela: sim
pronto quando: com o JSON que o harness manda no stdin da statusline
(`{"cwd":"<raiz do repo>","model":{"display_name":"Opus 5"},"context_window":{"used_percentage":12},"transcript_path":"C:/Users/Luis/.claude-personal/projects/x/y.jsonl"}`),
`python statusline/statusline.py` imprime uma linha contendo `rainforest-mind`,
`pessoal` e `Opus 5` — provado por
`printf '%s' '<json>' | python statusline/statusline.py` devolvendo essa linha
com exit 0, e por `grep -n '^REFRESHER' statusline/statusline.py` mostrando a
constante derivada de `__file__` e **sem** a string `.claude`.

> **Redacao corrigida em 2026-08-21**, apontada pela segunda revisao
> independente. A versao anterior mandava `grep -c 'os.path.expanduser'
> statusline/statusline.py` devolver `0` — mas esse comando roda no arquivo
> inteiro e devolve `1`, por causa do `HOME = os.path.expanduser("~")` da linha
> 27, que e legitimo e continua sendo usado pelo `FOCO`. O criterio media o
> arquivo quando queria medir **a constante**, e ao pe da letra reprovaria o
> `verificar` por defeito de redacao minha, nao do codigo.

### 2. Shim resolvedor versionado, que acha a versao mais nova do plugin [tipo: implementar]
atende: D1
arquivos: `statusline/statusline-command.sh`
depende de: nenhuma
paralela: sim
pronto quando: (a) com uma arvore sintetica em `$T/0.99.0/statusline/statusline.py`
que so imprime `SINTETICA`, `RAINFOREST_STATUSLINE_CACHE="$T" bash statusline/statusline-command.sh </dev/null`
imprime `SINTETICA`; (b) com **duas** versoes na arvore sintetica, imprime a de
mtime mais novo; (c) sem nenhum casamento
(`RAINFOREST_STATUSLINE_CACHE=/naoexiste`), sai **0** e nao imprime nada —
barra vazia e ruim, barra que trava o harness e pior. O default da variavel e o
mesmo glob que o `statusline-jornada.sh` ja usa:
`/c/Users/Luis/.claude*/plugins/cache/rainforest-mind/rainforest-mind/*`.
Provado pelos tres comandos acima com as saidas nomeadas.

### 3. Caso do falso positivo residual entra na bateria, e ela fica VERMELHA [tipo: teste]
atende: D4, D1
arquivos: `statusline/testa-statusline-prazo.py`
depende de: nenhuma
paralela: sim
pronto quando: com o corpo de FOCO `"## Ativo\nEntrega ate <hoje+10>, conforme
combinado na reuniao de <hoje+2>."`, a bateria acusa esse caso como FALHA
(esperado `prazo 10d`, obtido `prazo 2d`) — provado por
`python statusline/testa-statusline-prazo.py` saindo **1** e imprimindo
`8/9 casos passaram`. Vermelho aqui e o resultado correto: e a tarefa 4 que
conserta. Nao mexer no `statusline.py` nesta tarefa.

### 4. A data se ancora ao marcador por proximidade [tipo: implementar]
atende: D4
arquivos: `statusline/statusline.py`
depende de: 3
paralela: nao
pronto quando: com o mesmo corpo de FOCO da tarefa 3, `segmento_prazo()` devolve
`prazo 10d` (e nao `prazo 2d`), e os 8 casos que ja existiam continuam passando —
provado por `python statusline/testa-statusline-prazo.py` saindo **0** e
imprimindo `10/10 casos passaram`. Se a ancora quebrar qualquer um dos 8, **pare
e reporte**: afrouxar caso existente reprova a tarefa.

> **Criterio endurecido em 2026-08-21, depois do plano fechado** (de 9/9 para
> 10/10). A integracao das tarefas 1 a 3 mostrou que a solucao obvia — "so conta
> data que venha DEPOIS de um marcador" — **regride uma linha real** do FOCO.md
> do Luis: `- **Projetos 1 — reuniao 17/08, entregar ate 14/08 (sex)**` tem
> marcador antes das duas datas, e o compromisso que vale e o **14/08**, o
> menor. A tarefa 4 passa a exigir um decimo caso, que blinda essa linha, e ele
> ja tem de passar ANTES da mudanca. Endurecer criterio depois do plano fechado
> e legitimo; afrouxar nao seria.

### 5. A bateria de prazo entra no CI por um invocador em scripts/ [tipo: implementar]
atende: D3
arquivos: `scripts/testa-statusline.sh`
depende de: 1, 4
paralela: nao
pronto quando: o glob que o CI usa passa a incluir o arquivo novo —
`ls scripts/testa-*.sh hooks/testa-*.sh | grep -c .` devolve **37** (eram 36,
medido em 2026-08-21; o comentario do workflow ainda fala em 20, que era o numero
de 17/08) — e
`bash scripts/testa-statusline.sh` sai **0** imprimindo `10/10 casos passaram`;
com o `statusline.py` mutado (apagar o `if not RE_MARCADOR.search(linha)`),
`bash scripts/testa-statusline.sh` sai **diferente de 0**. Provado pelos tres
comandos.

### 6. Os tres mktemp da bateria de saude entram no trap global [tipo: implementar]
atende: D5
arquivos: `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
pronto quando: interrompendo a bateria com SIGINT dentro de cada uma das tres
secoes de mutacao (`MUTR` l.269, `MUT` l.351, `MUTCD` l.430), **nenhuma** pasta
temporaria sobra — provado por, para cada uma das tres, contar
`ls -1d "$TMPDIR"/tmp.* | wc -l` antes e depois de
`timeout -s INT <n> bash scripts/testa-saude.sh` e os dois numeros baterem; e
`bash scripts/testa-saude.sh` seguir saindo **0** com `28 ok`.

### 7. A instalacao vira script versionado, com conferencia e sem destruir as chances de voltar [tipo: implementar]
atende: D1, D7
arquivos: `scripts/instalar-statusline.sh`
depende de: 1, 2, 4, 5
paralela: nao
pronto quando: com um HOME sintetico que imita `~/.claude` (shim antigo,
`statusline.py`, `statusline-jornada.sh`, `testa-statusline-prazo.py` e um
`.bak`), `bash scripts/instalar-statusline.sh --conferir` **nao muda nada** e
lista os cinco caminhos com o que faria; e `bash scripts/instalar-statusline.sh`
deixa o HOME sintetico com **exatamente um** arquivo de statusline
(`statusline-command.sh`, byte a byte igual ao `statusline/statusline-command.sh`
do repo) e **zero** dos outros quatro. Provado por `ls` e `diff` nos dois modos.
Recusa-se a rodar (exit != 0, sem apagar nada) quando o alvo do shim ainda nao
existe no cache do plugin — apagar a copia velha antes de a nova estar
publicada deixa a barra vazia.

> **Tarefa reescrita em 2026-08-21, depois do plano fechado.** A versao original
> mandava a janela principal instalar o shim e apagar os arquivos **na mao**, e
> declarava a dependencia errada: dizia "so roda depois de a versao nova estar
> publicada no cache", mas publicar, aqui, e **merge** — o marketplace
> `rainforest-mind` tem `source: "./"` e o `plugin update` puxa do repositorio
> no GitHub. Ou seja, a tarefa 7 original so podia rodar **depois** do `fechar`,
> o que a deixava fora do alcance do `executar` e travava `revisar` e
> `verificar` atras dela. Com o entregavel virando script versionado, o
> `executar` fecha o que e dele (o script, testado contra um HOME sintetico) e o
> ato no ambiente do Luis vira uma linha do `fechar`, depois do merge — que e
> onde ele sempre pertenceu. Regra 17 ja dizia o principio para outro caso:
> estado compartilhado se escreve por script, nunca a mao.

### 9. Reverter a ancora por posicao, e a bateria dizer o que a barra promete [tipo: implementar]
atende: D8
arquivos: `statusline/statusline.py`, `statusline/testa-statusline-prazo.py`
depende de: 4
paralela: nao
pronto quando: com o corpo de FOCO `"## Ativo\n- <hoje+10> e o prazo final de
entrega do modulo.\n"` — data **antes** do marcador, ordem inversa —
`segmento_prazo()` devolve `prazo 10d` e nao vazio; e os casos de clausula de
contexto continuam passando (`conforme reuniao`, `de acordo com`, `definido na`,
intercalada, e a linha real `reuniao X, entregar ate Y` devolvendo o menor).
Provado por `python statusline/testa-statusline-prazo.py` saindo **0**. O caso
`data de contexto antes do marcador nao conta`, escrito na rodada 3, **sai da
bateria** — ele codificava o comportamento que a D8 descarta, e teste que
descreve comportamento abandonado mente sobre o que a barra promete. No lugar
dele entra o caso da ordem inversa.

### 8. Os dois trabalhos numa branch so, um PR so [tipo: docs]
atende: D6
arquivos: `docs/rainforest/estado/2026-08-20-statusline-no-plugin-e-temp-da-bateria.json`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
pronto quando: existe **uma** branch de trabalho contendo os dois trabalhos —
`git diff --name-only main...statusline-no-plugin-e-temp-da-bateria` lista
`scripts/testa-saude.sh` **e** arquivos sob `statusline/`, e
`git branch --list 'statusline-no-plugin*'` devolve exatamente uma linha. A
abertura do PR em si e ato do estagio `fechar`, e o `fechar` confere
`gh pr list --head statusline-no-plugin-e-temp-da-bateria` devolvendo um unico
numero — uma rodada de CI para os dois trabalhos.
