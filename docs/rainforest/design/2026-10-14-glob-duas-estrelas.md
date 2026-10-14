# conferir-entrega: `--escopo` com a mesma regra de glob do creep (#518)

## Objetivo
O `--escopo` do `conferir-entrega` recebe os `arquivos:` do plano e hoje converte `**` em `.[^/]*`, que casa só um nível de pasta: `arquivos: src/**` recusa `src/a/b.txt` como "fora do escopo". O mesmo plano passa no `creep` (`conferir-fluxo.cjs`, via `globMatches` de `scripts/lib/camadas.cjs`), que trata `**` certo. O conserto faz os dois lerem `arquivos:` do mesmo jeito.

## Decisões fechadas
- **D1 — Alinhar à regra do `globMatches`, não só consertar o `**`** — porquê: os dois instrumentos leem o mesmo `arquivos:`; divergência entre eles é a classe do defeito, não só o `**`. Isso traz junto: barra no fim (`scripts/fixtures/x/`) cobre tudo abaixo da pasta, e o resto das regras do `globMatches` (literal sem curinga é igualdade; `*` e `?` não cruzam `/`). (Luís, Q1: recomendado.)
- **D5 — O `globMatches` passa a ancorar sempre (`^` e `$`), para que `*` e `?` nunca cruzem `/`, e vale para o `creep` também** — porquê: o executor da tarefa 1 mediu que `globMatches` só ancora o fim quando o glob não termina em `*` (e o início quando não começa em `*`), então `src/*` casava `src/a/b.txt` e `*.md` casava `docs/x.md`: a premissa de D1 era falsa para a régua escolhida. Nos planos existentes, o único glob terminado em `*` simples (`scripts/fixtures/critica-do-revisor/*`) cobre pasta de um nível só, então nenhum plano antigo quebra. (Luís, emenda de 2026-10-14: recomendado (a), contra (b) aceitar o prefixo e (c) glob próprio só no `conferir-entrega`.)
- **D2 — `a/**/b` continua sem casar `a/b` (zero pastas)** — porquê: o `creep` também não casa; mudar só aqui criaria divergência nova. Se fizer falta, muda nos dois juntos. (Luís, Q2: recomendado.)
- **D3 — O `.cjs` reaproveita `globMatches` de `scripts/lib/camadas.cjs`; o gêmeo `.py` porta o mesmo algoritmo** — porquê: uma fonte só para o Node; o `.py` não pode importar Node, e a bateria já roda contra os dois gêmeos (`CONFERIR=...py`), o que mantém a porta honesta. A normalização atual do `conferir-entrega` (contrabarra vira `/`, minúsculas em caminho e glob) fica.
- **D4 — Bateria de dois lados com mutação** — porquê: critério de pronto da #518. Casos novos em `scripts/testa-conferir-entrega.sh`: `src/**` aprova arquivo dois níveis abaixo; pasta com barra final aprova arquivo dentro dela; `src/*` continua recusando dois níveis; arquivo fora continua recusado. Rodando contra `.cjs` e `.py`.

## Avaliado e descartado
- Consertar só o `**` (texto da issue): deixa a barra final divergente do `creep`, o mesmo defeito em outra forma.

- Glob próprio só no `conferir-entrega` (opção c da emenda D5): os dois voltariam a divergir.
- Aceitar `src/*` como prefixo de qualquer profundidade (opção b da emenda D5): mais frouxo que o glob que todo mundo conhece.

## Fora de escopo
- `**` casando zero pastas (D2).
- Unificar `globMatches` com outros casadores do repo além destes dois.

## Varredura
docs/rainforest/varredura/2026-10-14-glob-duas-estrelas.txt — só os dois gêmeos têm `globToRegex`; o `creep` usa `globMatches`. Mudou: confirmou que o gêmeo `.py` tem o mesmo defeito e entra no conserto.

## Em aberto
