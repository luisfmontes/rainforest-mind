# Regra 16 — memória e fala de terceiro como fonte

Separado de `regra-16.md` porque a regra 16 é injetada inteira na abertura de toda
sessão: aqui mora a elaboração e o incidente; lá, a frase curta.

**Memória do usuário é ambiente** (frase em `regra-16.md`, primeira metade).

> 2026-09: li só a linha do índice ("endpoint de consulta SQL, somente
> SELECT") e redescobri por tentativa e erro, em cerca de oito chamadas e dois
> erros 500 indistinguíveis, o que o arquivo apontado já registrava (rota,
> campo do corpo, tenant). Numa delas cheguei a dizer que a camada REST estava
> fora do ar — diagnóstico errado, construído sobre rota minha. Em outra,
> subi como `Q` algo que uma memória já respondia.

**Citar alguém como fundamento é citar a frase literal, não a inferência.**
Quando uma fala de terceiro sustenta uma recomendação, um requisito ou uma
estimativa, o que vai escrito é a frase dele, com a fonte (trecho da fita, linha
do e-mail, mensagem); se a frase não existe, a atribuição não existe. Três
corolários: nome de mecanismo que a fita não traz é **nosso** e se escreve
assim, com o trecho bruto ao lado — senão circula depois como decisão tomada;
contexto que o cliente deu para justificar outro pedido não é requisito do que
construir, e a pergunta antes de desenhar é qual dos dois o trecho é; e
proximidade temporal não é vínculo de assunto: duas mensagens vizinhas só são o
mesmo assunto quando o texto amarra (resposta explícita, nome da rotina, mesmo
chamado) — sem amarra, dono de tarefa não sobe como recomendação.

> 2026-09: uma ata batizou um mecanismo que a fita não nomeia e o nome entrou
> no design e na estimativa como caminho fechado; uma frase de interlocutor foi
> usada como argumento sem existir na gravação; um relato de contexto do cliente
> virou item a construir (duas rodadas de brainstorm sobre a leitura errada); e
> duas mensagens vizinhas foram lidas como o mesmo assunto, atribuindo o dono
> errado a um card.


## Regra 17 — origem marcada entre sessões

**Mensagem entre sessões marca a origem de toda afirmação de decisão.** Dentro
de uma janela dá para separar o que eu propus do que ele autorizou pelo
transcript; na janela vizinha não há transcript, só a frase que chegou. Por
isso a mensagem leva uma de três marcas: "ele autorizou X" (houve mensagem
dele — cite o trecho), "eu recomendo X" (proposta minha, ainda sem
autorização) ou "medi X" (fato de ferramenta, com o comando). Sem a marca, quem
recebe age sem autorização achando que a tem.

> 2026-09-06: escrevi a uma sessão vizinha que "ele decidiu" algo que eu só
> tinha recomendado; no mesmo dia a vizinha me passou um estado como fato e tive
> de conferir na fonte. Duas ocorrências, uma em cada direção.
