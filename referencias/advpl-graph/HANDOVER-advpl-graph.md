# HANDOVER — Skill "advpl-graph" (grafo de conhecimento para fontes AdvPL/TLPP)

> Documento de transferência de contexto. Leia inteiro antes de agir.
> Origem: sessão de chat (claude.ai) em 29/08/2026, com Luís (Dev Lead TOTVS Brasil Central).

## 1. Objetivo

Criar uma skill de Claude Code (candidata a entrar no plugin `rainforest-mind`) que:
1. Varre uma pasta/repo de fontes AdvPL (`.prw`) e TLPP (`.tlpp`)
2. Gera um **grafo de conhecimento persistente** (`graph.json`) + **INDEX.md direcionado a IA** (não a humanos)
3. Permite que agentes respondam perguntas e criem funcionalidades **reusando código existente** em vez de duplicar — lendo o índice primeiro e abrindo só os trechos necessários (`line`/`end` por função)

Inspiração de formato: repo `safishamsi/graphify` (skill `/graphify` — graph.json + wiki agent-crawlable + cache SHA256 + `--update` incremental). Graphify NÃO suporta AdvPL (tree-sitter não tem parser), por isso o extrator próprio.

## 2. Estado atual — o que já foi validado

Dois protótipos Python funcionais, testados em fontes reais do módulo Fechamento Financeiro (projeto Inovação Agro):

- **`advpl_graph.py` (v0.1, fonte único)** — testado em `IAG67M12.prw` (13.691 linhas, 219 funções). Extraiu 490 arestas, 45 tabelas, 11 MVs, 2 ExecAutos. INDEX.md de 20KB vs fonte de 525KB (~26x menos tokens).
- **`advpl_graph2.py` (v0.2, multi-fonte)** — testado em IAG67M12.prw + 4 `.tlpp`. Resolveu 7 chamadas cross-source, 7 tabelas-ponte, e sinalizou 6 externos não resolvidos (fontes fora do conjunto — comportamento correto, viram ponteiros).

### O que os extratores capturam (tudo tag EXTRACTED, nada inferido)
- Definições: `User Function`, `Static Function`, `Function`, `Method`, `WSMethod` (+ linha início/fim de cada corpo)
- Chamadas locais função→função
- **Vínculos cross-source, 3 mecanismos (validados nos fontes reais):**
  1. Chamada qualificada por namespace TLPP: `tbcagro.agroindustria.fechamento_financeiro.ordem.u_mvc(...)`
  2. Chamadas `U_Nome()` — resolução: fonte local → namespaces visíveis (`using namespace`) → global
  3. Tabelas-ponte (mesma tabela usada por >1 fonte)
- Tabelas: `RetSqlName("XXX")`, `DbSelectArea("XXX")`, padrão `XXX->`
- Parâmetros: `SuperGetMV`/`GetMV`/`GetNewPar`
- ExecAutos: `MSExecAuto({|...| MATA103, ...})`

## 3. Pegadinhas descobertas (não redescobrir)

- **Encoding**: fontes Protheus legados vêm em ISO-8859-1. Sempre detectar (`file -b`) e converter pra UTF-8 antes de parsear.
- **Falsos positivos de tabela**: o padrão `XXX->` casa com variáveis de 3 letras. Há uma blocklist (`STR`, `VAL`, `QRY`, `TMP`...) que precisa crescer — melhor: validar contra dicionário SX2 do cliente quando disponível, ou exigir que o alias apareça também em `DbSelectArea`/`RetSqlName`/`FWFormStruct`.
- **Descrição de função**: cabeçalhos padrão TOTVS (`//---+---` com colunas Data/Autor/Descrição) são extraídos parcialmente pela regex atual — melhorar parse do bloco Protheus.doc (`/*/{Protheus.doc}...`).
- **Duplicata de aresta namespace+U_**: quando a chamada qualificada usa `.u_nome(`, a regex de `U_` também casa — dedup por (from, to) ignorando `via`, ou dar precedência à qualificada.
- **PE (pontos de entrada)**: `*_pe.tlpp` contém hooks do padrão (ex.: `F565TOK`). Marcar `kind: "entry_point"` e linkar à rotina padrão correspondente.
- **Static Functions são file-local** — nunca resolver cross-source por nome.

## 4. Próximos passos (ordem sugerida)

1. **Empacotar como skill**: `SKILL.md` + script, comando `/advpl-graph <pasta>`, saída em `graphify-out/` ou `advpl-graph-out/` na raiz do repo
2. **Modo incremental**: cache por hash de arquivo (copiar ideia do graphify) — só reprocessa o que mudou
3. **Instrução no CLAUDE.md do repo**: "antes de criar qualquer função, consulte advpl-graph-out/INDEX.md e liste candidatas a reuso"
4. Melhorias do §3 (blocklist/SX2, Protheus.doc, dedup, PE)
5. Rodar no repo inteiro da Fábrica e medir: % de `U_` resolvidos, tamanho do índice vs fontes
6. (Depois) git hook pós-commit pra regenerar, e talvez export `graph.html` interativo

## 5. Artefatos que acompanham este handover

- `advpl_graph.py` — extrator v0.1 (fonte único, gera god nodes + tabela de funções com line/end)
- `advpl_graph2.py` — extrator v0.2 (multi-fonte, resolve namespaces/U_/tabelas-ponte)
- `INDEX-multi.md` + `graph-multi.json` — saída real do módulo Fechamento Financeiro (5 fontes), útil como fixture de teste
- Fontes de teste usados: `IAG67M12.prw` + `tbcagro_agroindustria_fechamento_financeiro_{ordem_mvc,pe,liquidacao_pagar,liquidacao_receber}.tlpp`

## 6. Decisões já tomadas (não reabrir sem motivo)

- Saída direcionada a IA, não a humanos (sem HTML bonito por enquanto; INDEX.md + graph.json bastam)
- Só arestas `EXTRACTED` no MVP; `INFERRED` fica pra depois
- Formato de nó: `fonte::Funcao` com `line`/`end` pra leitura cirúrgica via view
- Python puro, sem dependências além da stdlib (roda em qualquer ambiente da Fábrica)
