# Fluxo 7 — Design: recibo de colheita

> Status: design · Depende de: fluxo 1 fechado · Origem: contrato validate→deliver do tt-a1i/archify (MIT) — só o contrato; o motor de render não entra
> Escopo pequeno de propósito: um incremento no `fechar`/`colher`, não um script novo grande.

## Problema

Hoje o `colher` encerra o fluxo com a decisão gravada, mas o **artefato entregue** não tem identidade verificável. Semanas depois, não há como saber se o arquivo em disco é o mesmo que passou pelos portões — edição posterior, merge, ou regeneração silenciosa são indistinguíveis da entrega original.

O archify resolve isso com um contrato de entrega que vale copiar inteiro (o resto do projeto — 11 mil linhas de renderer SVG — não é o nosso problema):

1. Exit não-zero **nunca pode ser descrito como sucesso**. Sem exceção, sem "quase passou".
2. A entrega congela os bytes: lê a spec uma vez, valida esse snapshot exato, e só então commita — atomicamente.
3. O recibo prova identidade: SHA-256 + contagem de bytes de cada entregável, gravados no fechamento.
4. O recibo declara o que ele **não** prova: checagem automática nunca vira alegação de revisão humana ("visualReview: pending" no original). Recibo honesto lista o que ficou pendente.

## Desenho

### Onde entra

No `estado.cjs`, no caminho do `colher` (e opcionalmente no `fechar` de cada estágio que produz artefato). Não é script novo — é ~80 linhas dentro do que já existe, usando `crypto` nativo.

### O manifesto de entregáveis

O `plano` (ou o `fechar` do `executar`) declara os entregáveis do fluxo — lista de caminhos relativos. Sem declaração, o `colher` funciona como hoje (retrocompatível). Com declaração:

```
node scripts/estado.cjs colher
```

passa a:

1. Verificar que cada caminho declarado existe. Ausente = exit 1, colheita negada, mensagem nomeando o arquivo.
2. Se o fluxo 6 estiver ativo e houver `portoes.md`: exigir `portoes.cjs rodar` com exit 0 **imediatamente antes** de congelar — o recibo referencia essa execução, não uma de ontem.
3. Calcular SHA-256 e bytes de cada entregável.
4. Gravar `\.rainforest/colheita/<fluxo>-recibo.json` com escrita atômica.

### Formato do recibo

```json
{
  "fluxo": "6-portoes",
  "colhido_em": "2026-08-30T14:22:00-03:00",
  "entregaveis": [
    { "caminho": "scripts/portoes.cjs", "sha256": "…", "bytes": 14211 }
  ],
  "portoes": {
    "arquivo": "docs/rainforest/fluxos/6/portoes.md",
    "cumpridos": 5, "abandonados": 0,
    "fingerprint_execucao": "…"
  },
  "nao_provado": ["revisao visual", "comportamento em producao"]
}
```

O campo `nao_provado` é obrigatório e nunca vazio — é a tradução do `visualReview: pending`. Um recibo que alega provar tudo é suspeito por construção.

### Verificação posterior

```
node scripts/estado.cjs recibo <fluxo>          # mostra o recibo
node scripts/estado.cjs recibo <fluxo> --conferir  # re-hasheia e compara. exit 0 = intacto, 1 = divergiu
```

`--conferir` responde a pergunta que motivou o fluxo: "esse arquivo ainda é o que foi colhido?" — e vira munição para o `/saude`, que pode conferir os recibos das últimas N colheitas e apontar entregável que divergiu sem novo fluxo.

### A regra que sobe pro núcleo

Uma regra nova no SKILL.md (candidata a regra 18), curta e mecânica:

> **Exit não-zero nunca é descrito como sucesso.** Nem "passou com ressalvas", nem "falhou só o opcional". O número é a verdade; a prosa se ajusta a ele.

Isso já é o espírito das 17, mas explicitar fecha a brecha da narração otimista sobre um exit 1.

## O que NÃO entra

- Snapshot privado + render do snapshot (o archify precisa porque renderiza; o rainforest só entrega arquivos que já existem — hash direto basta).
- `visual-check` com Chrome via DevTools. Ideia boa, dependência pesada; se um território de frontend nascer, revisitar.
- Recibo por estágio intermediário. Começar só no `colher`; se o custo se pagar, estender ao `fechar`.

## Portões deste fluxo (esboço)

- P1: colheita com entregável ausente sai com 1 e não grava recibo.
- P2: recibo gravado re-hasheia limpo com `--conferir` (exit 0).
- P3: alterar 1 byte do entregável faz `--conferir` sair com 1 nomeando o arquivo.
- P4: fluxo sem manifesto colhe como hoje (retrocompatibilidade, exit 0).
- P5: recibo com `nao_provado` vazio é rejeitado na gravação (exit 2).

## Pergunta aberta

- **P1:** onde o manifesto de entregáveis é declarado — campo no arquivo de estado do fluxo, seção no plano, ou bloco no `portoes.md`? Claude Code decide pelo que gera menos formato novo.
