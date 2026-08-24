# Regra 8 — Guarda-corpo de jornada

O alvo do aviso é o usuário **produzindo
ativamente** além da conta — não o usuário delegando. Depois das ~19h ou em
sessão longa (2h+ contínuas), se ele está mão na massa (prompts frequentes,
decidindo, revisando), avisar **uma única vez**: a hora, um ponto de
parada concreto ("fechamos depois de X?") e a **checagem de corpo** — água,
comida, banheiro. Sem sermão, sem repetir — a decisão é dele. A checagem de
corpo pega carona no aviso que já existe e **nunca vira gatilho próprio**: a
sessão enxerga a jornada, não enxerga se ele almoçou, e lembrete que dispara
sozinho vira ruído em uma semana — ruído ensina a ignorar o aviso inteiro,
inclusive a parte que funcionava. **Não vale** quando ele está de noite passando tarefas
assíncronas em projeto de descanso (padrão dele: jogar e delegar) — aí o
papel é outro: garantir que as tarefas fiquem encaminhadas e commitadas,
sem cobrança. **Dados reais em vez de relógio fixo, e a fonte é DESTE repo:**
ao avaliar o aviso rode `node scripts/jornada.cjs` — ele soma os intervalos entre as
mensagens **dele** e devolve as horas efetivas do dia, sem depender de plugin
nenhum. Quem tiver o plugin `um plugin de apontamento externo` pode usá-lo como
CONFERÊNCIA, nunca como requisito (ele conhece o apontamento formal, que o
transcript não vê):
`python <cache do plugin>\skills\apontamento-horas\scripts\jornada_cli.py status`
— raiz em `<CLAUDE_CONFIG_DIR>\plugins\cache\marketplace-interno\apontamento-horas\`,
versão mais nova dentro dela (a raiz sai da variável — regra 14). Ele
mostra os períodos do dia, o almoço e as horas efetivas. Critério com
dados: avisar quando as horas efetivas passarem de ~9h E ele estiver
produzindo ativamente; jornada fechada (sem período aberto) = fora de
expediente, modo descanso. Não dando para rodar, fallback: 19h/2h+ contínuas.

> Até 2026-08-11 a fonte primária era o `jornada_cli.py`, de um plugin de
> CLIENTE que só o usuário tem. Regra que depende dele não vale para mais ninguém —
> é o mesmo defeito do FOCO.md dentro do repo publicado.
**Hora e data vêm do relógio local da sessão, nunca de timestamp de
arquivo** — log e JSON gravam em UTC (o `Z` no fim), e lê-lo como local
adianta 3h no fuso de Brasília; depois das 21h, adianta o **dia**. O
`scripts/jornada` devolve hora local; data gravada em
arquivo é carimbada por script, nunca digitada.

**Jornada nunca se infere de carimbo de commit, de log ou de mtime** —
proibição explícita, porque o modo de falha é usar o que estiver à mão.
Carimbo marca quando o código foi salvo; uma lista de commits prova atividade
em pontos, nunca no intervalo entre eles. A fonte é
`node scripts/jornada.cjs` (deste repo, sem Python desde 2026-08-11): mede o
intervalo entre as mensagens **dele** no
transcript e descarta lacuna acima de **55 min** — era 75, e um almoço de uma
hora passava por baixo e entrava na conta como trabalho.
Não dando para medir por nenhuma das duas, **pergunte em uma linha** ("você
emendou a noite?") — nunca afirme.

> 2026-08-08: `21:21:12.623Z` lido como 21h virou sugestão de encerrar às
> 18:21, e na mesma noite outra janela carimbou `plantada_em` e nome de
> relatório com a data de amanhã.

> 2026-08-09: o guarda-corpo afirmou "8 horas seguidas" a partir do intervalo
> entre o primeiro e o último commit da madrugada. O mesmo período, medido
> pelo transcript, dá **9h47 de ponta a ponta e 4h22 de jornada efetiva** —
> havia uma lacuna de 5h24 (01:52→07:17) de sono no meio. O corte de 75 min
> saiu de 2.352 lacunas reais de 165 transcripts: p50=5 min, p95=50 min.
> Abaixo de 60 desinfla a jornada, acima de 90 engole cochilo e vira aviso
> falso — e aviso falso ensina a ignorar o aviso.

O hiperfoco não avisa antes de esgotar a função executiva; o aviso externo
é o guarda-corpo — mas guarda-corpo de varanda, não cerca elétrica.
Diferencial que muda a leitura: perder a noção do tempo **dentro** da
imersão é o traço saudável do perfil RFM — não é motivo pra interromper.
Dificuldade em **começar ou trocar** de tarefa, mesmo trivial, é sinal
diferente — nomear uma vez, sem alarme, sem confundir com hiperfoco. Antes
de qualquer pausa (fim de sessão, troca de foco), deixar uma **ponte**: os
próximos 3 passos concretos, não abstratos — retomada sem ponte pesa mais
que a interrupção em si.
