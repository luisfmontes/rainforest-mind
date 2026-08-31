# Fluxo 11 — Conselho (`conselho.cjs`, debate estruturado de decisões de design)

> **Nota de numeração (2026-08-30):** o design de origem estava "aguardando
> numeração de fluxo". Numerado como **11** pelo `LEIA-PRIMEIRO-CONSOLIDADO-v2`.
> Conteúdo inalterado. A decisão aberta (fluxo independente vs. passo do
> `design`) permanece aberta — recomendações registradas ao fim.

**Status:** rascunho — proposta B aprovada em conversa (2026-08-29). Aguarda plano.
**Dependências:** `estado.cjs` (registro de rodada e transições), padrão de contrato dos territórios (interface de membro), fluxo 7 (padrão do campo obrigatório `nao_provado`, reutilizado aqui como `divergencias_nao_resolvidas`).

---

## Origem e atribuição

Ideias mineradas de **karpathy/llm-council** (https://github.com/karpathy/llm-council). O repo **não possui arquivo de licença**; portanto isto é *idea-mining*, não rewrite de código — nenhuma linha do original é reaproveitada. Ideias incorporadas, com adaptação:

1. **Revisão cruzada anonimizada** — no original, os modelos avaliam respostas uns dos outros sem saber a autoria, para não jogar favoritismo. Aqui, a anonimização deixa de ser instrução e vira **função do script**: `conselho.cjs` embaralha e renomeia os pareceres (membro-A, membro-B, membro-C) antes da fase de revisão.
2. **Ranking cruzado** — cada membro ordena os pareceres alheios. Aqui o ranking incompleto é **reprovado por exit code**, não por pedido.
3. **Síntese por Chairman** — no original, um LLM designado compila a resposta final. Aqui o Chairman é **mecânico**: o script coleta, valida e monta a síntese a partir de campos estruturados; a redação final é uma passada de modelo sobre dados já validados.

Adaptação de propósito: o llm-council responde perguntas abertas. O conselho do rainforest-mind **debate decisões de design antes do plano** — o ponto do fluxo onde uma escolha errada ainda é barata.

Atribuição obrigatória no cabeçalho de `conselho.cjs` e neste documento.

---

## Mecanismo

Três fases, todas serializadas em JSON no diretório da rodada (`.rainforest/conselho/<id-rodada>/`).

### Fase 1 — Pareceres
- `conselho.cjs abrir --questao <arquivo.md>` registra a rodada no estado e gera um prompt-arquivo por membro.
- Cada membro (subagente com persona) produz `parecer-<membro>.json`:

```json
{
  "posicao": "…",
  "argumentos": ["…"],
  "objecoes": ["objeção concreta à questão ou às alternativas"],
  "riscos": ["…"]
}
```

- **`objecoes` vazio = reprovado.** É a defesa mecânica contra a convergência Claude-com-Claude: instâncias do mesmo modelo tendem a concordar; cada membro é obrigado a produzir ao menos uma objeção verificável.

### Fase 2 — Revisão anonimizada
- `conselho.cjs revisar` embaralha os pareceres, remove identidade de persona e distribui a cada membro os pareceres **dos outros**.
- Cada membro devolve `revisao-<membro>.json` com ranking ordenado (todos os pareceres alheios, sem empate) e uma crítica por parecer.
- Ranking incompleto ou parecer não criticado = **reprovado**.

### Fase 3 — Síntese
- `conselho.cjs sintetizar` valida os artefatos, agrega rankings (posição média, desempate por contagem de primeiros lugares) e produz `sintese.json`:

```json
{
  "decisao_recomendada": "…",
  "fundamentos": ["…"],
  "divergencias_nao_resolvidas": ["obrigatório; vazio só com --unanime explícito"],
  "ranking_agregado": ["membro-B", "membro-A", "membro-C"]
}
```

- Síntese sem `divergencias_nao_resolvidas` (e sem `--unanime`) = **reprovado**. Consenso fabricado é o modo de falha número um de comitês de LLM; o campo força o registro do que **não** foi resolvido, irmão do `nao_provado` do fluxo 7.

### Personas v1
`cetico`, `arquiteto`, `usuario-final`. O `sabotador` do backlog criativo entra como quarto membro quando existir como agente. Persona é papel (agente); conhecimento de domínio, se necessário, vem de skill — mesma separação já confirmada no design de territórios.

---

## Contrato de membro

Membro do conselho é um **executável declarado em config**, não um modelo hard-coded — mesmo padrão do contrato de território.

```json
{
  "membros": [
    { "nome": "cetico",  "cmd": "claude -p @{prompt} > {saida}" },
    { "nome": "arquiteto", "cmd": "claude -p @{prompt} > {saida}" }
  ]
}
```

Contrato: recebe caminho do arquivo de prompt, escreve JSON de parecer no caminho de saída, exit 0 em sucesso. `conselho.cjs` valida o JSON contra o schema; JSON inválido = reprovado com mensagem apontando o campo.

- **v1: só o adaptador Claude é implementado.** `codex exec` e `gemini -p` cabem no mesmo contrato via `child_process` sem nenhuma dependência npm — entram depois como **integração opcional declarável** (mesmo padrão do bridge/setup). O segundo adaptador valida a interface, como o repo AdvPL valida o contrato de território.
- Comandos executados via `child_process.spawn` com shell explícito por plataforma — compatibilidade Windows é requisito, como no resto do repo.

---

## Portões (rascunho)

| Portão | CHECK | ESPERA | Falha |
|---|---|---|---|
| pareceres-completos | `node conselho.cjs conferir --fase pareceres` | exit 0, N pareceres válidos | reprovado; lista membros faltantes |
| objecoes-presentes | idem (mesma validação) | `objecoes.length >= 1` em todos | reprovado |
| revisoes-completas | `node conselho.cjs conferir --fase revisao` | ranking total e sem empates | reprovado |
| sintese-honesta | `node conselho.cjs conferir --fase sintese` | `divergencias_nao_resolvidas` presente ou `--unanime` | reprovado |
| teto-de-rodada | contador em estado | ≤ 2 tentativas por fase | **ABANDONA** |

Todos verificáveis em modo lint (fluxo 6): os CHECKs são comandos executáveis com saída determinística — sem oráculo desonesto.

---

## O que fica de fora e por quê

- **Debate multi-rodada com convergência (proposta C):** valor marginal da rodada 2 é baixo e o custo triplica. Se a síntese acumular divergências recorrentes, reavaliar.
- **Modelos externos na v1:** o contrato já os comporta; implementá-los agora adiciona chaves de API, custo e superfície Windows sem validar antes o núcleo.
- **UI web e OpenRouter do original:** o rainforest-mind é CLI, solo, zero-dependency. Nada disso sobrevive à tradução.
- **Ranking com notas numéricas:** ordem total simples basta para agregação; notas convidam falsa precisão.
- **Anonimização criptográfica:** embaralhamento + renome no script é suficiente para o caso solo; não há adversário real.

---

## Pronto quando (falsificável)

1. `node conselho.cjs abrir --questao exemplo.md` cria a rodada e N arquivos de prompt → exit 0.
2. Parecer com `objecoes: []` → `conferir --fase pareceres` retorna exit 1 citando o membro.
3. Revisão com ranking faltando um parecer → `conferir --fase revisao` retorna exit 1.
4. Síntese sem `divergencias_nao_resolvidas` e sem `--unanime` → `conferir --fase sintese` retorna exit 1.
5. Rodada completa e válida → `sintetizar` grava `sintese.json` e registra `ok` no estado.
6. Terceira tentativa consecutiva reprovada na mesma fase → estado registra **ABANDONA**.
7. Suíte roda igual em Linux e Windows (caminhos via `path.join`, spawn por plataforma).

---

## Alvos de mutação

- **Novo:** `conselho.cjs`, schema dos JSONs de parecer/revisão/síntese, prompts de persona (`cetico`, `arquiteto`, `usuario-final`).
- **Tocado:** `estado.cjs` (registro de rodada e do resultado no grafo), config (bloco `membros`), `/saude` (seção do conselho: rodadas abertas, ABANDONAs).
- **Intocado:** `poda.cjs`, `portoes.cjs` (o conselho declara portões, não altera o motor), subsistema de memória.

---

## Decisão aberta (Q1)

**Fluxo independente vs. passo opcional dentro do `design`.** Duas recomendações registradas em conversas distintas, para você fechar:

- *Conversa de origem:* **fluxo independente** — decisões de design são o caso principal, mas o conselho pode ser convocado no `revisar` também.
- *Índice consolidado v2:* **passo opcional do `design`**, ativado por presença de `.rainforest/conselho/` — padrão opt-in das `rubricas/`, sem inflar o grafo.

Ambas preservam o mecanismo; a diferença é só onde o gancho vive. Fechar antes do plano.
