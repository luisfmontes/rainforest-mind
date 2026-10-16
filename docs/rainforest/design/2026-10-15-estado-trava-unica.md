# estado.cjs: escritores do arquivo do fluxo se excluem (#545)

## Objetivo
Nenhum comando do `scripts/estado.cjs` apaga, ao regravar o arquivo do fluxo, o que outro processo gravou entre a leitura e a escrita dele: veredito do revisor, flake, decisão autônoma, pendência e marcações de estágio sobrevivem a escritas concorrentes.

## Decisões fechadas
- **D1 — Uma trava só por fluxo, `.<slug>.lock`, em toda gravação** — porquê: `veredito`, `registrar-flake` e `decidir` usam travas diferentes (`.veredito.lock`, `.flake.lock`, `.decidir.lock`), e cada uma só exclui a si mesma. Os três passam a usar a mesma trava, com a leitura, a montagem e a gravação dentro dela, como já fazem. `gravar()` entra nessa trava, a menos que o processo já a segure (os três comandos acima), e a trava é a `Trava` de `hooks/lib/trava-jsonl.cjs`, que já prova a morte do dono pelo PID.
- **D2 — Quem lê fora da trava mescla por campo na gravação** — porquê: `marcar`, `destinar`, `pendencia`, `exigir`, `liberar` e `liberar-teto` validam entre a leitura e a escrita, e o `marcar` do plano roda a `prova:` por até 120 s. Segurar a trava esse tempo faria o hook do veredito, que espera 10 s, falhar. Na gravação, dentro da trava, `gravar()` relê o arquivo vivo e mescla em três vias: a base é o que o comando leu (a primeira leitura, ou a última gravação do mesmo processo). Chave de topo ou campo de estágio (um nível dentro de cada objeto) que o comando não mudou fica com o valor vivo; o que ele mudou, inclusive removeu, fica com o dele. Os dois mudando o mesmo campo: o comando ganha, como hoje.
  - *Emenda 2026-10-16 (1ª revisão, achado [design]; Luís: seguir com as recomendadas):* a mescla perde item quando dois comandos acrescentam à mesma lista (dois `pendencia` em paralelo deixavam uma pendência só). Os comandos rápidos que acrescentam a lista, `pendencia`, `destinar`, `liberar` e `liberar-teto`, passam a ler, validar e gravar dentro da trava, como o `decidir`. A mescla por campo fica para quem valida devagar fora da trava: `marcar` e `exigir`. Saída do processo dentro da trava (`process.exit`) libera a trava.
  - *Emenda 2026-10-16 (2ª revisão, achado [design]; Luís: seguir com as recomendadas):* "o comando ganha" ainda apagava uma pendência aceita durante a validação de um `marcar` que fecha o estágio (ele remove `pendentes`, efêmero no fechamento). Quando o mesmo campo mudou nos dois lados, para valores diferentes, a mescla não escolhe vencedor: o comando recusa com exit 2 sem gravar nada, e rodá-lo de novo lê o estado atual, em que a pendência nova passa a ser cobrada pelo fechamento. Campos diferentes continuam mesclando.
- **D3 — Bateria determinística com dois processos** — porquê: a corrida é de milissegundos e não se reproduz por sorte. Uma costura de teste, `RFM_ESTADO_PAUSA_GRAVAR_MS`, faz o comando esperar logo depois de ler o estado (*emenda 2026-10-16:* não mais em `gravar()`; nos comandos que travam o comando inteiro, a espera cai dentro da trava), avisando `pausa-gravar: <slug>` no stderr para a bateria saber que a leitura já aconteceu. A bateria roda um `marcar` pausado e, durante a pausa, um `decidir` e um `pendencia`. Sem a mescla, o `marcar` apaga os dois; com ela, os três ficam. Sem a variável, nada muda no caminho normal.
- **D4 — Os nomes de trava antigos saem** — porquê: um processo de versão antiga do plugin ainda rodando pegaria `.veredito.lock` enquanto o novo pega `.<slug>.lock`, mas os dois só convivem durante a troca de versão e a mescla do D2 já cobre a escrita do outro lado. Manter os três nomes junto do novo seria trava dupla sem ganho.
- **D5 — A troca do arquivo tenta de novo com leitor aberto** — porquê: no Windows o `rename` do `.tmp` recusa com EPERM, EACCES ou EBUSY enquanto outro processo lê o JSON, e a leitura não passa pela trava. A gravação tenta de novo por até 2 s antes de falhar.
- **D6 — A trava não aparece no `git status`** — porquê: `.<slug>.lock` fica na pasta do estado, versionada, e o `marcar revisar ok` compara caminhos sujos. Uma gravação concorrente no instante da comparação acusaria arquivo novo. O `.gitignore` passa a ignorar `docs/rainforest/estado/.*.lock` e `docs/rainforest/estado/*.tmp`.

## Avaliado e descartado
- Segurar a trava durante o comando inteiro (D2): o `marcar` do plano roda a prova por até 120 s, e o hook do veredito desistiria em 10 s, perdendo o veredito com erro em vez de em silêncio.
- Mescla por estágio inteiro, sem descer ao campo (D2): `veredito` grava `revisar.vereditos` e `marcar` grava `revisar.status` no mesmo estágio. Por estágio, um apagaria o outro.

## Fora de escopo
- Um veredito `reprovado` gravado depois de o `marcar revisar ok` validar, mas antes de ele gravar: são campos diferentes (`vereditos` e `status`), então os dois ficam, e o estado mostra `ok` com um veredito reprovado. Antes o veredito sumia; agora fica visível. Recusar o `ok` nesse caso é trava de revisão, não de concorrência.
- O arquivo do caminho `leve` (`arqLeve`), que é outro arquivo e tem escritor único.
- Concorrência nos outros JSON do plugin (ideias, foco, sessões), que têm trava própria.

## Varredura
docs/rainforest/varredura/2026-10-15-estado-trava-unica.txt — só a própria #545 trata do tema. A #363 (veredito no worktree errado) e o PR #68 (trava por PID em `trava-jsonl.cjs`) são a base que este design reaproveita, sem mudança neles.

## Em aberto
nada
