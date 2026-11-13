# conta: o vigia não trava em silêncio, a pasta manual volta, e o problema chega à sessão

## Objetivo
Issue #693. Desde 2026-10-14 o vigia de troca de conta (`conta.cjs vigiar`, tarefa `\ClaudeVigias\troca-de-conta`, a cada minuto) abortava em toda rodada: `~/.claude-personal` existia sem `.credentials.json`, `pastasAtivas()` (`scripts/conta.cjs:64`) a contava, `infoPasta` (`:401`) lançava `pasta pessoal sem credencial`, e o `main().catch` escrevia no stderr que o `conhost --headless` descarta (a tarefa mostra resultado 0). Nada era decidido e nenhum evento era gravado. Nas duas vezes em que a pasta `trabalho` foi trocada à mão para a conta pessoal (18/10 e 01/11), ela nunca voltou e o aviso de limite nunca saiu; o Luís fez `/login` à mão (22/10 e 12/11).

Medido em 2026-11-12, num home temporário com o servidor falso da bateria (`scripts/fixtures/conta/servidor.cjs`), pasta `trabalho` na conta pessoal com `manual:true`, estacionado vivo, pessoal a 100% na semana:

| estado | saída do `vigiar` | eventos novos |
|---|---|---|
| `.claude-personal` existe sem credencial | `erro: pasta pessoal sem credencial`, exit 1 | nenhum |
| `.claude-personal` ausente | `avisar trabalho: seven_day de pessoal em 100%` | `manual_no_limite` |
| ausente, login da pasta vencido, `reserva-pessoal` vazia | `aviso: uso de pessoal indisponível: login vencido` (stderr), `sem ação` | nenhum |

Remédio de ambiente já aplicado (Q2 do Luís): a pasta foi renomeada para `~/.claude-personal.stub-20261014`, e uma rodada do vigia instalado saiu `rodada concluída`, exit 0.

O mod (`hooks/conta.ts`, `hooks/conta-puro.mjs`) já mostra toast para `renovacao_falhou`, `manual_no_limite` e outros eventos; o toast some sozinho e não chega ao modelo, e evento que o vigia nunca grava não vira toast.

Brainstorm em modo autônomo, com duas decisões do Luís em 2026-11-12 ("faz o recomendado"): renomear a pasta-stub (fora do repo, já feito) e a D3 abaixo.

## Decisões fechadas
- **D1 — Pasta sem credencial não derruba a rodada.** `vigiar` monta `pastas` só com as pastas ativas que têm credencial; a pasta ativa sem credencial fica de fora da decisão e gera um evento `pasta_sem_credencial` (com a pasta no campo `pasta`), gravado uma vez enquanto a situação persistir (não a cada minuto: o vigia confere o último evento desse tipo para a pasta antes de gravar, e só grava de novo depois de uma rodada em que a pasta teve credencial). `status` e os outros subcomandos não mudam. — porquê: a pasta trocada e a outra pasta são independentes; uma pasta sem login não é motivo para a outra ficar sem decisão.
- **D2 — Rodada que aborta vira evento.** No `vigiar`, exceção que escapa da rodada grava `vigia_falhou` com `motivo` = mensagem segura (`msgSegura`), antes de sair com exit 1. Não repete: só grava se o último evento `vigia_falhou` tiver outro `motivo`, ou se houve rodada concluída depois dele (a rodada concluída grava nada; a marca é o `mtime` de um arquivo `vigia-ok` em `<dados>/contas`, tocado ao fim de toda rodada sem exceção). — porquê: o `conhost --headless` engole stderr e exit code; o único canal que sobrevive é o `eventos.jsonl`.
- **D3 — Pasta trocada à mão volta quando a conta escolhida passa do limite.** Revoga em parte a D8 de `2026-10-10-troca-de-conta` (decisão do Luís em 2026-11-12, Q3 recomendada). Em `decidir`, pasta `manual` fora de casa cuja conta em uso tem `five_hour` ou `seven_day` em `>= trocarEm`, e cuja conta de casa tem folga (`five_hour < destinoMax5h` e `seven_day < destinoMaxSemana`, mesmas chaves da troca) e estacionado, recebe ação `voltar` pela mesma `checarVida` da volta comum. A volta grava o evento `voltar`, como a volta do vigia já grava, e deixa a pasta com `manual: false`. Sem folga na casa, sem dado de uso da casa ou sem estacionado, continua o `avisar` (`manual_no_limite`) de hoje. Pasta manual em casa, ou abaixo do limite, não muda. — porquê: a troca manual é para escapar de um limite; quando a conta escolhida também chega ao limite, a escolha deixou de servir, e o `/login` à mão era o que o Luís estava fazendo no lugar do vigia.
- **D4 — Uso ilegível de pasta fora de casa vira evento.** Quando a conta em uso de uma pasta fora de casa fica sem dado de uso (`usos[conta]` ausente ou incompleto) por 30 min seguidos, o vigia grava `uso_ilegivel` uma vez por período fora de casa (zera quando a pasta volta ou o dado volta). O início do período é guardado em `estado.json`, na pasta (`semUsoDesde`, epoch ms). — porquê: sem o dado, nem a D3 nem o aviso de limite disparam, e hoje isso só sai no stderr.
- **D5 — O problema de conta chega à sessão por um hook.** Hook novo `hooks/conta-aviso-sessao.cjs`, registrado em `SessionStart` e `UserPromptSubmit`, sem rede, sem trava e sem `spawn`: lê `<dados>/contas/eventos.jsonl` (o mesmo diretório que o `conta.cjs` resolve, incluindo `RFM_CONTA_DADOS`) e injeta em `additionalContext` uma linha por problema aberto que esta sessão ainda não viu. Problema aberto: o último evento de cada chave `(tipo, pasta ou login)` entre `vigia_falhou`, `pasta_sem_credencial`, `uso_ilegivel`, `manual_no_limite` e `renovacao_falhou`, com no máximo 7 dias, e sem evento posterior que o resolva (`trocar`/`voltar`/`reconciliado` da mesma pasta resolvem `manual_no_limite` e `uso_ilegivel`; `vigia_falhou` fecha quando a marca `vigia-ok` da D2 é mais nova que ele; `pasta_sem_credencial` fecha com um evento `pasta_com_credencial` da mesma pasta, que o vigia grava na primeira rodada em que a credencial volta; `renovacao_falhou` de um login segue o critério de `falhasDeRenovacao` — aberta enquanto o arquivo do login existe e vence em menos de 1 h —, que passa a morar em `scripts/lib/conta-avisos.cjs` e é usado pelos dois). Cada linha traz o comando que resolve (`/conta preparar <conta> --refazer`, `/conta <pasta>`, ou `/conta status`; D8). "Já visto" é por sessão: um arquivo `<dados>/contas/avisos-vistos/<session_id>.json` com as chaves já injetadas; arquivo de sessão com mais de 7 dias é apagado na leitura. Sem `eventos.jsonl`, sem `session_id` ou com erro de leitura, o hook sai 0 sem saída. — porquê: o toast do mod some e não chega ao modelo; a sessão é onde alguém pode agir (regra 14: anunciar em uma linha o que o ambiente impede).
- **D6 — Texto e orçamento.** A injeção é uma seção `## Conta (regra 14)` com no máximo 5 linhas de até 200 caracteres; o que passar vira `... e mais N: /conta status`. — porquê: o SessionStart tem teto de entrega por hook, e o UserPromptSubmit entra em todo turno.
- **D7 — O aviso de uso ilegível e o de pasta manual no limite ganham evento de fechamento.** Emenda da revisão 1 (achado 3; decisão do Luís em 2026-11-12, Q2 recomendada). O vigia grava `uso_legivel` da pasta quando o dado de uso da conta em uso volta (ou a pasta está em casa) e o último evento da pasta entre `uso_ilegivel`, `uso_legivel`, `trocar`, `voltar` e `reconciliado` é um `uso_ilegivel`. Grava `manual_fora_do_limite` quando a pasta deixou a troca manual fora de casa, ou quando a conta em uso tem dado e está abaixo do `trocarEm` nas duas janelas, e o último evento da pasta entre `manual_no_limite`, `manual_fora_do_limite`, `trocar`, `voltar` e `reconciliado` é um `manual_no_limite`. Sem dado, o `manual_no_limite` fica aberto. No hook, `uso_legivel` fecha só o `uso_ilegivel` e `manual_fora_do_limite` fecha só o `manual_no_limite` da mesma pasta, além dos três resolvedores da D5. — porquê: sem evento de fechamento, o aviso chegava a toda sessão nova por até 7 dias depois de o problema acabar, e aviso falso ensina a ignorar o aviso.
- **D8 — O comando do aviso funciona fora deste repositório, e o trecho livre perde os sinais de marcação.** Emenda da revisão 1 (achados 2 e 5; mesma decisão). As linhas apontam `/conta status` e `/conta preparar <conta> --refazer` (o `commands/conta.md` repassa os argumentos ao script do plugin), nunca `node scripts/conta.cjs`, que só existe com o cwd neste repositório. O trecho livre do log (o `motivo` do `vigia_falhou` e o erro do `renovacao_falhou`) troca `#`, crase, `<` e `>` por espaço, além da quebra e do controle. — porquê: o aviso aparece em qualquer repositório em que o Luís trabalha, e o texto do log entra no contexto do modelo.

## Avaliado e descartado
- **Tirar a pasta-stub e parar aí.** Resolve o caso de hoje, mas qualquer sessão com `CLAUDE_CONFIG_DIR` apontando para `~/.claude-personal` recria a pasta, e o vigia volta a travar sem ninguém ver.
- **Avisar só pelo toast do mod.** Já existe para `renovacao_falhou` e não foi visto; toast some e não chega ao modelo.
- **Hook rodando `conta.cjs status`.** Faz rede e pega trava a cada turno; o hook lê só o `eventos.jsonl`.
- **Manter a D8 e só avisar (Q3 opção B).** O Luís escolheu a volta automática.

## Varredura
docs/rainforest/varredura/conta-reserva-avisa.txt — a #693 é a única aberta sobre o vigia, reserva ou troca de conta.

## Em aberto
- Nada que bloqueie o plano. A versão (MINOR, por hook novo) se acerta no rebase, conforme o PR do `gate-segmentador` (2.12.3) entrar antes ou depois.

## Fora de escopo
- A causa do `token HTTP 400` da `reserva-team` (renovação recusada pelo servidor desde 05/11): o `preparar trabalho --refazer` do Luís em 2026-11-12 trocou a reserva; se voltar, o evento já sai pela D5.
- Os outros `esperar`/`null` silenciosos de `decidir` (abaixo do limiar, destino sem folga): são estado normal, não falha.
- O toast do mod continua como está.

## Pronto quando
- Com um home temporário com `.claude-personal` sem credencial, `conta.cjs vigiar` sai 0, decide para a pasta `trabalho` e grava um `pasta_sem_credencial` (um só em duas rodadas).
- Com `infoPasta` ou outra etapa lançando, `eventos.jsonl` ganha `vigia_falhou` uma vez em duas rodadas seguidas com o mesmo erro.
- Pasta `trabalho` manual na pessoal a 100% na semana, casa com folga e estacionado vivo: `vigiar` devolve a pasta (`trocar` para team, `manual:false`).
- O hook injeta a linha de cada problema aberto uma vez por sessão, e nada quando não há problema.
