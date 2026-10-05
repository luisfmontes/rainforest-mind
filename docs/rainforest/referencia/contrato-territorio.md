# Contrato do território (`versao_contrato: 0`)

Referência de como o rainforest lê o mapa de estágios que um plugin de território declara.
Descreve o que o código faz hoje (`scripts/territorio.cjs` e o trecho do território em
`scripts/estado.cjs`), não o que o design sugere. Design de origem:
`docs/rainforest/design/2026-10-05-mapa-de-estagios-do-territorio.md`.

Um **território** é um plugin de domínio (uma linguagem, uma plataforma) que diz, por estágio do
fluxo, quais agentes despachar, quais tools de MCP e skills consultar e quais comandos rodar. O
rainforest guarda só o contrato genérico; o mapa de cada território mora no plugin dele.

## Versão e promoção

- Este contrato é `versao_contrato: 0`: **experimental**. Um manifesto com qualquer outro valor
  (inclusive a chave ausente) torna o plugin inválido: `territorio.cjs` sai 2 se ele for o
  território do repositório; senão o ignora com aviso.
- Ele é exercitado por um território sintético nos testes
  (`test/fixtures/territorio/sintetico/territorio.json`, reproduzido abaixo) e validado por um
  território real.
- **Vira `v1` quando um segundo território real o implementar** (D10). Até lá, campo novo ou
  mudança de significado pode acontecer sem aviso de compatibilidade.

## Onde o manifesto mora

Arquivo `territorio.json` na **raiz do plugin de território**. Não existe manifesto dentro do
repositório de trabalho: o repositório só pode ter o apontamento `.rainforest/territorio` (abaixo).

## Exemplo completo

Território sintético dos testes, o único exemplo deste repositório:

```json
{
  "versao_contrato": 0,
  "nome": "sintetico",
  "deteccao": { "extensoes": [".abc"], "arquivos": [] },
  "variaveis": ["lint"],
  "estagios": {
    "brainstorm": {
      "mcp": [
        { "tool": "mcp__srv__consulta" },
        { "tool": "mcp__srv__dicionario", "quem": "agente", "obrigatorio": true }
      ],
      "skills": ["sintetico:conhecimento"]
    },
    "executar": {
      "modo": "substitui",
      "agentes": [{ "tipo": "sintetico:executor", "mcp": "agente", "obrigatorio": true }]
    },
    "revisar": {
      "modo": "soma",
      "agentes": [{ "tipo": "sintetico:revisor" }]
    },
    "verificar": {
      "comandos": [{ "id": "lint", "comando": "{lint} {arquivo}", "obrigatorio": true }]
    }
  }
}
```

## Campos do manifesto

`<estagio>` é um de `brainstorm`, `executar`, `revisar`, `verificar`. Estágio sem bloco no
manifesto imprime `estagio sem declaracao`. Campo omitido tem o padrão da coluna da direita;
`obrigatorio` só vale com o valor exato `true` (qualquer outra coisa conta como `false`).

| Campo | Significado | Se omitido |
|---|---|---|
| `versao_contrato` | Número do contrato. Tem de ser `0`. | Exit 2. |
| `nome` | Nome do território. Casa com o apontamento `.rainforest/territorio` e nomeia o config local. | O apontamento nunca o acha e o config local vira `undefined.json`. Sempre declare. |
| `deteccao.extensoes[]` | Extensões (com ponto, ex. `.abc`) que fazem o território casar com o repositório, sem diferenciar maiúscula. | Lista vazia: não casa por extensão. |
| `deteccao.arquivos[]` | Caminhos relativos à raiz do repositório; basta um existir. Opcional, ausente do exemplo (a lista do exemplo está vazia). | Lista vazia: não casa por arquivo. |
| `variaveis[]` | Nomes das variáveis que o território espera no config local. Documentação: o script não lê este campo; as variáveis exigidas são as que aparecem como `{nome}` em algum comando. | Sem efeito. |
| `estagios.<estagio>.modo` | `substitui` (o agente declarado toma o lugar do papel do rainforest) ou `soma` (roda junto). O script só imprime `modo: <valor>`; quem age é a skill do estágio. | Nenhuma linha `modo:` é impressa. |
| `estagios.<estagio>.agentes[].tipo` | Agente no formato `<plugin>:<agente>`. | O script quebra; sempre declare. |
| `estagios.<estagio>.agentes[].obrigatorio` | Agente obrigatório indisponível (plugin ausente ou desabilitado) faz o script sair 2. | `false`: indisponível vira uma linha `aviso:` e exit 0. |
| `estagios.<estagio>.agentes[].mcp` | Quem consulta o MCP para esse agente: `orquestrador` ou `agente`. | `orquestrador`. |
| `estagios.<estagio>.mcp[].tool` | Nome completo da tool de MCP (`mcp__<servidor>__<tool>`). | Sempre declare. |
| `estagios.<estagio>.mcp[].quem` | Quem consulta: `orquestrador` ou `agente`. Com `agente`, o item não entra na evidência do estágio: quem consulta é o agente, e o `marcar` não a cobra do orquestrador, mesmo com `obrigatorio` (D8). | `orquestrador`. |
| `estagios.<estagio>.mcp[].obrigatorio` | Item obrigatório precisa de evidência no `marcar` (abaixo). | `false`. |
| `estagios.<estagio>.skills[]` | Skills no formato `<plugin>:<skill>` que o estágio deve consultar. Skill nunca é obrigatória nem exigida no `marcar`. | Lista vazia. |
| `estagios.<estagio>.comandos[].id` | Identificador do comando; é a chave da evidência no `marcar`. | Sempre declare. |
| `estagios.<estagio>.comandos[].comando` | Linha de comando com variáveis `{nome}`. `{arquivo}` vem de `--arquivo`; as demais, do config local. | O script quebra; sempre declare. |
| `estagios.<estagio>.comandos[].obrigatorio` | Comando obrigatório precisa de evidência (comando, saída e exit) no `marcar`. | `false`. |

## Descoberta do território

`node scripts/territorio.cjs estagio <estagio> [--raiz <repo>]` (raiz padrão: diretório atual):

1. **Candidatos.** Lê `plugins/installed_plugins.json` do config dir da sessão
   (`CLAUDE_CONFIG_DIR`, senão `~/.claude`) e, de cada plugin instalado, o `territorio.json` da
   raiz de instalação. Um plugin com chave `false` em `enabledPlugins` do `settings.json` do mesmo
   config dir fica de fora (chave ausente = habilitado). Registro ilegível ou ausente = nenhum
   candidato.
2. **Contrato.** A descoberta nunca falha. Manifesto ilegível, que não é objeto (`null`, lista,
   número) ou com `versao_contrato` diferente de 0 marca o candidato como **inválido**, com o
   motivo. Na escolha (abaixo), inválido que **não** casa com o repositório é ignorado com a linha
   `aviso: plugin <plugin> ignorado: <motivo>` no stderr (também com `--json`) e o script segue;
   inválido que **casa** (apontamento com o `nome` dele, ou detecção casando quando o manifesto é
   objeto com `deteccao`) sai 2 nomeando o plugin.
3. **Escolha.** Se o repositório tem `.rainforest/territorio` (primeira linha = `nome`), esse
   apontamento **vence** a detecção: escolhe o candidato de mesmo `nome`; nome sem candidato sai 2
   nomeando o `nome`. Sem apontamento, vale o primeiro candidato cuja detecção casa: alguma
   extensão de `deteccao.extensoes` em algum arquivo até 5 níveis abaixo da raiz (ignora `.git` e
   `node_modules`), ou algum caminho de `deteccao.arquivos` existente.
4. **Sem território**, o script imprime `sem territorio` e sai 0; as skills seguem como sempre.

Saída com território: `territorio: <nome>`, depois, na ordem, `modo: ...`, uma linha por agente
(`agente: <tipo> obrigatorio=<bool> mcp=<quem>`), por tool (`mcp: <tool> quem=<quem>
obrigatorio=<bool>`), por skill (`skill: <id>`) e por comando (`comando: <id> <comando resolvido>
obrigatorio=<bool>`). Agente ou skill indisponível (plugin ausente ou desabilitado) vira a linha
`aviso: agente <tipo> indisponivel, papel padrao do rainforest` (ou `aviso: skill <nome>
indisponivel, papel padrao do rainforest`), nomeando o item, exceto agente obrigatório, que sai 2.

## Variáveis e config local

- `{arquivo}` é substituída pelo valor de `--arquivo <caminho>`; sem a opção, o texto `{arquivo}`
  fica como está.
- Qualquer outra `{nome}` usada em um comando do estágio vem do config local
  `~/.rainforest/territorios/<nome do território>.json`, um objeto `{ "<variavel>": "<valor>" }`
  com valores em texto. Esse arquivo é por máquina e fica fora de qualquer repositório; o manifesto
  nunca carrega caminho de máquina.
- Variável usada sem valor (arquivo ausente, chave ausente, valor não textual, vazio ou só
  espaços) sai **3**, com a
  mensagem `variavel sem valor em <arquivo>: <variaveis>` no stderr. Config local ilegível sai 2.

## Saídas do `territorio.cjs`

| Exit | Quando |
|---|---|
| 0 | Bloco impresso, ou `sem territorio`. |
| 1 | Uso errado (subcomando diferente de `estagio`, ou estágio faltando). |
| 2 | Contrato violado pelo território que casa com o repositório (manifesto ilegível ou `versao_contrato` diferente de 0; plugin inválido que não casa só gera aviso), apontamento para território inexistente, config local ilegível, agente obrigatório indisponível. |
| 3 | Variável de comando sem valor no config local. |

Com `--json`, o script imprime uma linha
`{"territorio":"<nome>"|null,"itens":[{"classe","id","obrigatorio","disponivel"}]}` com `classe`
em `agente` (id = `tipo`), `mcp` (id = `tool`), `skill` (id = o texto da skill, sempre
`obrigatorio: false`) e `comando` (id = `id`). Não resolve variáveis nem falha por item
indisponível ou variável faltando; só valem os exits 1 e 2 da descoberta. Sem território,
`territorio` é `null` e `itens` é vazio. É a interface que o `estado.cjs` lê.

## Evidência no `marcar` (D9)

Ao fechar um estágio com `node scripts/estado.cjs marcar`, o `estado.cjs` consulta o mapa do
estágio correspondente (`design` lê `brainstorm`; `executar`, `revisar` e `verificar` leem o
próprio nome) e confere o campo `territorio` do `--json` do `marcar`:

```json
"territorio": {
  "agentes":  [{ "tipo": "<plugin>:<agente>" }],
  "mcp":      [{ "tool": "<tool>" }],
  "comandos": [{ "id": "<id>", "comando": "<comando>", "saida": "<saida>", "exit": 0 }]
}
```

- Item **obrigatório** (agente, mcp ou comando) sem evidência: **recusa com exit 2** e a mensagem
  `RECUSADO: item obrigatorio do territorio sem evidencia: <ids>`. Evidência de agente é o `tipo`,
  de mcp é a `tool`; de comando exige `id`, `comando` e `saida` não vazios e `exit` numérico.
- Item opcional sem evidência: só uma linha `aviso:` no stderr, exit 0.
- Skills do território não entram na exigência.
- `territorio.cjs` saindo 2 (contrato violado) recusa o `marcar` com `RECUSADO: territorio invalido`.
- O campo `territorio` fica gravado no JSON de estado do estágio, como qualquer outro campo do
  `--json`.
- Sem território no repositório, ou sem o `territorio.cjs` ao lado do `estado.cjs`, o `marcar`
  se comporta como antes.

## Aceite

O contrato só se considera aceito por comportamento, não por suíte verde: o benchmark já pegou
uma promessa de integração que não mudava nada (D11).

**Protocolo (3ª rodada do benchmark, em chamado novo).** Duas execuções do mesmo chamado, com o
plugin de território e o rainforest habilitados nas duas: braço **com mapa** (território real com
`territorio.json` publicado) e braço **sem mapa** (mesmo repositório, sem o manifesto). Mesmo
modelo, mesma entrada, N igual nos dois braços, júri cego dos resultados.

Três critérios, todos exigidos:

1. **Despacho:** todo agente declarado nos estágios percorridos aparece despachado no transcript
   do braço com mapa (conta por `tipo`; o critério é 100% dos declarados, contra zero despachos
   observados sem mapa nas rodadas 1 e 2).
2. **Qualidade:** a nota do júri cego no braço com mapa **não cai** em relação ao braço sem
   mapa (média com mapa >= média sem mapa).
3. **Custo:** o custo total do braço com mapa é **<= +30%** do braço sem mapa.

Falhar em qualquer um reprova o aceite.

## Onde mora o mapa real

O mapa do território real (agentes, tools, comandos e variáveis dele) mora **no repositório do
plugin desse território**, nunca neste (D13). Aqui ficam só este contrato, o `territorio.cjs`, as
quatro skills ligadas e o território sintético dos testes. O aceite acima roda quando os dois
existirem.
