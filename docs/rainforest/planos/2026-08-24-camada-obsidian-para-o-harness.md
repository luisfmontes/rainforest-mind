# Plano: Camada Obsidian para o harness — a skill `montar-corpus`

Design: `docs/rainforest/design/2026-08-24-camada-obsidian-para-o-harness.md` (D1–D14, aprovado em 2026-08-24 — `docs/rainforest/estado/2026-08-24-camada-obsidian-para-o-harness.json`, `design.status: "aprovado"`).

Planejado em 2026-09-05, doze dias depois da aprovação, no inventário do acervo parado (PR #190). O design ficou com `plano`, `executar`, `revisar`, `verificar` e `fechar` em `"pendente"` desde então.

**Nome da entrega (o design nunca o fixou): `montar-corpus`.** Decidido pelo dono em 2026-09-05, contra `acervo`: a palavra já carrega dois sentidos concorrentes neste repositório — a coleção de incidentes em `skills/rainforest-mind/references/regra-12-acervo.md` e o inventário em `docs/rainforest/mapas/2026-09-05-acervo-*.md`. Um terceiro sentido empilharia ambiguidade num repo que o próprio design cita como já queimado por nome ambíguo ("segundo cérebro" nomeando instância e conceito).

## Achados que mudam o plano (leia antes das tarefas)

**1. D4 já está feito, e do lado certo da fronteira — CONFIRMADO.** A tabela de rota vive na skill pessoal `segundo-cerebro` (fora deste repositório, em `<home>/.claude/skills/`), com `## Rota por sintoma` na linha 41 e `## Rota por regra` na linha 72, somando as 24 páginas de wiki. O texto de D3 ("18 sem rota") não reflete o estado real: a tabela é anterior ao commit do próprio design.

**2. D4 NÃO deve ser implementado na direção que o design descreve — decidido em 2026-09-05.** D4 pede citação da página "na elaboração de cada regra", isto é, dentro de `skills/rainforest-mind/references/regra-NN.md`. Esses arquivos são **distribuídos a terceiros** — é o motivo de D2 existir. Gravar o caminho de uma página de wiki ali entrega caminho morto a toda instalação de terceiro e expõe a taxonomia de notas pessoais do dono dentro de um plugin público: exatamente o vazamento que D2 nomeia. CONFIRMADO que a direção pedida não existe hoje: `grep -c "wiki/"` em `references/regra-06.md`, `regra-07.md`, `regra-08.md` e `regra-09.md` devolve **0** nos quatro. A rota inversa já existe, na skill pessoal, que não é distribuída. Fechar a rota das regras que faltam é edição da skill pessoal, **fora deste repositório e fora deste plano**.

**3. D12 está bloqueado, não pendente — CONFIRMADO.** D12 pressupõe o grafo existindo para a `arqueologia` consumir. O único extrator que este design constrói (D6) é de **wiki**, não de código; o extrator de código é a frente 2, que o próprio design põe fora de escopo. `skills/arqueologia/SKILL.md:31-34` segue com três degraus — `CONFIRMADO`, `INFERIDO`, `LACUNA` — e o quarto não tem sobre o que se apoiar. Planejar D12 agora seria mandar construir sobre o que não existe.

**4. Dois mecanismos já prontos para reusar — CONFIRMADO.** `hooks/lib/raiz.cjs` exporta `resolverRaiz` (`:102`), a cadeia de quatro níveis que D14 pede; `hooks/lib/projetos.cjs` exporta `ler` e `resolverSlug` (`:252`), o vocabulário por slug que D9 pede para `--corpus`. Nenhum dos dois nasceu para este design, e os dois servem sem alteração.

**5. O corpus de validação tem 24 páginas — CONFIRMADO** por contagem dos `wiki/*.md` do repositório `segundo-cerebro`. É o número que a T5 usa como asserção de ponta a ponta.

**6. Nada do motor existe — CONFIRMADO.** `ls skills/` lista 16 skills e nenhuma trata de corpus, grafo ou acervo; não há schema, extrator nem build. É o núcleo real que falta, e é o que as tarefas 1 a 4 constroem.

**7. `graphifyy` não é dependência deste plano.** D8/D10 preveem a conferência de dependência externa, mas o extrator de D6 lê aresta **já escrita** no markdown (`relacionados` no frontmatter e `[[link]]` no corpo) — não infere ligação. A função de conferência nasce na T4 pelo padrão do `doutor()` do `sabia` (`sabia.py:1282`), e recusa em vez de instalar; ela só terá o que conferir quando existir um preenchedor que precise, que não é o desta entrega.

## O que não pode quebrar

- **Nenhum conteúdo do `segundo-cerebro` entra neste repositório** (D2). A skill lê o corpus e escreve o acervo gerado na raiz de dados do rainforest, nunca dentro do `rainforest-mind`.
- **Nenhum comando roda sem alvo explícito** (D9). Sem `--repo` nem `--corpus`, recusa. "Geral da máquina" não existe como modo.
- **A skill nunca instala nada** (D10, regra 15). Dependência ausente para e reporta o comando que falta.
- O validador da T1 é **Node puro**. Instalar `ajv` ou qualquer validador de JSON Schema violaria a regra 15 e não é necessário para a forma que D5 descreve.
- `skills/arqueologia/SKILL.md` fica **intacto** nesta entrega — ver achado 3.
- `skills/rainforest-mind/references/regra-*.md` ficam **intactos** nesta entrega — ver achado 2.
- Nenhum caminho de home entra em arquivo versionado — o gate de publicação recusa, e recusou este plano na primeira gravação.

## Tarefas

### 1. Schema de nós e arestas, com validador sem dependência [tipo: implementar]
atende: D5, D13
arquivos: `skills/montar-corpus/schema/grafo.schema.md`, `scripts/validar-grafo.cjs`, `scripts/testa-validar-grafo.sh`, `test/fixtures/corpus/grafo-exemplo.json`
depende de: nenhuma
paralela: sim

Escopo: fixa a forma do grafo em prosa mais exemplo JSON (não JSON Schema formal — ver "O que não pode quebrar") e escreve o validador em Node puro. Nó: `id`, `caminho`, `titulo`, `resumo`, `file_type` (enum `code|document|paper|image|rationale|concept`) e `confidence` (enum `EXTRACTED|INFERRED|AMBIGUOUS`). Aresta: `de`, `para`, `tipo`, `via`. O que se distribui é este formato, não o conteúdo nem um gerador único (D13).

mutacao:
  arquivo: `scripts/validar-grafo.cjs`
  de: `file_type` fora do enum é recusado com exit 1 e o campo nomeado
  para: `file_type` fora do enum passa como válido
  bateria: `bash scripts/testa-validar-grafo.sh`
  fixture: `test/fixtures/corpus/grafo-exemplo.json` com uma cópia adulterada em que `file_type` vale `poema`

pronto quando: com o fixture `test/fixtures/corpus/grafo-exemplo.json`, o grafo é aceito e a cópia com `"file_type": "poema"` é recusada nomeando o campo — provado por `node scripts/validar-grafo.cjs test/fixtures/corpus/grafo-exemplo.json` devolvendo `valido` e exit 0, e o mesmo comando sobre a cópia adulterada devolvendo `invalido: file_type` e exit 1.

### 2. Extrator de wiki para grafo [tipo: implementar]
atende: D6
arquivos: `skills/montar-corpus/extratores/wiki.cjs`, `skills/montar-corpus/testa-extrator-wiki.sh`, `test/fixtures/corpus/wiki-minima/**`
depende de: 1
paralela: nao

Escopo: lê cada `wiki/*.md` do corpus alvo, emite um nó `concept` por página e uma aresta por ligação declarada — `relacionados` no frontmatter e `[[link]]` no corpo. É **transcrição, não extração**: a aresta já está escrita pelo autor, e o extrator não infere ligação nova. Ligação para página inexistente vira aresta com `confidence: "AMBIGUOUS"`, nunca é descartada em silêncio.

mutacao:
  arquivo: `skills/montar-corpus/extratores/wiki.cjs`
  de: ligação apontando para página inexistente vira aresta `AMBIGUOUS`
  para: ligação apontando para página inexistente é descartada sem registro
  bateria: `bash skills/montar-corpus/testa-extrator-wiki.sh`
  fixture: `test/fixtures/corpus/wiki-minima/` — três páginas, uma delas ligando para uma página que não existe

pronto quando: com as 24 páginas reais do corpus `segundo-cerebro`, sai um grafo com 24 nós `concept` que o validador da tarefa 1 aceita — provado por `node skills/montar-corpus/extratores/wiki.cjs --corpus segundo-cerebro > /tmp/grafo.json` seguido de `node scripts/validar-grafo.cjs /tmp/grafo.json` devolvendo `valido` e exit 0, e de `node -e "console.log(require('/tmp/grafo.json').nos.filter(n=>n.file_type==='concept').length)"` devolvendo `24`.

### 3. Build do acervo em markdown, na raiz de dados [tipo: implementar]
atende: D7, D14
arquivos: `skills/montar-corpus/build.cjs`, `skills/montar-corpus/testa-build.sh`, `test/fixtures/corpus/grafo-exemplo.json`
depende de: 1
paralela: nao

Escopo: consome o `grafo.json` (JSON é formato de troca entre estágios) e escreve o artefato que se consome, que é markdown (D7). Usa `resolverRaiz` de `hooks/lib/raiz.cjs` para achar a raiz e cria `<raiz>/acervo/<corpus>/` com uma nota curta por nó, mais um `INDEX.md` com a rota de entrada. Uma pasta por corpus, nunca uma pasta "geral" (D14). Não roda `git init`, não cria remote e não commita — criar repositório é alterar o ambiente do usuário.

mutacao:
  arquivo: `skills/montar-corpus/build.cjs`
  de: o destino é sempre `<raiz>/acervo/<corpus>/`, com `<corpus>` obrigatório
  para: sem `<corpus>`, escreve direto em `<raiz>/acervo/`
  bateria: `bash skills/montar-corpus/testa-build.sh`
  fixture: `test/fixtures/corpus/grafo-exemplo.json`, com raiz apontada para sandbox por `RFM_ROOT`

pronto quando: com o fixture e a raiz em sandbox, o acervo aparece com um arquivo por nó mais o índice — provado por `RFM_ROOT=<sandbox> node skills/montar-corpus/build.cjs test/fixtures/corpus/grafo-exemplo.json --corpus exemplo` seguido de `ls <sandbox>/acervo/exemplo/` listando `INDEX.md` e um `.md` por nó do fixture, e de `test -s <sandbox>/acervo/exemplo/INDEX.md` saindo 0.

### 4. Empacotar como skill, com alvo explícito e conferência de dependência [tipo: implementar]
atende: D8, D9, D10
arquivos: `skills/montar-corpus/SKILL.md`, `skills/montar-corpus/cli.cjs`, `skills/montar-corpus/testa-cli.sh`
depende de: 2, 3
paralela: nao

Escopo: a entrega é uma skill que gera o acervo de **um corpus por vez** (D8). O CLI resolve o alvo: `--repo` usa `CLAUDE_PROJECT_DIR` ou o cwd, no mesmo default de `resolverRaiz`; `--corpus <slug>` resolve o caminho por `resolverSlug` de `hooks/lib/projetos.cjs`; sem nenhum dos dois, **recusa** (D9). A função de conferência de dependência externa nasce aqui, no molde do `doutor()` do `sabia`, e nomeia o comando que falta em vez de instalar (D10) — ver achado 7 sobre por que ela não tem o que conferir ainda.

mutacao:
  arquivo: `skills/montar-corpus/cli.cjs`
  de: sem `--repo` e sem `--corpus`, recusa com exit diferente de 0 citando os dois flags
  para: sem alvo, assume o cwd e roda
  bateria: `bash skills/montar-corpus/testa-cli.sh`
  fixture: invocação sem argumento nenhum, em sandbox com `projetos.json` de teste

pronto quando: com o corpus real `segundo-cerebro` registrado em `projetos.json`, o acervo é gerado; e sem alvo, nada roda — provado por `node skills/montar-corpus/cli.cjs` devolvendo exit diferente de 0 com mensagem citando `--repo` e `--corpus`, por `node skills/montar-corpus/cli.cjs --corpus corpus-que-nao-existe` devolvendo exit diferente de 0 nomeando o slug ausente, e por `node skills/montar-corpus/cli.cjs --corpus segundo-cerebro` devolvendo exit 0 com o acervo em `<raiz>/acervo/segundo-cerebro/`.

### 5. Ponta a ponta no corpus real, e registro das decisões que não viram código [tipo: doc]
atende: D1, D2, D3, D4, D11, D12
arquivos: `docs/rainforest/design/2026-08-24-camada-obsidian-para-o-harness.md`, `relatorios/2026-09-05-camada-obsidian-fechamento.md`
depende de: 4
paralela: nao

Escopo: roda a skill contra o `segundo-cerebro` inteiro e registra, no design e no relatório de fechamento, o que esta entrega decidiu **não** construir e por quê — para que ninguém reabra as discussões. São seis decisões sem código: D1 e D2 são decisão pura, sem artefato pendente (o `segundo-cerebro` já é repo separado e nenhum arquivo muda de lugar); D3 está atendido pela tabela de rota que já existe (achado 1); D4 fica deliberadamente fora deste repositório (achado 2); D11 o próprio design já põe fora de escopo; D12 fica bloqueado até a frente 2 existir (achado 3). Antes de rodar, conferir se `segundo-cerebro` está em `projetos.json` — não foi confirmado no levantamento, é LACUNA.

mutacao: n/a
  motivo: tarefa de documentação e validação de ponta a ponta. Não introduz comportamento novo — o comportamento que ela exercita é o das tarefas 1 a 4, e cada uma tem a própria mutação. O que ela produz é registro, e registro não se valida por mutação.

pronto quando: com as 24 páginas reais do `segundo-cerebro`, o acervo sai completo e sem ligação perdida — provado por `node skills/montar-corpus/cli.cjs --corpus segundo-cerebro` devolvendo exit 0, por `ls <raiz>/acervo/segundo-cerebro/*.md | wc -l` devolvendo `25` (as 24 páginas mais o `INDEX.md`), e por `grep -c "](" <raiz>/acervo/segundo-cerebro/INDEX.md` batendo com a contagem de arestas do grafo correspondente.

## Paralelismo

A tarefa 1 abre. Depois dela, 2 e 3 podem correr juntas — a 3 usa o fixture que a 1 entrega, não a saída da 2. A 4 depende das duas. A 5 fecha.

## O que este plano deliberadamente não faz

- **Não implementa D4 dentro do `rainforest-mind`** — achado 2. É edição da skill pessoal, noutro repositório.
- **Não planeja D12** — achado 3. Fica registrado como bloqueado pela frente 2, não como pendência deste plano.
- **Não constrói a metade "padrão TOTVS" (D11)** — o próprio design já a põe fora de escopo.
- **Não resolve a licença do `sabia`** — o design a registra em aberto, e ela só bloqueia a aplicação de D10 ao `sabia` no dia em que ele for distribuído. Nenhuma tarefa acima distribui o `sabia`.
- **Não fixa o nome do quarto degrau da escala de confiança** — pertence a D12, que está bloqueado.
