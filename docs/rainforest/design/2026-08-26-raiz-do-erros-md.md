# Design — a raiz do vigias/ERROS.md

Issue #112. Achada fechando a #110 (PR #111) e deixada de propósito para não
misturar produtor com consumidor.

Data: 2026-08-26.

## Objetivo

Fazer o `vigias/ERROS.md` ter **uma** raiz, e que ela seja a mesma que o leitor
já usa.

Hoje o `vigias/run-vigia.ps1` escreve o mesmo arquivo em duas raízes diferentes:

```
$ git show origin/main:vigias/run-vigia.ps1 | grep -nE 'ERROS\.md'
 31:      Out-File -Append ... (Join-Path $plugin "vigias\ERROS.md")
 46:      Out-File -Append ... (Join-Path $root   "vigias\ERROS.md")
 65:      Out-File -Append ... (Join-Path $root   "vigias\ERROS.md")
131:      Out-File -Append ... (Join-Path $root   "vigias\ERROS.md")
```

E `$root` não é fixo:

```powershell
$root = if ($env:RFM_ROOT) { $env:RFM_ROOT } else { Split-Path -Parent $PSScriptRoot }
```

Sem `RFM_ROOT` — que é como a tarefa agendada roda hoje — `$root` cai no próprio
plugin e as quatro linhas acertam o mesmo arquivo **por coincidência**. Com
`RFM_ROOT` definido elas se partem: a 31 continua no plugin, as outras três
passam para a pasta de dados. Duas listas de erro, nenhuma completa, e ninguém
avisado.

Pronto quando: com `RFM_ROOT` apontando para uma pasta de dados de teste, os
quatro caminhos de escrita gravam **no mesmo arquivo**, e o
`vigias/dados-batedor-repos.js` conta os quatro.

## O que mudou desde que a issue foi aberta

A issue dizia que não dava para consertar o `.ps1` sem antes decidir se o
`ERROS.md` é log de operação (raiz de dados) ou conteúdo versionado (plugin), e
apontava a linha 184 — `git -C $root add FOCO.md ideias.jsonl vigias/ERROS.md` —
como indício de que a intenção era a raiz de dados.

Esse indício **caiu**. A #118 mediu e provou que aquele `git add` não podia
funcionar em raiz nenhuma: a pasta de dados não é repositório git, e
`FOCO.md`/`ideias.jsonl` não são versionados no plugin. A linha inteira saiu no
PR #122. Ela não era evidência de intenção — era um defeito.

O que sobra é evidência limpa nos dois sentidos, e ela aponta para o plugin:

- `vigias/ERROS.md` **é rastreado** no repositório do plugin (`git ls-files`).
- `vigias/dados-batedor-repos.js:123` lê pelo `lerLinhasDoPlugin`, e o
  comentário da linha 25 declara: *"os relatorios e o `vigias/ERROS.md` sao
  CONTEUDO DO REPOSITORIO e moram ao lado"*.
- O `vigias/backup-estado.ps1`, que nasceu na #118, já escreve no `$Plugin`.

## Decisões fechadas

- **D1 — o `vigias/ERROS.md` mora no PLUGIN, sempre.**
  Porque: é o que o arquivo já é (rastreado no repo), é de onde o único leitor já
  lê, e é o que a execução agendada realmente produz hoje. As linhas 46, 65 e 131
  é que são o defeito; a 31 já estava certa.

- **D2 — nenhuma escrita de erro usa `$root`.**
  Porque: `$root` é a raiz de **dados** do usuário, e o `ERROS.md` não é dado do
  usuário — é registro de falha do próprio plugin. Misturar as duas foi o que
  criou o problema. A regra fica simples o bastante para ser conferida por uma
  trava: erro vai para `$plugin`, ponto.

- **D3 — uma trava impede a volta.**
  Porque: as três linhas erradas não vieram de uma decisão, vieram de descuido em
  três momentos diferentes. Sem trava, o quarto descuido é questão de tempo. A
  trava varre linha de execução e fica vermelha quando `ERROS.md` aparece colado
  a `$root`.

## Avaliado e descartado

- **Raiz de dados para o `ERROS.md`.** Era a outra metade da pergunta da issue.
  Descartada porque o arquivo é rastreado no plugin: escolher a raiz de dados
  deixaria um arquivo versionado órfão no repositório e obrigaria a mudar o
  `dados-batedor-repos.js` junto — que foi decidido na #110 há uma semana, com
  medição, na direção oposta.

- **Uma variável única `$erros` calculada uma vez no topo.** Reduz as quatro
  linhas a uma. Descartada por agora: some com o ponto onde a trava pega, porque
  a busca por `ERROS.md` colado a `$root` deixaria de casar em qualquer lugar.
  Trocar quatro `Join-Path` explícitos por uma indireção que a trava não enxerga
  é piorar a chance de regressão para ganhar três linhas.

- **Consertar só as três linhas, sem trava.** É o conserto que a issue pede
  literalmente. Descartado: o defeito nasceu três vezes por descuido, não por
  decisão. Conserto sem trava é o mesmo defeito com data marcada.

## Fora de escopo

- **O `run-vigia.ps1` inteiro.** Só as escritas de `ERROS.md` são tocadas.
- **A pasta de relatórios e o resto do que o `dados-batedor-repos.js` lê.**
  Resolvido na #110.
- **Rotação ou poda do `ERROS.md`.** O arquivo cresce sem limite; é outro
  assunto, e não foi medido aqui.

## Em aberto

- **O `ERROS.md` é rastreado num repositório público e recebe mensagem de erro
  em tempo de execução.** Hoje as mensagens são do próprio plugin e não carregam
  dado do usuário, mas nada garante isso: `Stop-ComErro` interpola `$configPath`,
  que pode conter caminho de máquina. Não foi medido nesta entrega, e merece
  issue própria.

- **Se algum `ERROS.md` já existe hoje na pasta de dados** de alguma máquina com
  `RFM_ROOT` definido, esta mudança o deixa órfão: as escritas passam para o
  plugin e o que estava lá para de crescer, sem ninguém avisar. Nesta máquina não
  existe (`RFM_ROOT` não está definido em lugar nenhum), então não há migração a
  fazer aqui — mas a entrega não trata o caso geral.
