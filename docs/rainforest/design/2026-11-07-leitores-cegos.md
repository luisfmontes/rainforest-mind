# Design: leitor cego do plano e diagnóstico cego no depurar

## Objetivo
Pôr um leitor **sem o contexto da sessão** nos dois pontos em que hoje a mesma sessão julga o
próprio raciocínio:

- **No fim do `plano`:** antes de marcar `ok`, um agente que nunca viu a conversa lê o design e o
  plano como o executor vai ler. Ele procura instrução que deixa decisão de design para quem
  implementa. Hoje o `plano` fecha só com as checagens mecânicas do `estado.cjs`, e o executor
  é um haiku que recebe só o texto da tarefa.
- **Na Fase 3 do `depurar`:** um segundo diagnóstico recebe só o sintoma e o repro, nunca a
  hipótese da sessão. Hoje quem ranqueia as hipóteses é a mesma sessão que as criou. Se os dois
  discordam, decide uma checagem cujo resultado é diferente para cada causa.

As ideias são `leitor-cego-do-plano-antes-do-codigo` e `depurador-com-diagnostico-cego`, da
triagem dos salvos do Instagram (relatorios/2026-11-06-salvos-instagram.md). O Luís delegou o
fluxo em modo automático em 2026-11-07 ("pode fazer no modo automatico vai fazendo oq vc
tiver"). As decisões marcadas **[sessão]** são a recomendada, sem rodada, e ficam para veto no PR.

As fontes foram lidas no código:
- `google/elephant-goldfish-model` (Apache-2.0): `agents/implementation_readiness.md`, o modo
  REVIEW com os vetores "lacuna de acionabilidade" e "lacuna de prontidão".
- `Raj9914/elephant-goldfish` (MIT): `claude/commands/eg-fix-bug.md`, Step 2, com o prompt de
  diagnóstico e o procedimento de desempate.

## Decisões fechadas
- **D1 — O leitor cego do plano roda antes do `marcar plano ok`, sempre que o plano tiver tarefa de tipo implementar, configurar ou teste, ou sem tipo (que o plano trata como implementar)** — porquê: é aí que uma decisão deixada em aberto vira código errado do executor. Um plano só de docs ou pesquisa não tem implementador para confundir. **[sessão]**
- **D2 — Leitor do plano: agente `general-purpose` com `model: sonnet`, e o briefing manda só ler** — porquê: o `revisor` está declarado para o estágio `revisar` no manifesto (`.rainforest/agentes.padrao.json`), e o método dele é de diff. O `planejador` escreve plano. O `general-purpose` está liberado em todo estágio, não escreve pelo manifesto e nasce sem contexto. O `sonnet` basta para ler, e o `opus` herdado custaria mais sem ganho. **[sessão]**
- **D3 — O briefing leva só os caminhos do design, do plano e do repositório, e um texto fixo dizendo quem vai implementar (um haiku que recebe o texto da tarefa e os arquivos listados)** — porquê: o leitor tem que estar na posição do executor. Resumo da conversa ou intenção da sessão no briefing desfaz a cegueira. A pergunta dele é a da persona de origem: "sei exatamente o que codar, onde e como, só com este texto?". **[sessão]**
- **D4 — Achado sai em três graus, com a tarefa afetada e a orientação: bloqueante, maior ou menor. Bloqueante e maior se corrigem no plano antes do `ok`, ou ganham uma linha no plano dizendo por que ficam. Menor fica a critério da sessão** — porquê: são os graus da persona (Blocker, Major, Nit). Corrigir no próprio plano não sobe pergunta ao Luís, porque editar o plano é trabalho do estágio, não decisão de escopo. Achado que muda uma `D<n>` do design é outra coisa: para o fluxo como achado `[design]`, como a regra 16 já manda. **[sessão]**
- **D5 — O diagnóstico cego dispara no começo da Fase 3, em background, com o sintoma e o repro das Fases 1 e 2 (no despacho conjunto com o `depurador`, D7, só o que o usuário descreveu, porque essas fases ainda não rodaram). A sessão escreve as próprias 3 a 5 hipóteses enquanto ele roda e só então compara** — porquê: escrever antes de ler o dele é o que garante que a comparação é honesta, e rodar em paralelo não atrasa o turno. O prompt pede de 1 a 3 causas candidatas com `arquivo:linha`, a evidência de cada uma e uma checagem que prova ou derruba cada uma. Não pede conserto. **[sessão]**
- **D6 — Se os dois concordam, registra-se que a concordância é fraca (mesmo modelo); se discordam, roda-se a checagem discriminante de cada candidata e se monta a tabela candidata / checagem / resultado / veredito. Checagem inconclusiva leva a escolha ao Luís antes de qualquer conserto** — porquê: é o procedimento `settle-disagreement` da fonte. Reler código não desempata; resultado de comando desempata. A checagem que capturar o bug vira o teste da Fase 5. **[sessão]**
- **D7 — O subagente `depurador` não tem a ferramenta Agent. Quando a skill roda nele, o diagnóstico cego é de quem despachou: a janela principal despacha o `depurador` e o diagnóstico cego juntos e compara os dois relatos** — porquê: o cabeçalho de `agents/depurador.md` declara `disallowedTools: Agent`. Sem esta decisão, o passo novo seria letra morta justamente no caminho da regra 10. A skill diz ao subagente que pule o passo e avise no relato. **[sessão]**
- **D8 — Os prompts moram em `skills/plano/references/leitor-cego.md` e `skills/depurar/references/diagnostico-cego.md`, e o SKILL.md de cada uma ganha só o ponteiro e a regra de quando rodar** — porquê: o `skills/plano/SKILL.md` está com 15.365 bytes, e o teto da bateria é 16 KB. **[sessão]**
- **D9 — Os prompts são reescritos em português, sem copiar o texto das fontes, e o crédito fica neste design** — porquê: memória "crédito só quando copia código". As duas licenças (Apache-2.0 e MIT) permitiriam copiar, mas o texto daqui precisa falar a língua do fluxo (tarefa, `atende:`, executor haiku), e isso já é reescrita. **[sessão]**
- **D10 — Versão 2.6.0, com README e CHANGELOG no mesmo commit** — porquê: passo novo em duas skills é capacidade nova (MINOR), e o README acompanha toda entrega. **[sessão]**

## Avaliado e descartado
- Instalar o `google/elephant-goldfish-model`: é um plugin inteiro com dez personas e um orquestrador próprio de design → plano. Ele disputaria o fluxo com o `brainstorm` e o `plano`, e daqui só serve uma persona.
- Rodar as dez personas do Google no plano: o custo cresce com cada uma, e as outras (estilo, estrutura, crítica de design) se sobrepõem ao `revisar` e ao brainstorm adversarial. Só a prontidão de implementação ataca a lacuna do executor haiku.
- Segunda opinião por `codex exec` no diagnóstico, como a fonte oferece: dobra o custo por bug e depende de CLI externo autenticado. A concordância entre dois modelos diferentes vale mais, mas isso fica para depois de medir quantas vezes o diagnóstico cego discorda.
- Usar o `revisor` como leitor do plano: está declarado para `revisar` no manifesto, e o método embutido dele cobra diff e evidência de execução, coisas que um plano não tem.

## Fora de escopo
- Trava mecânica no `estado.cjs` que recuse `marcar plano ok` sem o leitor cego: primeiro se mede se o passo é seguido e se acha algo. Se for pulado, vira ideia de trava.
- O relatório de deriva entre design e código depois do merge (`deriva-design-codigo-pos-merge`): mesma fonte, outro momento do fluxo; continua plantado.
- Leitor cego do **design** antes do plano (a persona no modo BRAINSTORM): o brainstorm já é adversarial com o Luís, e o leitor do plano cobre o ponto em que a ambiguidade vira código.

## Varredura
docs/rainforest/varredura/2026-11-07-leitores-cegos.txt — nenhuma Issue, PR, branch ou commit sobre goldfish, leitor cego, diagnóstico cego ou `implementation_readiness`. "Contexto zerado" casa com o `revisar` e o `divergir`, que já usam agente sem contexto em outros momentos (diff entregue e espaço de decisão), e não com plano ou depuração. No `ideias.jsonl` casam só as duas ideias deste fluxo; a vizinha `autoavaliacao-do-metodo-contra-o-rastro` trata da autoavaliação das regras, não do plano.

## Em aberto
- Nada bloqueia. As decisões **[sessão]** ficam para veto no PR.
