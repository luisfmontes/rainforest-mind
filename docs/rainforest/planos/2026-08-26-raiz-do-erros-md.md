# Plano: a raiz do vigias/ERROS.md (#112)

Design: docs/rainforest/design/2026-08-26-raiz-do-erros-md.md

## O que não pode quebrar

- **As mensagens de erro continuam saindo.** A mudança é de destino, não de
  conteúdo: nenhum caminho de erro pode ficar mudo.
- **O `-Cwd` inexistente continua saindo 1** (linha 46) e o `Stop-ComErro`
  continua saindo 1 (linha 65). Trocar a raiz não pode mexer no exit.
- **Nada é escrito fora da caixa de teste.** `RFM_ROOT` para sandbox sempre; o
  `~/.rainforest` real nunca é tocado.
- **O repo é PÚBLICO:** nenhum caminho de máquina, usuário ou credencial entra em
  arquivo versionado.
- **A tarefa agendada é lida, nunca escrita.**

## Tarefas

### 1. As três escritas de erro passam a usar $plugin [tipo: implementar]
atende: D1, D2
arquivos: `vigias/run-vigia.ps1`, `scripts/testa-erros-md-raiz.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: a escrita de erro do `-Cwd` inexistente, que passou a usar `$plugin`
  para: a mesma linha com `$root` de volta
  bateria: `bash scripts/testa-erros-md-raiz.sh`
  fixture: o caso "com RFM_ROOT definido, as escritas de erro caem todas no mesmo arquivo" de `scripts/testa-erros-md-raiz.sh`
pronto quando: numa caixa com `RFM_ROOT` apontando para uma pasta de dados **diferente** do plugin, cada um dos caminhos de erro é provocado de verdade e a bateria mostra que **todas** as linhas caíram no `ERROS.md` do plugin e **nenhuma** na pasta de dados — contando as linhas dos dois arquivos, não lendo o fonte

### 2. Trava: ERROS.md não volta a ser escrito na raiz de dados [tipo: implementar]
atende: D3
arquivos: `scripts/testa-erros-md-raiz.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: um comentário qualquer do arquivo
  para: `Out-File -Append -Encoding utf8 (Join-Path $root "vigias\ERROS.md")`
  bateria: `bash scripts/testa-erros-md-raiz.sh`
  fixture: o caso "nenhuma escrita de ERROS.md usa a raiz de dados" de `scripts/testa-erros-md-raiz.sh`
pronto quando: a trava varre **linha de execução** dos `.ps1` de `vigias/`, fica vermelha quando `ERROS.md` reaparece colado a `$root`, e fica **verde** com a mesma string em comentário — provado nos dois sentidos, porque trava que obriga a apagar a explicação apaga a razão
