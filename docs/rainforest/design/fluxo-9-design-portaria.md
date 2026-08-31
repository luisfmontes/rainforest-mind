# Fluxo 9 — Portaria (`portaria.cjs`)

> **Nota de renumeração (2026-08-30):** este design nasceu como "Fluxo 8" na
> conversa de origem. Renumerado para **9** pelo `LEIA-PRIMEIRO-CONSOLIDADO-v2`
> (o 8 pertence a handover+regente). Conteúdo da versão final (pós-análise
> hermes-agent) preservado; a seção "Validação externa" foi remontada a partir
> da conversa de origem — conferir contra o arquivo original se houver dúvida.

**Status:** rascunho para revisão
**Depende de:** `estado.cjs` (leitura do estágio ativo). Conversa com o fluxo 6 (mesmo padrão de lint) e alimenta o fluxo 7 (log de despacho como evidência), mas não bloqueia nem é bloqueado por eles.
**Origem:** decisão interna (conversa de 2026-08-29). Desenho validado contra hermes-agent (NousResearch, MIT) *depois* de pronto — convergência independente, não derivação. Uma ideia anotada para o futuro vem de lá e carrega atribuição (ver "fica de fora").
**Stack:** Node puro, CommonJS, zero dependência, compatível com Windows.

---

## Problema

A regra 10 exige autorização humana de subagentes a cada sessão. O custo é pago toda sessão e o ganho é nenhum: a autorização humana não verifica nada — depois da terceira vez, aprova-se por cansaço. É regra em prosa operada por atenção humana, exatamente o que a casa proíbe ("exit code, não instrução").

## Decisão

Substituir **autorização por sessão** por **admissão por manifesto**, decidida por um hook `PreToolUse` que intercepta toda chamada de Task. A regra fica mais restritiva e some do caminho do humano ao mesmo tempo:

> **Regra 10 (reescrita):** Subagente só roda se estiver declarado em `.rainforest/agentes.json` e o estágio ativo constar na sua lista. A portaria decide por código; o humano nunca é perguntado em sessão. Exceção não existe em runtime — exceção é editar o manifesto, e edição de manifesto é mudança versionada que passa pelo `revisar`.

---

## Validação externa — hermes-agent (NousResearch, MIT)

Comparação feita *depois* do desenho pronto (clonado e lido em 2026-08-29). Quatro convergências independentes, todas em código de produção no `delegate_tool.py` deles:

1. **Contexto isolado + retorno só de resumo** — filho nasce com contexto limpo e o pai só vê o resumo.
2. **Blocklist em código** — `DELEGATE_BLOCKED_TOOLS` hardcoded (sem delegação recursiva, sem interação com usuário, sem escrita na memória compartilhada): regra em código, não em prosa.
3. **Fail-closed como default** — aprovação de subagente com auto-deny e log de auditoria, igual ao Q2 daqui.
4. **Registro de despacho autocontido** — cada decisão logada legível isolada.

**Onde diverge — e a divergência é o ponto:** no hermes, o *modelo* decide quando e o que delegar (loop livre, filhos `orchestrator` com profundidade 2, despacho em background), e existe "smart approval" — um LLM auxiliar aprovando comandos perigosos. Para um assistente geral, cabe. Para o rainforest, é o anti-padrão: julgamento de modelo como oráculo. Aqui quem admite é manifesto + estágio, decidido por exit code. Nada do modelo de orquestração deles entra.

---

## Peças

### 1. Manifesto — `.rainforest/agentes.json`

```json
{
  "versao": 1,
  "agentes": {
    "revisor":          { "estagios": ["revisar"], "escreve": false },
    "sabotador":        { "estagios": ["revisar"], "escreve": false },
    "arqueologo-ativo": { "estagios": ["design"],  "escreve": false }
  }
}
```

- `estagios`: em quais estágios do grafo o agente pode ser despachado.
- `escreve`: por ora, sempre `false`. Subagente não escreve, só relata (ver "fica de fora"). O campo existe para que a exceção futura seja uma linha de diff, não uma mudança de schema.

### 2. O hook — `portaria.cjs`

Registrado em `.claude/settings.json` **do projeto** (versionado — Q1) como `PreToolUse` com matcher para a tool `Task`. Fluxo de decisão:

1. Lê o payload JSON do stdin; extrai o nome do agente do `tool_input` (Q3).
2. Carrega `.rainforest/agentes.json`. Ausente ou inválido → **nega tudo** (fail-closed).
3. Agente não declarado → nega, motivo: `agente '<nome>' não consta no manifesto`.
4. Consulta `estado.cjs` para o estágio ativo. Sem estágio ativo → nega, motivo: `sem estágio ativo — abra um fluxo` (Q2, fail-closed).
5. Estágio ativo fora de `estagios` do agente → nega, motivo com o estágio atual e os permitidos.
6. `escreve: false` mas o arquivo `.claude/agents/<nome>.md` declara tools fora da allowlist read-only (`Read`, `Grep`, `Glob`) → nega. A checagem roda também no lint, mas repete em runtime porque o arquivo do agente pode mudar depois do lint.
7. Tudo passou → **aprova** e anexa uma linha ao log de despacho.

Toda negação sai com motivo não vazio — negação muda é bug.

### 3. Log de despacho — `.rainforest/portaria/despachos.jsonl`

Append-only, nunca reescrito (mesma disciplina do histórico do fluxo 5). Uma linha por decisão, aprovada ou negada:

```json
{"ts":"2026-08-31T14:02:11Z","agente":"sabotador","estagio":"revisar","decisao":"allow","sessao":"<id>"}
{"ts":"2026-08-31T14:05:47Z","agente":"ensaio","estagio":"revisar","decisao":"deny","motivo":"agente 'ensaio' não consta no manifesto","sessao":"<id>"}
```

Cada linha é autocontida — legível isolada, sem precisar do resto do log para fazer sentido (padrão confirmado pelo registro de despacho do hermes-agent, ver validação externa).

O log é evidência de primeira classe: o `colher` pode responder "quem rodou, quando, em qual estágio" com `cat`, e o recibo do fluxo 7 pode referenciá-lo.

### 4. Modo lint — `portaria.cjs --lint`

Roda no `plano`, espelhando o lint do fluxo 6 (pegar desonestidade antes da execução):

- Agente no manifesto sem arquivo correspondente em `.claude/agents/` → erro.
- Arquivo em `.claude/agents/` sem entrada no manifesto → aviso (órfão: existe mas nunca vai rodar).
- `escreve: false` com tool de escrita no frontmatter → erro.
- `estagios` contendo estágio que o grafo não conhece → erro.
- Manifesto com JSON inválido ou `versao` desconhecida → erro.

Exit 0 só com zero erros.

---

## Portões do próprio fluxo (rascunho)

| # | CHECK | ESPERA |
|---|-------|--------|
| P1 | `node .rainforest/portaria.cjs --lint` sai 0 no repo com manifesto de exemplo | `lint:ok` |
| P2 | Teste com stdin simulado: agente **não declarado** recebe deny com motivo não vazio (script de teste sai 0) | `deny:nao-declarado` |
| P3 | Teste: agente declarado em **estágio errado** recebe deny citando estágio atual e permitidos | `deny:estagio` |
| P4 | Teste: agente declarado + estágio certo recebe allow **e** `despachos.jsonl` ganha exatamente uma linha com os campos obrigatórios | `allow:logado` |
| P5 | Manifesto removido → qualquer despacho recebe deny (fail-closed comprovado) | `deny:fail-closed` |

Todos os testes rodam offline, com payload simulado — não dependem de sessão real do Claude Code.

## Pronto quando (falsificável)

- Os cinco portões acima fecham com CHECK saindo 0 e ESPERA batendo.
- `despachos.jsonl` é comprovadamente append-only: byte count monotônico entre duas execuções consecutivas do teste P4.
- O lint pega, num repo de fixture, um agente com `Write` no frontmatter e `escreve: false` no manifesto.
- Uma sessão real do Claude Code despacha um agente declarado sem nenhum prompt de autorização ao humano (verificação manual única, registrada como evidência).

---

## O que fica de fora e por quê

- **Aprovação interativa de exceção** ("pergunta só quando não está no manifesto") — reintroduz o custo por sessão pela porta dos fundos e transforma negação em negociação. Exceção é diff no manifesto.
- **Subagente que escreve** — quebra a cadeia de evidência do recibo (fluxo 7): o recibo assina o que a sessão principal produziu; escrita fora dela é escrita sem assinatura. Fica de fora **agora**, mas a reavaliação futura já tem caminho pronto: o padrão de worktree por filho do hermes-agent (`subagent_worktree.py`, NousResearch, MIT — por sua vez implementação clean-room da semântica documentada do Muse Code). Filho write-capable ganha worktree git próprio branched do HEAD, commita lá, worktree limpo é podado e worktree com trabalho é reportado; quem revisa e faz o merge é a sessão principal — ou seja, a assinatura do recibo acontece no merge e a cadeia de evidência sobrevive. Se um dia `escreve: true` entrar, é com worktree obrigatório, e a portaria checa a flag de isolamento antes de aprovar. Requer atribuição no header do script quando implementado.
- **Teams dinâmicos / orquestração multi-nível** — o grafo é o rainforest; subagente é ferramenta de estágio, não segunda camada de arquitetura. Profundidade 1 é limite do harness e convém como limite de design.
- **Portaria para outras tools (MCP, Bash)** — escopo é Task. Permissão de tool comum continua no `settings.json` nativo; duplicar isso aqui criaria dois donos para a mesma decisão.
- **Cache de decisão** — a decisão custa duas leituras de arquivo pequeno; cache adiciona estado e um jeito novo de estar errado.

---

## Qs (decisões abertas, com recomendação)

**Q1 — Onde registrar o hook:** `.claude/settings.json` versionado vs `settings.local.json` pessoal. **Recomendo versionado**: regra da casa viaja com o repo; quem clona já chega governado.

**Q2 — Sem estágio ativo:** fail-closed (nega) vs fail-open (aprova). **Recomendo fail-closed** com motivo instrutivo. Coerente com o resto: fora do grafo, nada roda.

**Q3 — Campo do nome do agente no payload:** o formato exato do `tool_input` do Task (e o schema de resposta do hook — `permissionDecision` etc.) pode ter mudado desde jan/2026. **Recomendo resolver no `executar`**: primeiro despacho de teste grava o payload real em `.rainforest/portaria/amostra.json`, o parser é fixado contra a amostra, e a amostra fica no repo como documentação. P2–P5 pegam qualquer divergência futura.

---

## Plano (rascunho, ordem de dependência)

1. **Schema + fixture** — criar `agentes.json` de exemplo e um repo de fixture mínimo para os testes de lint. *Muta:* `.rainforest/agentes.json`, `test/fixtures/`.
2. **Amostra de payload (Q3)** — despacho real de teste, gravar `amostra.json`. *Muta:* `.rainforest/portaria/amostra.json`. Bloqueia o passo 3.
3. **`portaria.cjs` núcleo** — parser sobre a amostra, decisão 1–7, log append-only. *Muta:* `.rainforest/portaria.cjs`, `despachos.jsonl`.
4. **`--lint`** — as cinco checagens. *Muta:* `portaria.cjs`.
5. **Testes dos portões P1–P5** — stdin simulado, offline. *Muta:* `test/portaria/*.cjs`.
6. **Registro do hook + regra 10 reescrita** — settings versionado, texto novo da regra na doc. *Muta:* `.claude/settings.json`, doc de regras.
7. **Verificação manual única** — sessão real sem prompt de autorização, registrada como evidência. Fecha o fluxo.

> **Aviso de compatibilidade:** sintaxe de hooks e permission rules conferir em https://docs.claude.com/en/docs/claude-code/overview antes do passo 6. O desenho não depende do detalhe — só o registro e o parser, e ambos têm portão cobrindo.
