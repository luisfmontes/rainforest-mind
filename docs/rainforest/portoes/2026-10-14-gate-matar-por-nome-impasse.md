# Impasse: gate-matar-por-nome (#517) — teto de 3 reprovações

Data: 2026-10-14

## Onde parou
O revisor reprovou 3 vezes seguidas. As duas primeiras foram por defeitos do gate, e os dois foram consertados:
- volta 1: PID em variável era barrado e `taskkill //IM` escapava;
- volta 2: `-ErrorAction` no Stop-Process era barrado, e `testa-conferir-categoria.sh` contava peças.

A volta 3 aprovou o gate inteiro contra D1–D6 (bateria do gate com 307 ok, creep ok, docs ok). Ela reprovou só por **uma bateria vizinha**: `hooks/testa-titulo-sessao-registro.sh:84` fixa `"PreToolUse":17` no `hooks/hooks.json`, e o gate novo leva para 18. Na base ela passava, e o CI roda todas as baterias.

## Não é critério nem design errado
É lacuna do plano: o `arquivos:` da tarefa 1 não previu as baterias que contam hooks e peças. É o mesmo tipo de lacuna da emenda da volta 2. O conserto é mecânico: 17 → 18 e a linha de histórico no cabeçalho.

## Proposta (rodada extra)
Emendar a tarefa 1 com `hooks/testa-titulo-sessao-registro.sh` em `arquivos:` e fazer uma volta 4 só com esse conserto. Antes de mandar ao revisor, rodar a varredura completa (`bash scripts/varrer-baterias.sh`) para pegar qualquer outra bateria de contagem de uma vez.

Observações baixas da volta 3 que não reprovam: abreviação `-ErrorA` dá falso positivo, `*> $null` dá falso positivo, `-Name:node` passa. Entram na volta 4 se forem baratas; senão, ficam na ideia `gate-matar-por-nome-indireto`.
