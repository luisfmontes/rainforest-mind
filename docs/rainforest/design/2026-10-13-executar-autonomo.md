# executar-autonomo: o fluxo roda sozinho do plano aprovado até o PR mergeado

## Objetivo
Com o plano aprovado, a sessão leva o fluxo até o PR mergeado sem esperar o Luís: despacha cada camada, integra cada tarefa por script, roda o laço com o revisor, verifica, publica, espera o CI e mergeia. Ela só para e chama nas paradas reais, e avisa por push. A decisão que surge no meio do caminho vira registro, com a recomendada aplicada, e o Luís revisa no PR.

Enxerto do `execute` do wildz-data 1.0.126 (Rafael Siqueira). Lá a autonomia é instrução de skill ("does not pause for user input… runs autonomously until completion, ceiling hit, or unresolvable error", `skills/execute/SKILL.md:664`), com regra fixa para cada decisão e `PushNotification` no teto e no fim (`:640-643`). Não há hook `Stop`, `/loop` nem `ScheduleWakeup`. As decisões D1 a D7 são as recomendações da rodada 1, aceitas pelo Luís em 2026-10-13 ("1 3 4 5 recomendado", "2 recomendado", "recomendado").

## Decisões fechadas
- **D1 — Alcance: do plano aprovado (`plano ok`) até o PR mergeado. Design e plano continuam pedindo a palavra do Luís, e `executar`, `revisar`, `verificar` e `fechar` seguem sem ele.** — porquê: o design e o plano são onde ele decide; dali em diante, hoje, as paradas são espera e confirmação, não decisão.
- **D2 — Paradas que chamam o Luís. São seis, e qualquer outra coisa segue:**
  - um achado `[design]` do revisor;
  - a 3ª reprovação seguida (teto do laço);
  - um `flaky` terminal;
  - o teto de despachos;
  - o ambiente quebrado (exit 69);
  - um conflito com a `main` que não seja só de versão ou CHANGELOG.

  Conflito só de versão ou CHANGELOG se resolve sozinho: a versão do fluxo vale, e as duas entradas ficam no CHANGELOG, como no #512. Porquê: são as paradas em que a decisão é dele; as demais (reprovação comum, CI vermelho consertável, mutação que sobrevive) o laço já trata.
- **D3 — Aviso por `PushNotification`, uma linha, no começo de cada parada do D2 e no fim (PR mergeado ou fluxo parado).** Ele aparece na área de trabalho e, com Remote Control ligado, no celular. Progresso de rotina não notifica. Porquê: é a ferramenta que o harness já tem; aviso de rotina vira ruído e ele deixa de olhar.
- **D4 — Decisão que surge no meio: a sessão aplica a recomendada, registra no estado do fluxo e escreve na seção "Decidido sem você" do corpo do PR, e ele revisa no PR.** É uma exceção à regra 16 que só vale com o modo autônomo ligado e entre `plano ok` e o merge. Decisão que mexe numa `D<n>` do design não entra na exceção: é achado `[design]` e para (D2). Porquê: perguntar no meio é exatamente o que trava a execução; o registro preserva a palavra dele, só que depois.
- **D5 — Chave `executar-autonomo` no config: padrão desligado, ligada neste repo, no mesmo modelo do `fechar-mergear`. Com a chave desligada, nada muda.** — porquê: repo de cliente e repo de outra pessoa não passam a rodar sozinhos por atualizar o plugin.
- **D6 — Os agentes rodam em segundo plano, e a volta de cada um acorda a sessão, como no fluxo `executar-dag-painel`. Nada de um turno longo com `Agent` em primeiro plano.** — porquê: um agente lento não prende a janela, o Luís pode falar no meio, e o contexto não cresce num turno só.
- **D7 — A integração de cada tarefa vira um comando só: conferência da entrega, mutação, commit com trailer, `marcar` e remoção do worktree do agente. Ele responde aceito ou recusado com o motivo. Bateria e mutação longas rodam fora do teto de 10 min do Bash, como peça fixa e não improviso da sessão.** — porquê: no fluxo `executar-dag-painel` a integração montada à mão gerou boa parte dos tropeços (regex sem escape, mensagem barrada pelo gate, mutação morta no teto).

## Avaliado e descartado
- Turno único com agentes em primeiro plano, como no wildz-data: prende a janela e acumula contexto (D6).
- Hook `Stop` que impede o fim do turno: o `gate-agente-em-voo` já barra uma vez, e insistir viraria laço com o harness. A volta do agente em segundo plano já acorda a sessão.
- WhatsApp para o Luís como canal de aviso: exige depender da ponte no ar; o push basta (D3).
- Modo sempre ligado, ou ligado por linha no plano: ver D5.

## Fora de escopo
- Brainstorm e plano sem o Luís.
- Rodar sem sessão aberta (agendado ou em CI).
- Revisão final com modelo de outra família por padrão (a segunda opinião continua opcional).

## Varredura
`docs/rainforest/varredura/2026-10-13-executar-autonomo.txt`, com os termos autonomo, "rodar sozinho", PushNotification, ScheduleWakeup, integrar e overnight. Nenhuma Issue trata do assunto. Três ideias tocam nele:
- `perguntei-se-seguia-estagio-com-run-autonomo` (entre estágios, seguir sem perguntar), coberta por D1 e D4;
- `trabalho-autonomo-comecou-fora-do-fluxo`, coberta por D1, porque a autonomia só começa com plano aprovado;
- `2026-09-03-run-autonomo-gastou-a-janela-principal`, já colhida, cuja lição (relatório curto, mutação por script) o D7 reforça.

## Em aberto
