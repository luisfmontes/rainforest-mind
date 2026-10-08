# Fluxo pulado: bloquear com caminho leve declarado (#430)

## Objetivo
Trocar o aviso do `hooks/aviso-fluxo.cjs` por bloqueio (exit 2) quando o repositório tem fluxo e nenhum está aberto, estender o bloqueio ao despacho de agente que edita, e manter o hotfix mecânico possível por um caminho **declarado**: `estado.cjs leve --motivo "<por quê>"`. Pular deixa de acontecer por inércia e vira uma ação com o motivo escrito.

## Decisões fechadas
- **D1 — Vale nos dois trilhos, rainforest e protheus** — porquê: seis das onze ocorrências da #396 foram em repositório com fluxo de outro plugin; deixar protheus no aviso mantém metade do defeito.
- **D2 — Modelo de ameaça: protege contra o modelo pular o fluxo por inércia, na sessão principal (Edit/Write/MultiEdit de arquivo com extensão de código; `.ipynb` não está na lista de extensões de código, por isso o NotebookEdit fica fora) e no despacho de agente que edita.** Fica fora, por decisão: (a) `leve` declarado com motivo ruim — não se barra, fica no rastro para auditoria; (b) escrita por Bash (`sed`, `node -e`, redirecionamento) — detectar escrita em comando livre não é confiável, mesma escolha da D16 do painel; é buraco conhecido, não descoberta de revisão. Revisor que achar vetor dentro de (a) ou (b) não reprova por isso. — porquê: sem fronteira escrita a auditoria de gate não converge.
- **D3 — O despacho de agente que edita também é barrado, revertendo em parte a #267** — porquê: subagente está isento do gate de Edit (critério 1 do `aviso-fluxo`), então sem isto o caso `fluxo-recomendado-e-pulado` (executor despachado sem perguntar) passa intacto. A portaria segue só registrando todo o resto.
- **D4 — Liga por padrão na publicação; a chave `aviso-fluxo` do config desliga tudo (Edit e despacho), por projeto** — porquê: o defeito é inércia; trava opt-in ficaria desligada pelo mesmo motivo.
- **D5 — "Agente que edita" = `escreve: true` no manifesto de agentes; passa quando o estágio aberto do fluxo está nos `estagios` dele, ou quando a branch tem `leve`** — porquê: o manifesto já declara as duas coisas; `arqueologo` (design) despacha no brainstorm, `executor` com fluxo em `plano` é recusado. O manifesto deixa de ser só declaração neste ponto. Agente fora do manifesto (outro plugin) não é barrado por este gate.
- **D6 — Onde o `leve` mora: no trilho rainforest, no arquivo de estado versionado da branch (`docs/rainforest/estado/<data>-<branch>.json`, com motivo e data); no trilho protheus, em arquivo local sob o `.git` do repositório** — porquê: no rainforest o rastro aparece no PR e na auditoria; no protheus não se escreve na pasta de outro plugin.
- **D7 — Alcance do `leve`: a branch inteira, o mesmo recorte do `resolver` de fluxo aberto. Na branch padrão de repo rainforest o `leve` é recusado (regra 11 manda worktree); no protheus é aceito em qualquer branch** — porquê: um recorte só para "aberto" e "leve" evita duas noções de escopo.
- **D8 — O bloqueio repete a cada edição de código até existir fluxo aberto ou `leve`** — porquê: bloqueio que vale só na primeira vira o aviso de antes na segunda tentativa. A memória por sessão do `aviso-fluxo` deixa de decidir se bloqueia.
- **D9 — A mensagem de bloqueio nomeia as duas saídas com comando pronto: abrir o fluxo (`iniciar` / `/brainstorm`, ou `/protheus:trabalhar`) e `estado.cjs leve --motivo`, com o caminho absoluto do script do plugin** — porquê: critério da #430; recusa que não diz a saída empurra para desligar a trava.

## Avaliado e descartado
- **Manter o aviso (#396, "aviso, não bloqueio")** — medido: onze observações em dois meses mesmo com texto e memória; e em 2026-10-07 esta própria sessão recebeu o aviso no primeiro Edit e corrigiu #423, #421 e #429 sem abrir fluxo nem perguntar.
- **Bloquear só a primeira edição da sessão** — descartado na D8: a segunda tentativa passaria.
- **Gate de despacho só com fluxo em brainstorm/plano (item 3 literal da issue)** — descartado na D3/D5: despacho de executor sem fluxo nenhum, o caso mais comum, ficaria livre.

## Fora de escopo
- Detectar escrita por Bash (D2b).
- Julgar a qualidade do motivo do `leve` (D2a).
- Barrar agente de outro plugin que não está no manifesto.
- Mudar o fluxo protheus em si (`/protheus:trabalhar`, `.gates.json`): só se lê o que ele já grava.

## Varredura
docs/rainforest/varredura/2026-10-08-fluxo-pulado-bloqueio.txt — achou a #396 (origem do aviso e da escolha "não bloqueio", citando #186 para o hotfix mecânico) e a #264/#267 (portaria passou de admitir a só registrar). Mudou o design: a D3 reverte a #267 explicitamente e de forma estreita (só `escreve: true`), e a D5 reusa o manifesto em vez de criar lista nova. Nenhuma ideia no `ideias.jsonl` casou.

## Em aberto
