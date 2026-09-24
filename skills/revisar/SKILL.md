---
name: revisar
description: Revisão independente de uma entrega do fluxo, contra o diff real — nunca pelo relato de quem implementou. Use depois que `executar` fechou `ok`, antes de `verificar`.
---

# Revisar

Abre com:

```
node scripts/estado.cjs exigir --slug <slug> --estagio revisar
```

Recusa (exit 2) se `executar` estiver `parcial` — não existe revisão de
entrega incompleta; é o próprio estado que barra, não julgamento seu.

## Contexto zerado, nunca `fork`

Revisor nasce sem a conversa que produziu a entrega — `Agent` novo, nunca
`fork` do agente que despachou. Quem herda a narrativa de quem escreveu
valida a narrativa, não o código: some a chance de o revisor notar algo
que quem implementou já decidiu que estava certo. Use
`rainforest-mind:revisor` (`agents/revisor.md` — leia antes de citar; é
sonnet com o método de review embutido).

## O relato de quem implementou não é fonte

O briefing do revisor traz caminho, diff e critério de sucesso original —
nunca o resumo de "o que foi feito". Justificativa de desenho do
implementador ("deixei assim por YAGNI", "não fiz X porque Y") é ele
dando nota a si mesmo e **nunca reduz a severidade de um achado**: se o
código faz a coisa errada, a explicação de por que faz não conserta.

## Escopo fixado por diff

```
git diff <base>...<head>
```

Três pontos, sempre — mostra só o que a branch trouxe desde que divergiu
da base. `git diff base..head` ou `HEAD~1` pegam o commit errado e cortam
task com vários commits, ou trazem mudança alheia que chegou em paralelo
na base. Sem diff (branch igual à base, ou `head` inexistente), **não há
revisão**: pare e reporte em vez de revisar de memória da conversa.

## Achado exige cenário

Achado só sobrevive com `arquivo:linha` e o cenário concreto de falha —
entrada ou estado que produz resultado errado. "Eu faria diferente" ou
"não é assim que eu escreveria" não é achado, é estilo, e só entra se
violar padrão documentado do repo.

## Revisor não muta — encaminha a mutação

Validar por mutação (reverter o comportamento e ver o teste falhar) é
técnica boa e é **ofício do `tester`**, que roda com `isolation: "worktree"`
justamente para isso. O revisor não tem worktree por desenho — `revisar` é
leitura — e por isso **não edita fonte em lugar nenhum**, muito menos no
diretório principal do usuário.

Quando o achado só fecha com mutação, ele sai como achado **com a mutação
descrita** (que linha inverter, que teste deveria quebrar) e quem despacha
manda um `tester` isolado executá-la. **Exit 69 do `conferir-mutacao.cjs`
que o tester roda é bloqueio de ambiente, não veredito** (regra 14): nem
aprova, nem reprova, nem vira achado — anuncie em uma linha e não
redespache. Não é burocracia: em 2026-08-13 um
revisor mutou `gerar_updater_projeto.py` direto no diretório principal, o
`gate-worktree.cjs` bloqueou o `git checkout --` do próprio revert — corretamente,
pela letra da trava — e ele desfez reescrevendo o arquivo por fora do git,
o que funcionou e não deixou rastro auditável (Issue #4). A trava não estava
errada; o caminho é que não existia.

## Molde do briefing do revisor

Linha isolada `Slug: <slug>` no cabeçalho do briefing despachado, ao lado de
`Runtime:`/`Sensor:` — mesma convenção de `skills/executar/SKILL.md:71-79`
(o parser aceita a linha em qualquer ponto do prompt, não só a primeira —
`scripts/lib/primeiro-prompt-jsonl.cjs:65-73` —, mas `Runtime:` já ocupa a
primeira linha quando presente, então `Slug:` vem logo depois dela). É dali
que o hook `SubagentStop` (`hooks/veredito-revisor.cjs`) lê o slug para
gravar o veredito (D5); revisão avulsa, sem `Slug:`, não grava nada nem
trava — continua funcionando como hoje.

Briefing que pede mutação de fonte é recusado na PRIMEIRA linha do relato,
antes de qualquer leitura. Quando o achado só fecha com mutação — reverter
o código e ver o teste falhar — descreva-a sem mutar:

- **Arquivo e linha**: qual fonte, que linha;
- **O que inverter**: comportamento oposto;
- **Teste que deveria quebrar**: qual teste rodaria vermelho com a mudança.

Quem a executa é um `tester` isolado em worktree.

### Backstop de mutação (Issue #4)

`exigir --estagio revisar` **captura um instantâneo**:
o `HEAD` do repositório e a lista de caminhos sujos (`git status --porcelain`).
Depois, `marcar --estagio revisar --status ok` **compara** esse instantâneo e
recusa (exit 2) se:

1. **HEAD mexeu** — qualquer movimento reprova. Se o HEAD andou, a base do diff
   que você revisou mudou, e a revisão foi feita contra outra árvore. A mensagem
   distingue "você commitou" de "outra janela commitou" e diz o que fazer: re-rode
   `exigir revisar` e revise novamente.

2. **Caminho sujo NOVO** — arquivo que não estava no instantâneo mas aparece agora.
   A comparação usa **conjuntos, não contagem**: sujeira pré-existente é legítima
   (outro trabalho em andamento no mesmo clone) e não reprova. Só caminho novo
   recusa.

   Uma exceção, e ela é o próprio mecanismo: `docs/rainforest/estado/<slug>.json`
   sai da comparação. É o `exigir` que o suja, ao gravar ali o instantâneo que
   acabou de tirar — e o arquivo é versionado neste repo. Sem a exceção a trava
   recusa o caminho feliz **sempre**, porque acusa de mutação a escrita que ela
   mesma fez. A bookkeeping da trava não pode ser evidência contra o revisor.

Se o instantâneo não existir (slug que fechou `revisar` sem passar pelo novo
`exigir`), **avise e não trave** — travar retroativo quebra trabalho em andamento.
O instantâneo fica gravado no arquivo de estado (`docs/rainforest/estado/<slug>.json`)
e sobrevive entre sessões.

## Creep: medido contra o plano, não contra o gosto

**Creep é código sem tarefa correspondente no plano.** Arquivo que você tocou mas que não se encaixa em nenhum glob de `arquivos:` de tarefa nenhuma é achado e reprova a revisão.

Isto é **distinto** de "eu faria diferente":

- **Estilo** ("não é assim que eu escreveria", "deixaria mais limpo"): só entra se violar padrão documentado do repo. Senão, é gosto, não achado.
- **Creep** ("esse arquivo não era pra ser tocado", "essa mudança não estava no plano"): arquivo no diff que não casa com nenhum `arquivos:` da tarefa. Sempre reprova.

### Saída única: emendar o plano

Encontrou creep? A única forma de destravá-lo é emendar o plano: a tarefa que faltava entra no plano com critério falsificável. **Justificar em prosa não destrava** — "era uma limpeza necessária", "o compilador pediu" são narrativas, não ações que o plano registra.

A emenda deixa rastro conscientemente registrado de que o escopo cresceu — é isso que distingue creep legítimo (genuinamente necessário) de mudança de escopo silenciosa.

### Isenções: quando um arquivo não precisa de tarefa

Alguns arquivos escapam do creep sem estar em `arquivos:` de tarefa nenhuma, porque
não pertencem a esta tarefa — pertencem a OUTRA regra documentada do repo. A
pergunta-teste, antes de olhar qualquer lista: **o arquivo existe porque outra
regra documentada do repo obrigou a criá-lo?** Se sim, isenção; se a resposta é
"achei que fazia sentido" ou "aproveitei e ajustei", é creep.

Classes que o `conferir-fluxo.cjs creep` reconhece (`globs_isentos`):

- `docs/rainforest/design/<slug>.md`, `docs/rainforest/planos/<slug>.md`,
  `docs/rainforest/estado/<slug>.json`, `docs/rainforest/portoes/*<slug>.md` —
  o próprio rastro que o fluxo escreve para ESTE trabalho.
- `relatorios/` — registro escrito depois que o fluxo já fechou; não pode ter
  tarefa que o cubra, porque nasce depois do plano.
- `docs/rainforest/reguas/` — a skill `regua` exige commitar a régua antes da
  1ª rodada.
- `skills/<s>/references/`, **só quando `skills/<s>/SKILL.md` está em
  `arquivos:` de alguma tarefa do plano** — documentação auxiliar da skill que
  a tarefa já está autorizada a tocar. Sem essa declaração, `references/` da
  mesma skill continua creep normalmente: a isenção é condicional ao
  `SKILL.md` estar no escopo, nunca um glob largo por nome de skill.

Foi a divergência real da Issue #279: dois revisores, o mesmo diff, veredito
oposto sobre `docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md` e
`skills/executar/references/runtime-do-agente.md` — um leu por olho, o outro
pelo `creep` sem estas duas classes. Achar uma classe nova de isenção fora
desta lista não é decisão de revisor: emenda a esta seção primeiro.

## Registre agentes em voo

Quando o revisor despacha agente em background, atualize o estado antes:

```
node scripts/estado.cjs marcar --slug <slug> --estagio revisar --status parcial \
    --json '{"em_voo":[{"agente":"<nome>","tarefa":"<descricao>","desde":"<data-iso>"}]}'
```

Ao receber o resultado (ou registrar que o agente morreu), dê baixa:

```
node scripts/estado.cjs marcar --slug <slug> --estagio revisar --status <ok|reprovado> --json '{...}'
```

Sem `--json` com `em_voo`, o campo desaparece automaticamente no fechamento
(é `CAMPOS_EFEMEROS`). Em sessão não interativa, o turno pode acabar com agente
em voo — o gate `Stop` bloqueia até que você registre.

## Veredito binário

```
node scripts/estado.cjs marcar --slug <slug> --estagio revisar --status ok --json '{"achados":0}'
```

ou

```
node scripts/estado.cjs marcar --slug <slug> --estagio revisar --status reprovado --json '{"achados":N}'
```

Não existe meio-termo: `reprovado` **não libera** `verificar` — `exigir`
do próximo estágio recusa enquanto `revisar` não fechar `ok` — e devolve o
trabalho para `executar`, com os achados numerados como a lista de
pendências da próxima rodada.

**Condição de parada**: sem diff, não há review. Reportar isso — branch
sem commit novo, `head` que não existe, worktree que não foi integrado —
vale mais que produzir um veredito sobre o que a memória da conversa
lembra ter sido feito.

### Contrato de uma linha: `VEREDITO: ok` / `VEREDITO: reprovado`

O relato do revisor (`agents/revisor.md`, seção (f)) termina, sempre, com uma
última linha exata — sem negrito, sem markdown, sem texto depois: `VEREDITO:
ok` ou `VEREDITO: reprovado`. Um hook `SubagentStop`
(`hooks/veredito-revisor.cjs`) lê essa linha direto de
`last_assistant_message` contra vocabulário fechado
(`hooks/veredito-revisor.cjs:44`) e grava em `revisar.vereditos` via `node
scripts/estado.cjs veredito` — sem passar pelo relato de quem despachou
(D1-D3). Fora do vocabulário (prosa, `**APROVADO**` em negrito, sem a linha)
grava `invalido`: a revisão existe e fica auditável, mas não conta como `ok`
nem como `reprovado` nos gates abaixo.

**Transição**: fluxo cujo `exigir revisar` rodou antes deste contrato existir
não tem `revisar.vereditos` armado — `marcar` então só **avisa** em stderr e
segue fechando como hoje (`scripts/estado.cjs:446-451` para `ok`,
`scripts/estado.cjs:472-477` para `reprovado`); a exigência vale só para
janela armada por um `exigir` novo.

**Desligar** (D11): `contrato-veredito` é obedecido em duas camadas — `node
scripts/setup.cjs --desligar contrato-veredito` desarma as duas. O hook
para de gravar; as travas de `marcar revisar` (`contratoVereditoLigado()`)
param de exigir a janela, avisando em stderr. Sem a segunda camada,
`revisar` ficava infechável: `exigir --estagio revisar` continua armando a
janela vazia com o toggle desligado, e o hook nunca a preenche.

**`--transcrito` é a prova** (D12): `veredito` recusa (exit 2, nada
gravado) sem `--transcrito <caminho>` que confirme, NO ARQUIVO
(`transcritoConfirmaVeredito`): dentro de `subagents/`, primeiro prompt com
`Slug: <slug>` do fluxo, última mensagem do assistente batendo com o
`--veredito` (`invalido` fora do vocabulário). Gravar `ok` à mão volta a
exigir fabricar um transcrito dentro de `subagents/`, auditável.

**Risco residual aceito** (D13): nada amarra o `Slug:` do briefing ao diff
revisado — `Slug:` errado grava no fluxo errado. D12 exige o slug real do
transcrito, mas não o confere contra o `Head:`; conferir o `Slug:` certo é
responsabilidade de quem despacha.

### Teto de 3 reprovações e a 4ª rodada

`revisar` herda o teto genérico de tentativas (`TETO_TENTATIVAS = 3`,
`scripts/estado.cjs`): na 3ª reprovação seguida, `exigir --estagio executar`
(o estágio reaberto pela reprovação) recusa reentrar sem destrave. A 4ª
rodada não é automática — é decisão do usuário, com rastro escrito:

```
node scripts/estado.cjs liberar --slug <slug> --estagio revisar --rodada-extra "<o que o usuário decidiu>"
```

exige, antes de destravar (`scripts/estado.cjs:1738-1762`):

1. `--rodada-extra "<texto>"` com o que o usuário decidiu;
2. o impasse escrito em `docs/rainforest/portoes/<slug>-impasse.md`
   (`scripts/estado.cjs:1747`, isento de creep —
   `scripts/conferir-fluxo.cjs:530`) — sem o arquivo, recusa (exit 2) nomeando
   o caminho esperado.

Não é `exigir revisar --rodada-extra`: quem primeiro bate no teto é `exigir
--estagio executar`, não `exigir --estagio revisar` — um flag pendurado ali
não destravaria o estágio que realmente recusa.

### Trava de cobertura de creep e mutação

`node scripts/estado.cjs marcar --estagio revisar --status ok` recusa se o `--json` não incluir `base` e `head` — são os dois pontos que definem o diff e permitem provar ausência de creep — e recusa também se o repositório foi mutado desde `exigir --estagio revisar`: HEAD diferente ou arquivo novo sujo (ver seção anterior). Sem `base`/`head`, fechar a revisão sem poder provar que o diff não toca arquivo fora do plano é o buraco que a trava fecha.

**`reprovado` não exige `base`/`head` nem a comparação de instantâneo**
(HEAD/caminhos sujos), e é deliberado: reprovar já devolve o trabalho para o
`executar`, então não há veredito de ausência de creep para provar — a
comparação de instantâneo só roda quando `status` fecha `ok`
(`scripts/estado.cjs:1892-1896`, gatilho `FECHADO['revisar'] || 'ok'`,
`scripts/estado.cjs:132`). A trava existe para impedir que se declare "sem
creep" ou "sem mutação" sem poder comprová-lo — não para burocratizar a
recusa.

O que `reprovado` PASSA a exigir (D9): pelo menos um veredito `reprovado`
gravado na janela `revisar.vereditos` — sem isso, `marcar --estagio revisar
--status reprovado` recusa (exit 2) citando "nenhum veredito 'reprovado'
gravado" (`scripts/estado.cjs:470-480`). Simetria com D3: quem despacha não
reabre o `executar` sem um revisor ter de fato dito `VEREDITO: reprovado`.

## Segunda opinião (opcional)

Depois que o revisor Claude fecha `ok`, a entrega pode ser submetida a um
segundo auditor de **família de modelo diferente** (Codex ou Gemini). A
segunda opinião é um passo **opcional** — liga-se por `--modelo codex` ou
`--modelo gemini` em `node scripts/segunda-opiniao.cjs`.

Quando ligada, consome:

- `git diff <base>...<head>` (três pontos, o mesmo escopo que `revisar` já fixa
  acima)
- O critério falsificável do briefing (arquivo de texto)
- O commit-base (SHA fornecido)

E devolve:

- Veredito de **uma linha** no stdout, vocabulário fechado: `concordo` ou
  `discordo`
- Parecer completo (justificativa) no stderr

**Arbitra sempre a janela.** O modelo externo aconselha, nunca manda. Se
discordar e a janela rejeitar o parecer, a divergência vai ao log
(`scripts/segunda-opiniao.cjs registrar-divergencia ...`) com motivo nomeado —
não desaparece, mas também não trava a entrega.

**Indisponibilidade reprova.** Se o modelo está ligado mas não responde (exit
≠ 0, stdout vazio, ou timeout), o `segunda-opiniao.cjs` sai com erro — nunca segue
em silêncio. Use `TIMEOUT_SEGUNDA_OPINIAO_MS` para calibrar timeout (default
300000 ms = 5 min).

Quando a segunda opinião concorda, a entrega prossegue com endorsement de
ambos os auditores. Quando discorda e é aceita, o motivo fica registrado e
visível para que revisões futuras de contexto relacionado saibam por quê a
aprovação do externo foi descartada.
