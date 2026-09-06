# Fechamento da tarefa 5 — Camada Obsidian para o harness

Datado 2026-09-05. Validação de ponta a ponta da skill `montar-corpus` contra o corpus real `segundo-cerebro`.

## Critério de pronto — validação ponta a ponta

**Critério 1:** `RFM_ROOT=<sandbox> node skills/montar-corpus/cli.cjs --corpus segundo-cerebro` → exit 0

```
[1/3] Extraindo segundo-cerebro...
[2/3] Validando segundo-cerebro...
[3/3] Construindo acervo de segundo-cerebro...
Pronto: acervo de segundo-cerebro em <sandbox>/acervo/segundo-cerebro/
```

✅ CONFIRMADO: exit 0

---

**Critério 2:** `ls <sandbox>/acervo/segundo-cerebro/*.md | wc -l` → **25**

```
25
```

✅ CONFIRMADO: 25 arquivos (24 páginas + INDEX.md)

---

**Critério 3:** `ls ~/.rainforest/acervo` → não existe; `ls ~/.rainforest/.temp` → não existe

```
~/.rainforest/acervo: False
~/.rainforest/.temp: False
```

✅ CONFIRMADO: raiz de dados real limpa, sem contaminação

---

**Critério 4:** `test -f relatorios/2026-09-05-camada-obsidian-fechamento.md` → exit 0

✅ CONFIRMADO: arquivo presente

---

## Registro das seis decisões que não viram código

A entrega deliberadamente **não constrói** as seguintes decisões do design e as registra aqui para que ninguém as reabra. Cada uma é justificada pelo achado que a fecha.

### D1 — O Obsidian sai inteiro, inclusive como leitor; markdown com `[[link]]` fica como formato

**Tipo:** Decisão pura, sem artefato pendente.

**Motivo (do design):** O dono não abre o aplicativo nem para ler, então toda decisão de desenho que mirava o visualizador (nota de comunidade, layout de vault) perdeu a justificativa; o formato sobrevive porque markdown serve tanto a humano quanto a agente, e renderiza no GitHub.

**Implementação:** Nenhuma. O Obsidian já é externo e o Markdown já é o formato escolhido pelo extrator (D6, tarefa 2).

---

### D2 — O acervo `segundo-cerebro` continua repositório separado e privado

**Tipo:** Decisão pura, sem artefato pendente.

**Motivo (do design):** O `rainforest-mind` é plugin distribuído a terceiros e o acervo tem material pessoal; fundir trocaria um problema de roteamento por um problema de vazamento. O `para-aplicado.md` já tinha decidido que nenhum arquivo muda de lugar, e a decisão se confirma por um motivo mais forte do que quando foi escrita.

**Implementação:** Nenhuma. O corpus continua em `C:/Projetos/segundo-cerebro` (confirmado em `projetos.json`), e nenhum arquivo se moveu.

---

### D3 — O problema é roteamento, não armazenamento

**Tipo:** Atendido pela tabela de rota que já existe.

**Motivo (do plano, achado 1):** Das 24 páginas de wiki, 6 têm rota (a tabela sintoma→página da skill `message-standards`, que funciona e foi observada disparando) e 18 dependem do gatilho temático da skill `segundo-cerebro`, que exige a sessão reconhecer o assunto. A tabela de rota vive na skill pessoal `segundo-cerebro` (fora deste repositório, em `<home>/.claude/skills/`), com `## Rota por sintoma` na linha 41 e `## Rota por regra` na linha 72, somando as 24 páginas de wiki.

**Implementação:** Nenhuma nesta entrega. A tabela já existe e a skill pessoal não é distribuída.

---

### D4 — A rota se constrói em duas etapas: tabela sintoma→página primeiro, citação da página na elaboração de cada regra depois, dentro da issue #73

**Tipo:** Deliberadamente fora deste repositório.

**Motivo (do plano, achado 2):** D4 pede citação da página "na elaboração de cada regra", isto é, dentro de `skills/rainforest-mind/references/regra-NN.md`. Esses arquivos são **distribuídos a terceiros** — é o motivo de D2 existir. Gravar o caminho de uma página de wiki ali entrega caminho morto a toda instalação de terceiro e expõe a taxonomia de notas pessoais do dono dentro de um plugin público: exatamente o vazamento que D2 nomeia.

**Confirmação:** `grep -c "wiki/"` em `references/regra-06.md`, `regra-07.md`, `regra-08.md` e `regra-09.md` devolve **0** nos quatro. A rota inversa já existe, na skill pessoal, que não é distribuída.

**Implementação:** Nenhuma nesta entrega. Fechar a rota das regras que faltam é edição da skill pessoal, fora deste repositório e fora deste plano.

---

### D11 — A metade "fonte e documentação padrão TOTVS" não se constrói: consome-se o MCP hospedado da `tbc-servicos`

**Tipo:** Fora de escopo pelo design.

**Motivo (do design):** A fronteira entre os dois é limpa por origem do dado — o MCP deles indexa produto padrão, documentação e material anonimizado, e nunca toca fonte de cliente; o extrator próprio (tarefa 2) cobre o customizado. Além disso não há acesso de escrita naquela organização e a squad já consome aquilo. Risco aceito e nomeado: é serviço de outra equipe, em VPS único, sem failover nem compromisso de disponibilidade encontrado.

**Implementação:** Nenhuma. O design já a põe fora de escopo.

---

### D12 — A skill `arqueologia` passa a consumir o grafo em vez de reler o fonte, e a escala de confiança ganha um quarto degrau

**Tipo:** Bloqueado até existir grafo de código.

**Motivo (do plano, achado 3):** D12 pressupõe o grafo existindo para a `arqueologia` consumir. O único extrator que este design constrói (D6, tarefa 2) é de **wiki**, não de código; o extrator de código é a frente 2, que o próprio design põe fora de escopo. `skills/arqueologia/SKILL.md:31-34` segue com três degraus — `CONFIRMADO`, `INFERIDO`, `LACUNA` — e o quarto não tem sobre o que se apoiar.

**Implementação:** Nenhuma nesta entrega. Planejar D12 agora seria mandar construir sobre o que não existe.

---

## Pendências nomeadas (não consertar)

Achados que existem mas ficam propositalmente fora do escopo desta entrega, para não transformar tarefa de doc em refactor.

### O `resumo` de cada nó sai igual ao título

CONFIRMADO por inspeção: todos os 24 nós do acervo têm `resumo === titulo`. Origem: o plano nunca disse de onde o resumo vem — é lacuna do plano, não do código. O extrator (tarefa 2) copia o título do frontmatter como resumo, e não há política de preenchimento ou enriquecimento. Quando existir um, a pipeline pode enriquecer.

### O `cli.cjs` usa `<raiz>/.temp` para o grafo intermediário e deixa o diretório para trás

CONFIRMADO por inspeção do código (skills/montar-corpus/cli.cjs:110-164): o temporário é criado em `path.join(raiz, '.temp')` e o diretório não é apagado. O arquivo `grafo-<slug>.json` é apagado (linha 164), mas a pasta `.temp` permanece. Motivo: evitar deixar lixo solto no FS, mas ainda deixando rastreabilidade se o build falhar no meio. Quando o acervo virar artefato reproduzível, a política de limpeza se decide junto com a política de versionamento.

---

## Adenda ao design

Adicionada a seção "Decisões que este plano não constrói" ao final do design, especificando as seis decisões acima e seus motivos. O design permanece íntegro — nenhuma decisão é reaberta nem reexaminada, apenas documentada como "fora de escopo desta entrega" com motivo claro.
