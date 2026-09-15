# Modelo do builder na régua — haiku contra sonnet, rodada 1

**Data:** 2026-09-14
**Fluxo:** `2026-09-14-guias-e-sensores`, tarefa 8
**Decisão que este relatório executa:** D12 — varia só o modelo do builder, crítico cego fixo nos dois braços, resultado é relatório e **não** muda `agents/*.md`.

## O que foi medido

Dois builders receberam **briefing idêntico, base idêntica e tarefa idêntica**: escrever `scripts/conferir-orfaos.cjs`, um conferidor que acha arquivo em `scripts/` ou `hooks/` que nada referencia. A única diferença entre os dois despachos foi o parâmetro `model`.

A régua é `scripts/conferir-duplicacao.cjs` — escolhida na Fase 0 por passar nos três testes (nomeada, obtível, comparável). Os sete mecanismos estão em `docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md`, commitados **antes** da primeira rodada e imutáveis a partir dali.

## Como a cegueira foi montada

| Medida | Por quê |
|---|---|
| Arquivos entregues como `par1-artefato-A.cjs` etc., fora do repo | o nome `conferir-duplicacao.cjs` entregaria de cara qual é a régua |
| Posição alternada: régua é **A** no par 1, **B** no par 2 | crítico que sempre escolhe a mesma letra revela viés posicional, não qualidade |
| Mecanismos desidentificados | o arquivo de régua commitado nomeia e cita o artefato dela; a versão do crítico tem os mesmos sete mecanismos com exemplos generalizados |
| Mesmo modelo nos dois críticos, agente novo em cada um, sem memória da conversa | crítico variável faria a medição medir o crítico (D12) |
| Instrução explícita de não julgar se os artefatos funcionam | o crítico julga ofício; correção é medida em separado, abaixo |

**O que não foi possível cegar:** o conteúdo revela que problema cada arquivo resolve, e um crítico atento pode inferir que o conferidor de duplicação é o estabelecido. Isso empurra a favor da régua nos dois braços — o que torna uma vitória nossa mais confiável que uma derrota. As duas derrotas abaixo têm que ser lidas com esse desconto.

## Resultado da rodada 1

| Braço | Artefato | Veredito do crítico cego | Rodadas até vencer |
|---|---|---|---|
| builder `haiku` | 335 linhas | **perdeu** (crítico escolheu A = régua) | não venceu na rodada 1 |
| builder `sonnet` | 387 linhas | **perdeu** (crítico escolheu B = régua) | não venceu na rodada 1 |

**Nenhum dos dois venceu a rodada 1.** A régua ganhou os dois pares.

### O sinal que valida a medição

Os dois críticos escolheram **letras diferentes** — A no par 1, B no par 2 — e nos dois casos a letra era a régua. Se houvesse viés posicional, as escolhas coincidiriam na letra, não no artefato. Não coincidiram.

Mais: os dois convergiram, sem combinar, no **mesmo mecanismo decisivo**. O par 2 é explícito — *"o mecanismo que decide o veredito é o M3"*. O par 1 usa M1 como principal e M3 como segundo. M3 é o exit code carregar significado, com achados de naturezas diferentes saindo com códigos diferentes.

### As lacunas isoladas (uma por braço, como a régua exige)

- **haiku, M1:** o cabeçalho justifica a *categoria* de script com exemplos hipotéticos entre aspas ("por se ver", "pode servir depois"), em vez de registrar o incidente medido que motivou *este* script.
- **sonnet, M3:** todo achado sai com o mesmo exit code 2, sem distinguir o arquivo sem citação nenhuma — a certeza mais forte — do arquivo citado só em `docs/rainforest/estado/*.json`, que o próprio cabeçalho dele reconhece como evidência de outra natureza.

Vale notar o que a lacuna do sonnet diz sobre a régua: `conferir-duplicacao.cjs` venceu porque **já tinha resolvido essa tensão** (certeza vira falha, inventário sai 0, e o cabeçalho explica por quê). Não foi estilo. Foi uma decisão de contrato que os dois builders não tomaram.

## Segundo eixo: correção — medido à parte, e mais duro

O crítico cego foi instruído a julgar ofício, não funcionamento. Correção foi medida aqui, contra o repositório real:

| Braço | Órfãos apontados | Falsos positivos |
|---|---|---|
| `haiku` | 5 | **3** |
| `sonnet` | 2 | 0 |

Os três falsos positivos do haiku são `hooks/testa-fuga-de-escotilha.sh`, `scripts/testa-arqueologo-ponta-a-ponta.sh` e `scripts/testa-enxugar-estrutura.sh`. Não são órfãos, e a prova é uma linha — `.github/workflows/baterias.yml:163`:

```
baterias=$(ls scripts/testa-*.sh hooks/testa-*.sh 2>/dev/null)
```

O CI descobre bateria **por glob, nunca por nome**. Todo `testa-*.sh` roda a cada push, cite-o alguém ou não. Chamar um deles de órfão é o tipo de achado que faz alguém apagar um teste vivo.

O braço sonnet não caiu nisso, e o relatório dele diz por quê: ele foi ler o `baterias.yml` e desenhou a regra de bateria na direção inversa — não "quem cita a bateria", mas "o que a bateria cita". Também registrou ter corrigido, antes de commitar, uma versão anterior em que palavra comum em português ("estado", "config") salvava bateria fantasma por coincidência léxica.

## O que este relatório afirma, e o que não afirma

**Afirma:** numa tarefa, com um briefing, num par de artefatos, o builder `sonnet` produziu um conferidor sem falsos positivos e o `haiku` produziu um com três. Os dois perderam para a régua no julgamento de ofício, pela mesma razão estrutural.

**Não afirma** que `sonnet` é melhor que `haiku` como builder em geral. É **n=1**. Uma tarefa não generaliza para as outras, e a D12 fecha esse caminho de propósito: o resultado não muda o `model:` de nenhum agente em `agents/*.md`. Trocar modelo por causa de uma medição de uma tarefa só é generalizar de uma amostra.

**O que a medição sustenta como ponta solta:** se este tipo de tarefa — escrever peça nova de CLI com padrão de qualidade estabelecido — for despachado com frequência, vale repetir a medição com outras tarefas antes de tirar conclusão. Uma amostra é evidência de que a diferença existe naquela tarefa; não de quanto ela vale.

## Rastro

- Régua: `docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md`
- Artefato da régua: `scripts/conferir-duplicacao.cjs`, na base `ae681310`
- Base dos dois builders: `ae681310886baf3ddaee27707651c2f2419771b7` (anterior ao commit da régua, para o arquivo de mecanismos não existir no worktree deles)
- Braço haiku: `worktree-agent-a7932c94bf8acb337`, commit `f2752c86`
- Braço sonnet: `worktree-agent-ad858a787a754c2c7`, commit `df07247e`

Nenhum dos dois artefatos foi integrado à branch — eles existem como medição, não como entrega.
