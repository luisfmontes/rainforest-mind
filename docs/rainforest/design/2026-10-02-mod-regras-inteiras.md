# Mod: regras inteiras e memoria no system prompt via prompt.compose

## Objetivo
Entregar a abertura do rainforest-mind (regras com elaboracao, foco sem corte e
memoria) como secao do system prompt, por um mod (Claude Mods, Claude Code
2.1.287+), e deixar de depender do teto de entrega de hook do SessionStart, que
hoje obriga a mandar so o nucleo das regras e corta foco e memoria.

## Decisões fechadas
- **D1 — Escopo: regras + foco + memoria pelo mod; busca e registro ficam fora** — porque: regras, foco e memoria sofrem do mesmo corte e se resolvem pelo mesmo mecanismo; a ferramenta `buscar_memoria` e o registro por `$.model.fork` tem risco proprio e ficam plantados.
- **D2 — Mecanismo: uma secao `rainforest-mind:abertura`, `scope: 'session'`, acrescentada ao fim do `prompt.compose`** — porque: e o unico caminho medido. Em 2026-10-02, o prototipo `rf-teto` com 32.066 chars chegou inteiro numa sessao nova (`claude -p --plugin-dir`, canarios 1024/3072/16384/32000), e o controle sem o mod devolveu `NENHUM`.
- **D3 — Orcamento das regras: 32 KB, nucleo + elaboracao das regras 16, 12, 11 e 17** — porque: sao as quatro mais citadas nas 298 observacoes (r16=30, r12=28, r11=17, r17=14; 89 citacoes) e cabem em ~31 KB. Subir para 48 KB (r3 e r10) e so mudar o numero, se elas seguirem falhando.
- **D4 — Selecao das regras: lista fixa num arquivo de configuracao do plugin, mais um script que sugere a nova ordem a partir das observacoes, rodado a mao** — porque: um ranking automatico mudaria o system prompt sem decisao de ninguem, quebraria o cache e deixaria os testes instaveis.
- **D5 — Orcamento da memoria: 8 KB, sem o corte de 160 chars por linha** — porque: ~2 mil tokens bastam para as observacoes recentes chegarem inteiras; manter 3.000 B so trocaria o corte por linha por menos linhas.
- **D6 — O mod entrega tudo o que o `foco-session-start` entrega hoje (regras, foco, dependencias), e o hook fica como reserva** — porque: nucleo e foco saem do hook num bloco so; cortar so o nucleo seria cirurgia de texto num formato que muda.
- **D7 — Com o mod ativo, ele remove a entrada do SessionStart via `classic.SessionStart` (`additionalContext`)** — porque: sem isso o modelo recebe as regras duas vezes, e o nucleo diz "leia o arquivo" com o texto inteiro ali do lado. Sem mod (Codex, Claude Code antigo), o hook segue identico.
- **D8 — Fonte unica: o mod nao reimplementa a montagem; chama os geradores `.cjs` existentes por `$.process.run`, com o orcamento como parametro, e recebe JSON** — porque: o modulo do mod nao tem Node nem SQLite, e duas implementacoes da abertura divergiriam. Hook e mod passam a ser so dois destinos do mesmo texto.
- **D9 — A secao e montada uma vez, no `session.start`, e reaproveitada** — porque: texto estavel mantem o cache do prompt. Remonta so quando o proprio engine reabre a sessao (`/clear`).
- **D10 — A primeira tarefa e provar o carregamento pelo marketplace: publicar uma versao com um mod minimo (canario) e conferir numa sessao nova; falhou, para e volta com a medicao** — porque: `claude plugin validate` aceitou um `hooks.json` com `hooks` e `modules` juntos (exit 0), mas carregar em runtime a partir do marketplace nao foi provado. A alternativa (`CLAUDE_CODE_PLUGIN_DIRS`) mexeria no ambiente das duas contas.
- **D11 — A bateria de orcamento aprende o destino mod: as partes (32 KB de regras + 8 KB de memoria + foco) precisam caber no teto declarado, conferido por teste** — porque: a #250 mostrou partes de orcamento somando mais que o todo, sem nada conferindo.
- **D12 — Verificacao pela saida real: canario e2e numa sessao nova com o plugin, mais o controle sem ele** — porque: o `$.prompt.compose()` chamado de um comando lista o prompt `lean`, diferente do que a sessao principal envia, e nao prova o que chegou ao modelo.

## Avaliado e descartado
- Hot reload na sessao aberta: o mod recarregou e compos a secao, mas ela nao chegou ao modelo da sessao ja aberta (medido em 2026-10-02). Vale so para a sessao seguinte, o que basta para a abertura.
- `$.prompt.compose()` como prova do que chega: devolve o prompt `lean` (lista comecando em `lean_body`), nao o da sessao principal.
- As 120 KB inteiras das elaboracoes: ~30 mil tokens por sessao, possivelmente multiplicados por subagente.
- So o nucleo atual sem corte: quase nao muda nada em relacao a hoje.
- Ranking automatico das regras a cada abertura: muda o prompt sem decisao, quebra o cache e os testes (D4).
- Cortar so o nucleo de dentro do texto do hook: fragil a qualquer mudanca de formato (D6).
- `prompt.context` (blocos da primeira mensagem) no lugar do `prompt.compose`: nao foi medido; o `prompt.compose` foi.

## Fora de escopo
- Ferramenta `buscar_memoria` via `$.tool.register` e registro de observacao via `$.model.fork`/`session.append` — viram ideias plantadas.
- As outras ideias de mod ja plantadas: gates em `tool.call`, faixa acima do prompt, jornada e janela parada por relogio.
- Codex: nao tem mods; continua recebendo a abertura pelo hook, sem mudanca.
- Mexer no `ambiente` do usuario (settings, env, `CLAUDE_CODE_PLUGIN_DIRS`).

## Varredura
docs/rainforest/varredura/2026-10-02-mod-regras-inteiras.txt — nenhuma issue, PR ou branch sobre mods ou `prompt.compose`; as unicas entradas no `ideias.jsonl` sao as plantadas nesta sessao. Achou a historia do orcamento de abertura (#10, #81/#85, #250, v0.48.0, `orcamento --agregado`), o que gerou a D11.

## Em aberto
- Se o `prompt.compose` tambem roda no prompt dos subagentes: os tipos nao dizem. E fato, medido na tarefa de D10 com um canario num subagente; se rodar, o plano decide o filtro (por `traits` ou equivalente) antes de subir o orcamento.
