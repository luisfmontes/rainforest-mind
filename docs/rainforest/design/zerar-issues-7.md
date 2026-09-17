# Zerar as Issues abertas, rodada 7 — rota com emoji por etapa (#299)

## Objetivo
Dar à regra 4 um formato de acompanhamento que mostre o estado de cada etapa de
relance — a rota re-renderizada a cada checkpoint, com emoji de status e
numeração estável — sem gastar o orçamento do núcleo injetado na abertura.

## Decisões fechadas
- **D1 — O formato mora na elaboração `references/regra-04.md`; o núcleo só ganha o marcador `<!-- detalhe -->` + `Elaboração:` (vira ↳ na injeção)** — porquê: o núcleo é fixo e cada byte dele sai do foco, que já é cortado hoje; 93 B na regra 6 quebraram fixture na rodada 6.
- **D2 — A cada checkpoint a rota inteira é re-renderizada, com as linhas ✅ reduzidas ao rótulo** — porquê: é o ganho que a issue nomeia (passado, presente e futuro sem rolar a tela) e rota de 3–7 etapas cabe em poucas linhas.
- **D3 — Quatro estados: ✅ feito · 🔄 rodando · ⏳ não começou · ❌ reprovado/bloqueado** — porquê: o fluxo tem status `reprovado`; sem ❌ a etapa falha aparece como ✅ ou ⏳, mentira de relance.
- **D4 — A ressalva da numeração estável (etapa não renumera, ao contrário da regra 1) fica em `regra-04.md` junto do formato e em uma linha em `regra-01.md`** — porquê: quem lê só a regra 1 renumera por padrão; a exceção precisa estar nos dois lados.
- **D5 — Uma linha no item 3 do `modo-dev` liga a rota planejada (`→ verifica:`) ao acompanhamento com emoji** — porquê: é a mesma lista em dois momentos, custa uma linha.
- **D6 — Versão 1.19.1 no `plugin.json` e no badge do README** — porquê: muda texto de regra entregue ao usuário; patch porque nenhum comportamento de hook ou script muda.

## Avaliado e descartado
- Formato no texto do núcleo: descartado pela medição do orçamento (`TETOS.ORCAMENTO_BYTES` em `hooks/lib/contexto-sessao.cjs`; foco já cortado na abertura de 2026-09-17).
- Só "o que falta" no checkpoint (como na sessão de origem): perde o passado da rota, que é o que obriga a rolar a tela.

## Fora de escopo
- Mudar a frase "Fechamos [n]/[total]" do núcleo além do marcador — o texto da regra fica.
- Aplicar o formato por código (hook ou trava): é regra de conversa, não de artefato.

## Em aberto
