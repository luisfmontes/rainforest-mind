# Design: a trava diária da manutenção poda as dos dias anteriores

## Objetivo
O hook `hooks/memoria-manutencao-session-start.cjs` cria `<raiz>/manutencao-<AAAA-MM-DD>.lock` uma
vez por dia e nunca remove as anteriores. Elas não têm efeito (só a do dia é consultada, pelo
`openSync(trava, 'wx')`), mas acumulam na raiz de dados: 46 arquivos em `~/.rainforest` em
2026-11-07. Ideia `manutencao-lock-acumula-na-raiz-de-dados`. Modo autônomo ("se tiver mais coisas
pode continuar, tem passe livre pra se auto melhorar", 2026-11-07): as decisões marcadas
**[sessão]** foram a recomendada, sem rodada, e ficam para veto no PR.

**Fato conferido:** nenhum outro script ou hook lê `manutencao-*.lock`
(`grep -rn "manutencao-" scripts hooks skills` só acha o próprio hook e o comentário de
`scripts/memoria.cjs:2411`). O PID gravado dentro da trava serve à bateria, que lê só a do dia.

## Decisões fechadas
- **D1 — Quem cria a trava do dia apaga as de dias anteriores [sessão]** — porquê: a poda roda uma vez por dia, no mesmo ramo que já ganhou a corrida do `'wx'`, então não há duas sessões podando ao mesmo tempo e não custa nada nas outras aberturas. Entra só arquivo cujo nome casa inteiro com `^manutencao-\d{4}-\d{2}-\d{2}\.lock$` e cuja data é menor que a de hoje (comparação de texto, que para `AAAA-MM-DD` é cronológica). A trava de hoje, uma de data futura (relógio voltou), o `manutencao.log` e qualquer outro arquivo ficam.
- **D2 — Poda que falha não derruba nada** — porquê: a regra do hook é exit 0 sempre. Erro ao listar a raiz ou ao apagar um arquivo (`EPERM`, `ENOENT` por corrida) é engolido arquivo a arquivo; os demais seguem, e o disparo da manutenção não depende da poda. A poda roda **depois** do `spawn`, para que nenhuma falha dela atrase ou impeça o filho.
- **D3 — Versão PATCH (2.8.1), com CHANGELOG** — porquê: conserto sem contrato novo.

## Avaliado e descartado
- Uma trava só (`manutencao.lock`) com a data dentro: perde a atomicidade do `'wx'` por nome, que é o que impede duas sessões de dispararem no mesmo dia.
- Podar pela idade do arquivo (`mtime`): o nome já traz a data, e `mtime` muda com cópia e backup.
- Podar no `scripts/memoria.cjs manutencao` (o filho): o filho roda com `RFM_ROOT` fixado e até ~1h; a poda é responsabilidade de quem cria a trava.

## Fora de escopo
- As 46 travas que já existem somem sozinhas na primeira abertura de sessão com a 2.8.1 instalada, pelo próprio D1.

## Varredura
docs/rainforest/varredura/2026-11-07-poda-trava-manutencao.txt — nenhuma Issue, PR ou branch fala da
trava diária da manutenção; as que casam "trava" e ".lock" são de outras travas (estado do fluxo,
catraca, `atualizar-cli.sh`). Casa só a ideia `manutencao-lock-acumula-na-raiz-de-dados`, sem
`ao_colher`. O `deriva --arquivo hooks/memoria-manutencao-session-start.cjs` lista
`2026-09-16-memoria-reconciliacao-e-consolidacao D1, D5 — intacta`: a poda não mexe no
`openSync(trava, 'wx')` nem no disparo do filho.

## Em aberto
- Nada bloqueia. As decisões **[sessão]** (D1) ficam para veto no PR.
