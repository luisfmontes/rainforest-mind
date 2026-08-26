# Regra 3 — Radar de escopo

Existe um foco **ativo** (FOCO.md na raiz deste repo,
injetado no início da sessão, com critério de pronto e avanços datados).
O desvio é medido **só contra o ativo** — as frentes e compromissos listados
no arquivo não disparam aviso; existem para a troca ser barata (`/foco
trocar`). Quando a conversa sai do ativo, sinalizar em uma frase, sem
julgamento, com escolha: "Estávamos em [foco], isso é [outro tema] — seguimos
nele ou planto e voltamos?" Se a sessão abriu numa pasta/tarefa de **outra
frente**, não brigar: oferecer a troca de foco em uma linha.
**Todo foco tem natureza — `[trabalho]` ou `[pessoal]`, marcada no FOCO.md — e
o radar de um foco de trabalho não cobra em tempo pessoal. Pessoal inclui
estudo: trilha, curso ou pós-graduação contam como contexto pessoal para este
filtro, mesmo que o FOCO.md nomeie essa frente separadamente e mesmo sem a
palavra "pessoal" aparecer no pedido.** São dois filtros,
e o aviso só sai se passar nos dois: *quando* (fora do expediente — fim de
semana, feriado, jornada fechada pelo mesmo sinal que a regra 8 já lê — foco
de trabalho não dispara nada) e *qual* (em contexto pessoal o desvio se mede
contra o foco pessoal ativo, se houver; não havendo, não se mede). Assunto
declaradamente pessoal vale como contexto pessoal mesmo em dia útil, e
trabalho no sábado por escolha dele continua valendo — o filtro é sobre o
que o usuário está fazendo, não sobre o calendário sozinho. Tempo pessoal pede
*menos* radar, não mais.

> 2026-08-08 (sábado): a abertura cobrou desvio contra um foco de trabalho
> com prazo enquanto ele levava livros para o segundo cérebro, e ele
> corrigiu na mão.

Na abertura,
se um compromisso com prazo estiver vencido ou a ≤2 dias, avisar em uma
frase; se o foco ativo estiver sem avanço datado há 7+ dias, nomear isso
uma vez.

**Na abertura, e só nela.** No fecho de sessão a linha de prazo não se emite em
hipótese nenhuma, nem como lembrete acrescentado por conta própria — no fim do
turno não há o que fazer com um prazo, só o que sentir.

> 2026-08-11: no fechamento de uma sessão longa, depois de ele já ter respondido
> "não" para a pergunta de observações da regra 13, um lembrete do prazo de sexta
> foi acrescentado por iniciativa própria. A janela do foco estava ativa ao lado,
> e o radar do mesmo turno já dizia isso.

Sessões em paralelo mudam como este radar mede — regra 17: sessão ativa no
projeto do foco deixa o radar **desta** janela leve, porque paralelo é escolha
dele. **Isto é checagem obrigatória antes de qualquer aviso desta regra sair —
a frase de desvio e a linha de prazo —, não nota de contexto para ler
depois.** O que ela decide, porém, é diferente para cada um: a frase de desvio
**não sai**; a linha de prazo **sai**, como nota de que o foco está sendo tocado
naquela janela, nunca como cobrança dirigida a esta. O hook diz as duas coisas
na mesma diretiva — não é julgamento seu. Leia a lista de sessões inteira (`sessoes.json`, injetada na
abertura): um resumo como "+N janela(s) em outra(s) pasta(s)" não é prova de
que não há sessão do foco entre elas, é convite para abrir a lista antes de
cobrar. O casamento é por raiz de pasta/worktree, não por igualdade de string
— o foco é nome ("Template ABAPA"), a sessão é caminho
(`...\worktrees\gestao-projetos-template`). "Ativa" inclui a janela
**esperando o usuário** dentro da ociosidade máxima do foco, não só a que está
processando neste instante. Havendo sessão assim, a frase de desvio não sai.

> Quatro reincidências do mesmo furo, entre 2026-08-10 e 2026-08-22: o radar
> cobrou desvio, ou emitiu linha de prazo, com a janela do foco trabalhando ao
> lado. Nas quatro a informação estava na injeção da própria abertura — o que
> faltou foi a ordem (checar antes de falar), o casamento por raiz em vez de
> nome, e não tratar o resumo "+N janelas" como prova de ausência.
