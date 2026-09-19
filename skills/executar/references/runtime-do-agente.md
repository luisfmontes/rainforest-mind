# Runtime do agente: em que host o briefing vai rodar

A primeira linha do briefing pode ser `Runtime: codex`, para despachar via Codex
CLI, ou `Runtime: claude`, que é o default quando a linha não aparece. Quem lê
essa linha é `hooks/portaria.cjs`, e ela é de **primeiro-encontro**: vale a
primeira ocorrência, ao contrário da linha `Sensor:`, em que todas contam (ver
`sensor-no-briefing.md`, e a D18 do design de 2026-09-14).

## Com `Runtime: codex`, o briefing leva o bloco de ponte

O briefing carrega junto o bloco de ponte de
`rainforest-mind/references/regra-10-runtime.md`. Isso não é zelo: medido em
2026-09-08, **o preâmbulo do agente sozinho não segurou um haiku** — o modelo
saiu do método que o agente descrevia. O bloco de ponte é o que segura.

## O que NÃO muda com o runtime

`scripts/conferir-entrega.cjs` é indiferente ao host: ele confere o **worktree
real** — o que foi escrito, em que branch, sobre que base — independentemente de
qual CLI correu o agente. É o mesmo princípio da regra 12: a entrega se valida
na saída real, nunca no relato de quem a produziu, e muito menos na identidade
de quem a produziu.
