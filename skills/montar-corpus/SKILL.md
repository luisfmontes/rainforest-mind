# montar-corpus

Constrói acervo em markdown a partir de um corpus de wiki em versão de controle.

## O que faz

A skill encadeia três estágios para criar um banco de conhecimento navegável:

1. **Extrator**: lê cada página de wiki, identifica ligações (`[[página]]` e `relacionados:`) e emite um grafo em JSON
2. **Validador**: confere se o grafo respeita o schema (nós e arestas bem formados)
3. **Build**: consome o grafo e escreve um acervo em markdown, com uma nota por conceito e um índice de rota

O acervo se grawa em `<raiz>/acervo/<corpus>/`, onde `<raiz>` é a que `resolverRaiz` encontra e `<corpus>` é o slug do projeto em `projetos.json`.

## Uso

```bash
node skills/montar-corpus/cli.cjs --corpus segundo-cerebro
```

Ou com raiz customizada:

```bash
RFM_ROOT=/caminho/para/dados node skills/montar-corpus/cli.cjs --corpus segundo-cerebro
```

## Flags

### `--corpus <slug>`

Obrigatório. Nome do corpus em `projetos.json`, sob forma de slug (kebab-case). Exemplo: `segundo-cerebro`, `wiki-minima`.

Se o slug não existir em `projetos.json`, a skill recusa.

### `--repo <caminho>`

Opcional. Caminho do repositório que contém o corpus. Se omitido, usa `CLAUDE_PROJECT_DIR` ou o cwd.

## Resolução de caminhos

### Alvo (corpus)

Usa `resolverSlug` de `hooks/lib/projetos.cjs`. Busca o slug em `projetos.json` dentro de `<raiz>/projetos.json`.

### Raiz de dados

Usa `resolverRaiz` de `hooks/lib/raiz.cjs`. Ordem:

1. `RFM_ROOT` (env var explícita)
2. `<projeto>/.rainforest` (por projeto)
3. `~/.rainforest` (global do usuário)
4. Raiz do plugin (auto-hospedagem)

Quando nenhum nível existe, a skill recusa.

## Validação

Sem `--corpus`, recusa com mensagem mencionando `--repo` e `--corpus`.

Corpus ausente em `projetos.json`: recusa nomeando o slug.

Grafo inválido (nó fora do enum, aresta mal formada): recusa com o campo nomeado.

## Dependências externas

Nenhuma no estágio de wiki. O validador não usa biblioteca JSON Schema — é Node puro.

Se um extrator futuro precisar de ferramenta externa, a conferência aqui a nominará e recusará a execução sem instalar.

## Estrutura do grafo

- **nó**: `id`, `caminho`, `titulo`, `resumo`, `file_type` (`code|document|paper|image|rationale|concept`), `confidence` (`EXTRACTED|INFERRED|AMBIGUOUS`)
- **aresta**: `de`, `para`, `tipo`, `via`, `confidence` (opcional)

Ver `skills/montar-corpus/schema/grafo.schema.md`.

## Arquivos produzidos

```
<raiz>/acervo/<corpus>/
├── INDEX.md          # Rota de entrada com lista de nós e arestas
├── conceito-a.md     # Uma nota por nó
├── conceito-b.md
└── ...
```