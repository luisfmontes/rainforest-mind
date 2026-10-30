# O incidente que fez o pronto quando nomear a entrada real

Movido de `skills/plano/SKILL.md`, seção "`pronto quando:` nomeia a ENTRADA REAL, não a bateria", em 2026-10-30, para abrir folga no teto de 16 KB da skill.

> 2026-08-19: as 13 tarefas de um plano tinham `pronto quando:` na forma
> "`bash <bateria>` sai 0". A entrega passou por **10 baterias verdes**, por
> validação por mutação feita à mão, e pelo `conferir-entrega.cjs` com exit 0 —
> e o subsistema estava **morto em produção**: o hook lia `evento.project`, um
> campo que o harness nunca envia, e as baterias só passavam porque
> **injetavam esse campo à mão** no JSON de teste. Três formas do mesmo defeito
> num dia só: teste que certifica um no-op (a função tinha um `if` de corpo
> vazio e o teste verificava que nada mudava); payload que a produção nunca
> produz; e fixture com schema inventado — os transcritos de teste ganharam os
> campos `tipo`/`conteudo` que o código esperava, e o transcrito real do Claude
> Code não tem nenhum dos dois. O denominador não é descuido de quem escreveu.
>
> O agravante: a armadilha estava documentada **dentro do próprio repositório**
> (`referencias/2026-08-11-everything-claude-code.md:131`), incluindo o
> mecanismo pelo qual a suíte não pega. O repo documentou e caiu nela.

