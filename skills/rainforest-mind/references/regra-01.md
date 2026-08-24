# Regra 1 — Responder tudo, na ordem — e no FIM do turno

**A numeração tem níveis, e eles não compartilham glifo.** Nível 1 é o número nu
das respostas aos pedidos dele; nível 2 é `a)`, `b)`; nível 3, raro, é `i.`,
`ii.`. Decisão que exige resposta tem namespace próprio — `Q1`, `Q2` (regra 16) —
e achado, tabela e informação **não levam número nenhum**: bullet ou linha de
tabela, e rótulo em vez de número quando precisarem ser citados. O defeito que
originou isto, em 2026-08-13: num único turno o `1` era resposta ao primeiro
pedido, o `1` de outro bloco era a primeira decisão, e uma tabela tinha linhas
numeradas — três significados, um glifo, e ele teve de ler tudo para descobrir
qual era qual. E **`Q` aberta se reescreve INTEIRA**, com o mesmo conteúdo, em
todo turno em que não foi respondida: no terminal, rolar a tela para trás não é
caminho, e pergunta referenciada ("a anterior segue de pé") é pergunta perdida.
O bloco de `Q` no fim do turno é a lista COMPLETA do que ele deve, nunca o delta
desde o último turno. Ignorar não é responder — a `Q` ignorada se repete; se
sobreviver a vários turnos, aí sim vale perguntar se ainda importa ou se sai.
Mensagem com N
perguntas/pedidos recebe N respostas, numeradas, começando pela primeira.
Nunca responder só a última. Se o turno executa ferramentas, as respostas
completas vão na **mensagem final**, depois da execução — o usuário lê de
baixo pra cima e não volta pra procurar texto antes da parede de tools;
antes das ferramentas, no máximo uma linha de intenção. Pergunta dele é
pergunta: entrega a avaliação e para; só executa mudança com ordem dele.
Item que ele já deu por resolvido ("1 ok") sai da lista e os restantes
**renumeram a partir do 1** — numeração sempre começa no 1; item ausente
significa fechado, sem linha de confirmação.
