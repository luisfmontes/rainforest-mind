## Resumo

Dois bloqueios falsos a menos, sem abrir o que cada gate protege. Versão 2.17.1.

```
portaria (D1)
  protheusAberto lê <raiz>/docs/plans e <raiz>/<pasta>/docs/plans   (#728)
  .gates.json sem branch abre se os COMMITS da branch o tocam (ou o plano/design dele)
  trilho protheus aberto e vinculado à branch libera o escritor mesmo com docs/rainforest/estado/ na raiz   (#729)
gate de publicação (D2)
  gh api orgs/<org>/... , users/<u>/... , repos/<d>/<r>/...  -> o destino no início do endpoint não se confere   (#726)
  a troca é na POSIÇÃO do token (forma crua = valor); corpo por pipe/<<< e nome de arquivo em contents/ seguem conferidos
  o endpoint decodificado também se confere (contents/ter\mo702.md barra)
```

## Evidência

- **Antes:** `gh api orgs/<org>/teams -X POST -f name=x -f privacy=closed` barrava pelo nome da org; `protheus-implementer` em repositório multi-cliente saía `fora-de-fluxo`.
- **Depois**, no HEAD desta branch:
  - `node hooks/testa-portaria-fluxo-pulado.cjs`: `ok: 116   falhou: 0` (seção O, casos O1–O17)
  - `bash hooks/testa-gate-publicacao-destino.sh`: `== resultado: 330 ok, 0 falha(s) ==` (seção #726)
  - vizinhas da lib `tokens-comando.cjs` (ganhou `ini`/`fim` não enumeráveis): fechar-issue `669 ok`, staging-total `199 ok`, mensagem-commit `93 ok`, cwd-efetivo `85 ok`; aviso-fluxo `10 ok`, bloqueio-fluxo `37 ok`, colapso-continuacao `19 ok`
  - `conferir-fluxo.cjs mutacoes`: tarefas 1, 2, 3, 4 e 6 vermelhas; 5 n/a.

Quatro rodadas de revisão independente (a 1ª e a 2ª reprovaram; a 3ª aprovou com um preexistente que foi consertado aqui; a 4ª aprovou), mais três alertas da revisão de segurança automática, todos fechados.

## Perigo de merge

**Porta:** mão dupla. Hooks decidem exit 0 ou 2; um revert devolve o comportamento anterior.
**Raio de impacto:** médio. A portaria decide todo despacho de agente que escreve; o gate de publicação roda em toda escrita e todo `gh`. O que muda só tira bloqueio nas formas medidas.

## Deixado para depois

nada ficou para depois

Fora deste PR:
- #732 fica aberta (Refs #732): o caso dela (worktree novo, `.gates.json` recente sem `branch`, branch `fix/...` que não toca o plano) segue barrado, porque a D1.3 emendada exige vínculo com a branch.
- Resíduos aceitos (preexistentes, exigem ofuscação deliberada): crase do PowerShell, percent-encoding e expansão vazia do shell no endpoint de `gh api`. Estão no design.

## Decidido sem você
- O diff da branch (D1 parte 2) vale para .gates.json com campo branch? → Nao: so para .gates.json sem branch; com branch, so a igualdade decide. Porquê: o campo branch e o vinculo explicito do arquivo com uma branch (D10 do fluxo-pulado); o leitor cego apontou o refinamento
- Revisão 2: a troca do destino no endpoint passou a ser pela posição do token (o tokenizador ganhou `ini`/`fim`), em vez de busca por texto.
- Revisão 3: o endpoint decodificado passou a ser conferido (preexistente no arquivo da entrega).

Closes #726, closes #728, closes #729. Refs #732.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
