# Plano: Apoio ao dev, lote 2

Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-2.md

## O que não pode quebrar
- O contrato de veredito de uma linha (#327): `VEREDITO: ok` / `VEREDITO: reprovado` como última linha, negrito e crase aceitos, devolução da vez só na primeira parada (`stop_hook_active`).
- `critica-do-revisor.cjs` continua saindo 0 / 3 (`[design]` no início do achado) / 4, com `[design]` no meio da frase sem parar o laço.
- `conferir-prova` continua aceitando prova sem placar reconhecível que sai ≠ 0, e a exceção de arquivo ausente na base (126/127).
- `limpar-worktrees --remover` continua sem remover `sujo`, `de-outra-sessao`, `em-uso-recente`, `órfão`, `erro` nem worktree com agente em voo.
- `memoria.cjs buscar --json` continua devolvendo `[]` no vazio; a saída com resultado não muda.
- Nenhuma bateria existente (`hooks/testa-veredito-revisor.sh`, `scripts/testa-critica-do-revisor.sh`, `scripts/testa-conferir-prova.sh`, `scripts/testa-limpar-worktrees.sh`, `hooks/testa-erros-log.sh`, `scripts/testa-memoria.sh`) fica vermelha.

## Tarefas

### 1. Veredito coerente com os achados [tipo: implementar]
atende: D2, D3, D8
arquivos: `hooks/lib/achados-revisor.cjs`, `hooks/veredito-revisor.cjs`, `scripts/estado.cjs`, `scripts/critica-do-revisor.cjs`, `agents/revisor.md`, `skills/revisar/SKILL.md`, `hooks/testa-veredito-coerente.sh`, `hooks/testa-veredito-revisor.sh`, `scripts/testa-critica-do-revisor.sh`
depende de: nenhuma
busca:
- repo | grep -rn "\[design\]" scripts hooks | critica-do-revisor.cjs:103 reconhece [design] pela posição no início do achado; nenhuma contagem de severidade em lugar nenhum
- livro | claudex-loop runner.py:116-146 | APPROVED com achado high e REVISE sem achado são rejeitados por invariante
desfecho: estender
prova: `bash hooks/testa-veredito-coerente.sh`
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: if (veredito === 'ok' && achados.alta > 0) veredito = 'invalido';
  para: if (false) veredito = 'invalido';
  bateria: `bash hooks/testa-veredito-coerente.sh`
  fixture: testa-veredito-coerente.sh, caso "VEREDITO: ok com achado [alta] devolve a vez na primeira parada"
pronto quando: com o payload real de SubagentStop do revisor (`agent_type` `rainforest-mind:revisor`, `last_assistant_message` com achados numerados e a última linha `VEREDITO: ok`, um deles aberto por `[alta]`, e `Slug:` no primeiro prompt do transcrito), o hook devolve `{"decision":"block"}` com um motivo que cita a regra ("ok com achado [alta]") na primeira parada e grava `invalido` com `stop_hook_active: true`; `VEREDITO: reprovado` sem nenhum achado marcado também bloqueia na primeira parada; `ok` só com `[media]`/`[baixa]` e `reprovado` com um `[baixa]` gravam normalmente; `[média]` com acento conta; `[alta]` citado no meio de uma frase não conta; `critica-do-revisor.cjs` sai 4 para reprovado sem achado marcado e 0 para reprovado com um `[media]` — provado por `bash hooks/testa-veredito-coerente.sh`. A forma da regra no hook é a linha do `de:`, e a contagem mora em `contarAchados(texto)` de `hooks/lib/achados-revisor.cjs`, reusada pelo `critica-do-revisor.cjs` (o reconhecimento de posição do `[design]` vai para a mesma lib). `agents/revisor.md` e `skills/revisar/SKILL.md` dizem o formato `[alta]|[media]|[baixa]` no início de cada achado e as duas regras de coerência. Nenhum caso de teste afirma sobre o texto do fonte.

### 2. Prova que não rodou caso nenhum é recusada [tipo: implementar]
atende: D2, D4
arquivos: `scripts/conferir-prova.cjs`, `scripts/testa-conferir-prova-sem-caso.sh`
depende de: nenhuma
prova: `bash scripts/testa-conferir-prova-sem-caso.sh`
mutacao:
  arquivo: `scripts/conferir-prova.cjs`
  de: const semCaso = placar !== null && placar.ok === 0 && placar.falhou === 0;
  para: const semCaso = false;
  bateria: `bash scripts/testa-conferir-prova-sem-caso.sh`
  fixture: testa-conferir-prova-sem-caso.sh, caso "prova que sai 1 com placar ok: 0 falhou: 0 é recusada"
pronto quando: num repo git temporário com um plano real cuja tarefa `implementar` tem `prova:` apontando para uma bateria que existe na base e sai 1 imprimindo `ok: 0   falhou: 0`, `node scripts/conferir-prova.cjs` (na forma que o `estado.cjs marcar --estagio plano` usa) sai ≠ 0 e diz que a prova não executou caso nenhum; a mesma bateria imprimindo `ok: 3   falhou: 1` e saindo 1 é aceita; saída `0 ok, 0 falhou` também é recusada; saída sem placar reconhecível e exit 1 é aceita como hoje; prova cujo arquivo não existe na base continua aceita — provado por `bash scripts/testa-conferir-prova-sem-caso.sh`. O placar é lido com `extrairPlacar` importado de `scripts/conferir-mutacao.cjs` sobre stdout+stderr da prova, e a forma da regra é a linha do `de:`.

### 3. Limpeza de worktree só com prova afirmativa [tipo: implementar]
atende: D2, D5, D8
arquivos: `scripts/limpar-worktrees.cjs`, `scripts/testa-limpar-worktrees-arquivo.sh`
depende de: nenhuma
prova: `bash scripts/testa-limpar-worktrees-arquivo.sh`
mutacao:
  arquivo: `scripts/limpar-worktrees.cjs`
  de: const alcancavel = headAlcancavel(item.caminhoOriginal);
  para: const alcancavel = true;
  bateria: `bash scripts/testa-limpar-worktrees-arquivo.sh`
  fixture: testa-limpar-worktrees-arquivo.sh, caso "worktree destacado com commit próprio ganha refs/rainforest/arquivo antes de sair"
pronto quando: num repo git temporário montado pela bateria, com um worktree limpo em HEAD destacado que tem um commit que nenhuma branch alcança, `node scripts/limpar-worktrees.cjs --remover` (com a raiz da bateria) remove o worktree e deixa `refs/rainforest/arquivo/<nome-do-dir>` apontando para aquele commit, e a saída diz que arquivou; um worktree limpo cuja branch alcança o HEAD sai sem criar ref; quando a sonda de alcance falha (git que erra, simulado pela bateria), o worktree fica `erro` e não é removido — provado por `bash scripts/testa-limpar-worktrees-arquivo.sh`. A forma da decisão é a linha do `de:`, com `headAlcancavel` devolvendo `true`, `false` ou `null` (sonda falhou).

### 4. Saúde: erro de ferramenta não medido não vira ok [tipo: implementar]
atende: D2, D6
arquivos: `scripts/erros.cjs`, `scripts/saude.cjs`, `scripts/testa-saude-nao-medido.sh`
depende de: nenhuma
prova: `bash scripts/testa-saude-nao-medido.sh`
mutacao:
  arquivo: `scripts/erros.cjs`
  de: try { bruto = fs.readFileSync(alvo, 'utf8'); } catch (e) { return e.code === 'ENOENT' ? [] : null; }
  para: try { bruto = fs.readFileSync(alvo, 'utf8'); } catch { return []; }
  bateria: `bash scripts/testa-saude-nao-medido.sh`
  fixture: testa-saude-nao-medido.sh, caso "log de erros ilegível sai aviso não medido"
pronto quando: com o log de erros real do plugin no lugar que `erros.cjs` lê, trocado pela bateria por um diretório com o mesmo nome (leitura falha com erro diferente de ENOENT), `errosRecentes` / `checarErros` do `saude.cjs` devolve um achado `aviso` com "não medido" no texto; com o caminho ausente devolve `ok` "nenhum registrado"; com uma linha de erro recente devolve o que devolve hoje; os outros chamadores de `recentes()` em `erros.cjs` (`texto` e o vizinho) tratam `null` sem lançar — provado por `bash scripts/testa-saude-nao-medido.sh`. A forma da distinção é a linha do `de:`.

### 5. buscar explica o vazio [tipo: implementar]
atende: D2, D7
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria-vazio-explicado.sh`
depende de: nenhuma
prova: `bash scripts/testa-memoria-vazio-explicado.sh`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: console.log(vazioExplicado(totalNoEscopo, temFiltro));
  para: console.log('(nenhum resultado)');
  bateria: `bash scripts/testa-memoria-vazio-explicado.sh`
  fixture: testa-memoria-vazio-explicado.sh, caso "filtro que exclui tudo diz quantas observações existem no escopo"
pronto quando: num banco temporário (`RFM_ROOT` em `mktemp -d` fora do worktree) com duas observações do mesmo projeto, `node scripts/memoria.cjs buscar --texto termoinexistente` sai 0 com `(nenhum resultado — 2 observação(ões) no escopo; os filtros excluíram todas)`; `buscar --desde 2030-01-01` diz o mesmo; num banco iniciado sem observações, `buscar --texto x` diz `(nenhum resultado — banco sem observações)`; com `--json` as três saem `[]`; uma busca com resultado sai igual à de hoje — provado por `bash scripts/testa-memoria-vazio-explicado.sh`. A forma é a linha do `de:`; `totalNoEscopo` conta sem os filtros de texto e data, mas respeitando `--projeto`.

### 6. Versão 1.76.0, CHANGELOG e README [tipo: docs]
atende: D1, D9
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4, 5
mutacao: n/a
  motivo: metadado de versão e documentação, sem comportamento a inverter
pronto quando: com o diff real das tarefas 1 a 5, os dois `plugin.json` dizem `1.76.0`, o CHANGELOG tem a entrada 1.76.0 com uma linha por decisão entregue (D3 a D7) citando o `arquivo:linha` do furo que cada uma fecha, e o README documenta o formato de severidade do revisor e o vazio explicado do `buscar` onde já documenta o vizinho de cada um — provado por `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(require('./'+f).version)"` devolvendo `1.76.0` duas vezes e pela leitura do revisor casando cada linha do CHANGELOG com o diff.
