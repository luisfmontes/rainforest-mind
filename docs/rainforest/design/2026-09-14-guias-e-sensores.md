# Guias e sensores: cinco enxertos do Harness Engineering

## Objetivo

Enxertar no plugin o par **guia / sensor** de Martin Fowler — guia é controle
aplicado antes da ação, sensor observa o resultado depois dela — e usar essa
distinção para fechar quatro lacunas que hoje existem sem nome: peça de harness
não classificada, orçamento de contexto não medido no agregado, artefato de
contexto envelhecendo em silêncio e sensor não declarado no manifesto do agente.
Mais uma medição: o mesmo harness com modelo diferente.

Origem: vídeo "Harness Engineering: A Nova Corrida do Mercado de IA"
(Attekita Dev, 2026), que cita o modelo de guias e sensores do Martin Fowler.

## Decisões fechadas

- **D1 — A medição de troca de modelo entra neste fluxo, como última tarefa** — porquê: ela só tem sentido depois que a classificação guia/sensor existir, porque é a classificação que define o que a régua mede.
- **D2 — A categoria guia/sensor é metadado estrutural, não documentação** — porquê: tabela solta envelhece em silêncio, que é exatamente o `AGENTS.md` inchado que o vídeo critica. Metadado é o que destrava D3 e D9; sem ele os dois viram intenção.
- **D3 — A exigência de sensor barra no `verificar` e apenas avisa nos demais estágios** — porquê: `verificar` existe para rodar critério contra artefato real, e estágio ali sem nenhum sensor é verificação de fachada. Barrar em `executar` pararia trabalho legítimo no meio.
- **D4 — Os sensores de orçamento e de idade medem sempre, mas só falam na abertura quando estouram** — porquê: falar sempre faria o sensor de orçamento de contexto gastar orçamento de contexto em toda sessão. O que fala na abertura é o teto **do próprio hook** (ver D17); o agregado fica na bateria, porque hook nenhum consegue observá-lo.
- **D5 — A marca de categoria mora no cabeçalho do próprio arquivo; um conferidor varre `hooks/`, `scripts/conferir-*` e `vigias/` e reprova peça sem marca** — porquê: lista central diverge do diretório em silêncio, e este repo já foi mordido por isso (a cópia byte-idêntica em `hooks/lib/estagio-ativo.cjs`, que sobreviveu porque teste nenhum a olhava). Sem lista, não há o que divergir.
- **D6 — Fechar `verificar` com `ok` exige que a evidência cite um sensor; o plano pode declarar sensor externo** — porquê: `skills/plano/SKILL.md:49` manda "provado por <comando exato>", e comando exato é frequentemente ferramenta de fora (`npm test`, compilador, linter). Exigir peça do repo quebraria critério legítimo.
- **D7 — O teto agregado do SessionStart é a soma lida dos tetos já declarados, não um número novo, e é medido em `scripts/orcamento.cjs` na bateria** — porquê: número escolhido a dedo envelhece sozinho, e `scripts/orcamento.cjs:45-53` já lê o teto da lib por regex e nunca literal; somando o declarado, subir um teto por hook atualiza o agregado de graça. Fica na bateria porque nenhum hook enxerga o agregado: cada um emite só o próprio `additionalContext` (`hooks/foco-session-start.cjs:321-326`, `hooks/memoria-session-start.cjs:369-374`), e quem executa os cinco é `scripts/exporta-hooks-sessao-start.cjs`, que é CLI.
- **D8 — A troca de modelo da medição usa o parâmetro `model` do `Agent`, sem editar `agents/*.md`** — porquê: não altera arquivo versionado para produzir um número, e a portaria nunca olha `model` (ela decide `runtime`, `claude`|`codex`), então não há atrito de gate.
- **D9 — O portão de sensor declarado fica na portaria, antes do despacho** — porquê: a portaria já lê o manifesto e já tem esse portão para outra coisa — agente `escreve: false` tem as `tools` do frontmatter conferidas contra allowlist em `hooks/portaria.cjs:963-998`. E barrar antes da ação **é** um guia: pôr isso no `conferir-entrega` classificaria errado a peça que inaugura a classificação.
- **D10 — Três categorias — `guia`, `sensor`, `dado` — classificadas pelo evento em que o código roda, nunca pelo que ele inspeciona** — porquê: com essa regra o híbrido `hooks/gate-verificador-staged.cjs` (roda em `PreToolUse`, inspeciona conteúdo já em disco) é `guia` sem discussão, e ninguém julga caso a caso. Regra que exige julgamento diverge entre duas pessoas.
- **D11 — O sensor de idade cobre só `FOCO.md`, a 7 dias sobre o último avanço datado** — porquê: é o único artefato injetado cuja idade tem significado (`ESTRATEGIA.md` nunca é lido — `hooks/foco-session-start.cjs:171-172` só faz `existsSync` —, então dele só restaria `mtime`, que mede a última gravação e não a última validade). São 7 e não 21 para alinhar com o limiar que já existe para este mesmo arquivo: `içarAvancoRecente` (`hooks/lib/contexto-sessao.cjs:371`) existe para a regra 3 ("foco há 7+ dias sem avanço") e `vigias/sentinela-foco.md` item 3 já o cobra. Dois limiares no mesmo arquivo fariam o sensor novo contradizer o vigia em silêncio.
- **D12 — A medição varia só o modelo do builder; o crítico cego é o mesmo modelo nos dois braços; o resultado é relatório** — porquê: crítico variável faria a medição medir o crítico. E o resultado não muda `agents/*.md`: trocar modelo por causa de uma tarefa só é generalizar de n=1.
- **D13 — Agente sem o campo `sensores` no manifesto passa; nega-se o briefing que exige sensor fora de uma lista declarada** — porquê: ausência tem que significar "esta tarefa não pede sensor", que é o caso da maioria. Fail-closed negaria os doze agentes do padrão no primeiro dia por uma declaração que ninguém escreveu ainda.
- **D14 — A `versao` do manifesto fica em 1** — porquê: campo opcional cujo ausente reproduz o comportamento antigo não quebra leitor nenhum. Subir a versão negaria repo com `.rainforest/agentes.json` próprio, que substitui o padrão por inteiro e não faz merge.
- **D15 — A medição de orçamento não grava histórico** — porquê: a pergunta que o sensor responde é "estourou agora?", e isso se responde medindo agora. Arquivo que só cresce e ninguém abre é a versão em disco do documento inchado.
- **D16 — A classificação das peças existentes entra na mesma entrega que o conferidor** — porquê: a regra de D10 é mecânica e o inventário já está levantado. Entregar o conferidor com lista de pendentes criaria a exceção no mesmo commit que cria a regra.
- **D17 — A medição de orçamento parte em dois: cada hook trava o próprio teto na abertura, o agregado fica no `orcamento.cjs`** — porquê: `hooks/foco-session-start.cjs` já trava o próprio (`travarOrcamento` em `hooks/lib/contexto-sessao.cjs:1030`, que prefixa aviso e corta o fim); `memoria-session-start` ganha o mesmo. A alternativa — hook 1 grava uma célula que hook 2 lê e soma — acoplaria os dois à ordem de declaração em `hooks/hooks.json:8,12`, dependência que teste nenhum da bateria olha. Cada peça mede o que consegue observar.
- **D18 — Cada declaração de sensor usa o canal que o seu leitor tem: linha `Sensor:` no briefing para a portaria, campo `sensor_externo` no `--json` para o `estado.cjs`** — porquê: a versão original desta decisão dizia que **os dois** chegariam por linha no briefing, reaproveitando o parser da linha `Runtime:` (`skills/executar/SKILL.md:71`, lido em `hooks/portaria.cjs:247`). Metade disso é impossível: `scripts/estado.cjs` nunca recebe texto de briefing — ele recebe `--json`. A decisão confundia dois portadores. O sensor que o **agente pode rodar** (D9/D13) é decidido no despacho, onde existe briefing, e continua na linha `Sensor:`. O sensor citado na **evidência** ao fechar `verificar` (D6) é decidido no fechamento, onde só existe `--json`, e vai no campo `sensor_externo`, cujo valor tem de aparecer dentro de `comando`. Corrigido em 2026-09-14, com o fato levantado pelo agente da tarefa 5 durante a execução.
- **D19 — O conferidor de D5 varre só peça de papel; arquivo de teste, lib, log e dado ficam fora, e CLI rodado sob demanda conta como sensor** — porquê: `hooks/` tem mais de quarenta `testa-*` além de `lib/` e `hooks.json`, e `vigias/` tem `.ps1`, `.js`, `.jsonl` e `log-*.txt`. Exigir marca de tudo transformaria a regra em ruído. E D10 classifica pelo evento de execução, mas CLI não tem evento: "sob demanda" é o evento dele, e ele observa resultado — logo, sensor.

## Avaliado e descartado

- **Classificar as peças em documentação solta (tabela no README) ou em JSON central `.rainforest/pecas.json`** — os dois divergem do diretório sem sinal. Evidência no próprio repo: a cópia local byte-idêntica em `hooks/lib/estagio-ativo.cjs` sobreviveu rodadas de revisão porque nenhum teste a olhava, e sabotá-la deixava a bateria verde.
- **Exigir que o comando de evidência do `verificar` seja peça do repo** — `skills/plano/SKILL.md:49` fixa a forma "provado por <comando exato> devolvendo <saída esperada>", e comando exato costuma ser ferramenta externa. A exigência reprovaria critério correto.
- **Teto agregado do SessionStart com número escolhido a dedo** — `scripts/orcamento.cjs:45-53` já lê `ORCAMENTO_BYTES` da lib por regex justamente para o teto não ser copiado; um literal novo reintroduziria a divergência que aquele código evita.
- **Editar `agents/<nome>.md:4` para trocar o modelo na medição** — altera arquivo versionado para produzir um número, e o `Agent` já aceita `model` por despacho.
- **Incluir `ESTRATEGIA.md` no sensor de idade** — `hooks/foco-session-start.cjs:171-172` confere só existência; o conteúdo nunca entra no payload. Sem leitura, a única idade disponível é `mtime`, que dispararia sobre arquivo correto em estar parado.
- **Gravar histórico da medição de orçamento (`.rainforest/orcamento.jsonl` ou dentro de `despachos.jsonl`)** — série temporal que ninguém leria; e `despachos.jsonl` é log de agente, misturar assunto ali quebra quem o lê.
- **Subir a `versao` do manifesto para 2** — `hooks/portaria.cjs:625-638` nega qualquer versão diferente de 1, e o manifesto do repo substitui o padrão inteiro (D3 de 2026-09-13); um repo com manifesto próprio passaria a ser negado por não ter acompanhado o bump.
- **Recusar a abertura da sessão quando o orçamento estoura** — desproporcional: sessão não pode morrer por payload grande. O que faltava em 2026-08-10 não era o corte, era o silêncio sobre ele.
- **Barrar a exigência de sensor em `executar`** — pararia trabalho legítimo no meio; o estágio cuja definição depende de sensor é `verificar`.
- **Somar o orçamento agregado dentro dos hooks, por célula compartilhada** — o primeiro hook gravaria a própria medida e o segundo leria e somaria. Acopla os dois à ordem de declaração em `hooks/hooks.json:8,12`, e essa dependência não é observada por nenhum teste da bateria — a mesma forma de defeito que já escapou duas vezes neste repo.
- **Um canal único de declaração de sensor, a linha `Sensor:` no briefing, para os dois casos** — era a D18 original, e a execução da tarefa 5 a refutou com o fato: `scripts/estado.cjs` não recebe briefing nenhum, só `--json`. Um parser de linha ali não teria texto onde procurar. A economia aparente de "um canal só" custava um canal que não existe.
- **Limiar de 21 dias para o `FOCO.md`** — foi a recomendação inicial, feita antes do levantamento. Ele mostrou que já existe um limiar de 7 sobre o mesmo campo, em `hooks/lib/contexto-sessao.cjs:371` e `vigias/sentinela-foco.md` item 3; manter 21 poria dois números em desacordo sobre o mesmo arquivo, sem nada explicando a diferença.

## Fora de escopo

- **Motor de régua.** `skills/regua/SKILL.md:185-187` declara que a skill não implementa motor nenhum e usa o `/loop` nativo; a medição de D12 segue essa via.
- **Mudar o modelo declarado de qualquer agente em `agents/*.md`.** A medição produz número, não política.
- **Checagem de idade sobre design docs, ideias plantadas e observações de memória.** Design velho é histórico, não dívida.
- **Fazer `scripts/conferir-entrega.cjs` receber o critério da tarefa.** Hoje o critério é prosa no briefing (`skills/executar/SKILL.md:98-100`), e mudar isso é trabalho próprio, não subproduto deste.
- **Medir o teto real de entrega do harness** (o que entregou ~2,2 KB de 32 KB em 2026-08-10). Não é observável de dentro do hook; o que se mede aqui é o que o hook **emite**.

## Em aberto

- Nada.

## Emenda de 2026-09-15 — o portão de sensor vira registro (issue #264)

**Decidido: o portão de sensor na portaria deixa de negar e passa a registrar,
porque a política que ele assumia foi revogada enquanto este fluxo estava aberto.
Continua negando só o que é forma de arquivo.**

Esta emenda reverte a D9 ("o portão de sensor declarado fica na portaria, antes
do despacho") e a D13 ("nega-se o briefing que exige sensor fora de uma lista
declarada") no que elas diziam sobre **negar**. O que elas diziam sobre **onde**
a declaração mora continua valendo: o campo `sensores` segue no manifesto, a
linha `Sensor:` segue no briefing, e a portaria segue sendo quem os lê (D18
intacta).

### O que a mediu

A `dd2e7ccd` ("portaria: deixa de admitir agente e passa a registrar", fecha a
#264) entrou na main em 2026-09-15, depois do `executar` deste fluxo ter fechado
em 14/09. Ela separou dois critérios que a portaria misturava:

- **forma do arquivo → nega.** Manifesto com JSON ilegível, versão desconhecida,
  `agentes` inválido, `escreve`/`runtime` com valor que não dá para interpretar.
  A razão está escrita no próprio código: "tem de doer no arquivo, não três telas
  adiante". O `agentes.extra.json` malformado continua saindo com exit 2.
- **admissão e ordem → registra.** Agente fora do manifesto, despacho fora de
  fluxo. Viraram `declarado: false` e `fora_de_fluxo: true` no `despachos.jsonl`.
  O custo foi medido: o log de 15/09 tinha seis `allow` com
  `via: autorizacao-do-usuario` e nenhum deles decidiu nada.

O portão da D13 é do segundo tipo — ele pergunta "este agente pode receber esta
tarefa?", que é admissão. Mantê-lo faria o plugin negar por uma lista declarada
no mesmo dia em que parou de negar por uma lista declarada.

### O que muda, e o que não muda

| Caso | Antes (D9/D13) | Agora |
|---|---|---|
| `sensores` ausente no manifesto | passa | passa, sem mudança |
| briefing pede sensor DA lista | passa | passa, e o log registra o sensor pedido |
| briefing pede sensor FORA da lista | **nega, exit 2** | **passa, exit 0**, com `sensor_fora_da_lista` no log |
| `sensores` malformado no manifesto | nega, exit 2 | **nega, exit 2** — é forma, não admissão |
| linha `Sensor:` ilegível no briefing | nega, exit 2 | **passa, exit 0**, com `sensor_ilegivel: true` no log |

A peça continua classificada `guia` pela D10, e isso não é contradição: a D10
classifica **pelo evento em que o código roda** (`PreToolUse`), nunca pelo que
ele faz com o que leu. Foi essa regra que existiu justamente para não abrir
julgamento caso a caso.

### O que isto conserta de graça

O núcleo da regra 10, injetado em toda sessão, afirma que **só a regra 11 barra**
(`skills/rainforest-mind/SKILL.md:124`), e a elaboração lista os casos de negação
como "todos forma ou regra 11" (`references/regra-10-portaria.md:68`). Com a D9
valendo, os dois passariam a mentir a partir deste merge — o revisor levantou
isso como achado bloqueante, por leitura independente, em 2026-09-15. Convertido
o portão em registro, os dois voltam a ser verdade sem edição. A única linha que
ainda precisa de emenda é a lista de negações por forma, que ganha `sensores`
malformado ao lado de `escreve` e `runtime`.

### O que não foi feito aqui, e por quê

Não se acrescentou `sensores` a nenhum agente do `.rainforest/agentes.padrao.json`
— seguindo o que a Tarefa 6 já tinha decidido e registrado. Com o portão virando
registro, isso significa que o campo hoje não tem consumidor: nada no manifesto
o declara, então nada aparece no log por causa dele. É o argumento da D15
("arquivo que só cresce e ninguém abre") apontado para dentro, e fica dito em vez
de escondido. O que sustenta a peça mesmo assim é a D18: quando algum agente
precisar declarar sensor, o canal existe, foi testado e não precisa ser desenhado
de novo no meio da urgência.
