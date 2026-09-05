# Schema de Grafo — Nós e Arestas

## Forma do Grafo

O grafo é um JSON com dois arrays de topo: `nos` e `arestas`. Cada nó representa uma entidade (página, conceito, código, artigo, imagem); cada aresta representa uma relação entre dois nós.

### Nó

Um nó tem os campos obrigatórios:

| Campo | Tipo | Descrição | Valores válidos |
|---|---|---|---|
| `id` | string | Identificador único do nó | qualquer string não-vazia |
| `caminho` | string | Caminho relativo da fonte | qualquer string não-vazia |
| `titulo` | string | Título ou nome curto | qualquer string não-vazia |
| `resumo` | string | Resumo ou descrição breve | qualquer string não-vazia |
| `file_type` | string | Tipo de arquivo ou conteúdo | `code`, `document`, `paper`, `image`, `rationale`, `concept` |
| `confidence` | string | Nível de confiança na extração | `EXTRACTED`, `INFERRED`, `AMBIGUOUS` |

### Aresta

Uma aresta tem os campos obrigatórios:

| Campo | Tipo | Descrição | Valores válidos |
|---|---|---|---|
| `de` | string | ID do nó de origem | ID de um nó existente no grafo |
| `para` | string | ID do nó de destino | ID de um nó existente ou referência externa |
| `tipo` | string | Tipo de relação | qualquer string não-vazia |
| `via` | string | Mecanismo da relação (como foi encontrada) | qualquer string não-vazia |

## Exemplo

```json
{
  "nos": [
    {
      "id": "conceito-1",
      "caminho": "wiki/conceito-1.md",
      "titulo": "Conceito Principal",
      "resumo": "Este é um conceito importante no sistema.",
      "file_type": "concept",
      "confidence": "EXTRACTED"
    },
    {
      "id": "codigo-2",
      "caminho": "src/utils.js",
      "titulo": "Utilitários de Sistema",
      "resumo": "Funções auxiliares para o núcleo.",
      "file_type": "code",
      "confidence": "EXTRACTED"
    },
    {
      "id": "artigo-3",
      "caminho": "papers/estudo-2026.pdf",
      "titulo": "Estudo de Fundações",
      "resumo": "Análise de padrões arquiteturais.",
      "file_type": "paper",
      "confidence": "INFERRED"
    }
  ],
  "arestas": [
    {
      "de": "conceito-1",
      "para": "codigo-2",
      "tipo": "implementa",
      "via": "referenced-in-code"
    },
    {
      "de": "conceito-1",
      "para": "artigo-3",
      "tipo": "fundamenta-se-em",
      "via": "markdown-link"
    }
  ]
}
```

## Validação

Um grafo é válido quando:

1. É um objeto JSON válido com exatamente dois campos de topo: `nos` e `arestas`.
2. `nos` é um array de nós, cada um com todos os campos obrigatórios.
3. `arestas` é um array de arestas, cada uma com todos os campos obrigatórios.
4. Cada campo de cada nó e aresta é do tipo esperado (string).
5. `file_type` só pode ser um dos valores no enum: `code`, `document`, `paper`, `image`, `rationale`, `concept`.
6. `confidence` só pode ser um dos valores no enum: `EXTRACTED`, `INFERRED`, `AMBIGUOUS`.
7. Valores vazios ou `null` tornam o grafo inválido.
