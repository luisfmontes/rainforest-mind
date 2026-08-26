# Regra 13 — Correção sua vira observação registrada

O plantio da regra 6 depende
do usuário nomear a ideia; este registro é o inverso — o gatilho é **ele
corrigir**. Quando o usuário redireciona a saída, repete um pedido que já tinha
sido atendido, ou aponta que uma regra devia ter disparado e não disparou,
isso é sinal de regra pouco clara ou ausente: gravar uma observação com
`"tipo": "observacao"`, `contexto` = o que aconteceu na sessão (com data), e
`ao_colher` = a mudança de regra proposta.

**Quem grava é o `node scripts/ideias.cjs plantar` (JSON pela entrada padrão),
nunca a mão no arquivo.** Esta frase não estava aqui até 2026-08-14, e a
ausência dela produziu o defeito exato que se esperaria: em 2026-08-14 uma
sessão escreveu direto no `ideias.jsonl` uma linha com `tipo`, `contexto` e
`ao_colher` — os três campos que este parágrafo citava — e **só** eles. Sem
`id`, sem `titulo`, sem `descricao`, com `data` no lugar de `plantada_em` e
projeto fora do vocabulário. O `conferir` passou a recusar o arquivo inteiro
por causa dela, e as outras 125 linhas ficaram reféns de uma. A prova de que
não passou pelo script é que o `plantar` grava um backup a cada escrita e não
existe backup do estado intermediário.

A regra 6 já nomeava o gravador ("quem grava é o `/ideia`"); esta não nomeava,
e era a única das duas que descrevia campos soltos sem dizer por onde entram —
o que se lê como instrução para editar o arquivo. Regra que enumera campo sem
nomear o comando convida exatamente isso. Vale a regra 17: estado compartilhado
se escreve por script.

 **Silencioso
por padrão**: registra e segue a tarefa — sem anunciar o registro no meio do
trabalho (regra 7). Só sobe na hora se a correção mudar o que está sendo
feito agora. Quem fecha o ciclo é a regra 5 (fim de sessão) e o jardineiro
de sexta, nunca uma interrupção. Sem isso, só vira regra o que o usuário teve o
trabalho de notar e nomear — as regras 11 e 12 nasceram assim, e custaram
uma sessão inteira de prejuízo antes de alguém escrever. Mecânica adotada da
task-observer, de Eoghan Henn (rebelytics.com, CC BY 4.0): o gatilho e o
ciclo de revisão, **não** o log paralelo — aqui a observação mora no mesmo
`ideias.jsonl`, um lugar só pra olhar.

**Antes de gravar, decidir se a correção revelou MÉTODO ou FATO.** Correção de
método (jeito de fazer que muda o futuro) vira observação aqui, com `ao_colher`
de verdade. Fato durável sobre o ambiente (o que um serviço faz, não o que
fazer sobre ele) não tem `ao_colher` real e não pertence ao `ideias.jsonl` — vai
para a memória da sessão ou para o `CLAUDE.md` do repositório em questão. Teste
de uma frase: existe ação futura que isso destrava? Não existindo, não é ideia.
Episódio misto separa em dois registros, cada metade no seu lugar — nunca
espremer o fato dentro de um `ao_colher` inventado para preencher o campo.

> 2026-08-14: uma linha escrita à mão no `ideias.jsonl` misturava fato ("o REST
> volta sozinho em até 2 min") com método ("checar o ciclo normal antes de
> afirmar falha"). Convertê-la preservando as duas dentro de uma observação foi
> tratar de FORMA um problema de CATEGORIA: o fato não pertencia ali em forma
> nenhuma.

**Observação prescrita três vezes sem `colhida_em` é sinal de trava ausente,
não de disciplina fraca.** Registrar de novo o mesmo `ao_colher` não fecha o
laço: se uma checagem barata já foi prescrita em duas observações anteriores e
nenhuma foi colhida, a terceira repetição vira mecanismo verificável por
máquina, não mais uma linha no arquivo. E observação de **método** — que vale em
qualquer pasta — não se arquiva sob a pasta onde por acaso apareceu: `projeto` é
campo obrigatório, e o valor para ela é `solta` — o slug de ideia sem projeto,
o único que nasce com `caminho: null`. O motivo é **categoria**, não
visibilidade: hoje `projeto` quase não decide onde a observação reaparece, e
escrever o contrário seria inventar mecanismo. A injeção de abertura não lê o
`ideias.jsonl`; o jardineiro de sexta mostra observação independente do campo. O
que `solta` muda de fato é o agrupamento do `listar` e o recorte do
`listar --projeto`. Reaparecimento por sessão é mecanismo que ainda não existe —
está plantado, não escrito aqui como se existisse.

> 2026-08-26: uma revisão pegou este parágrafo prescrevendo "fica marcada como
> transversal" — mecanismo que não existe em lugar nenhum do plugin. As saídas
> possíveis eram registrar `transversal` como slug de projeto, poluindo o
> vocabulário controlado, ou escrever o campo à mão, violando a linha 11 desta
> mesma regra. A correção trocou por `solta`, que existe — e manteve uma
> justificativa que também não se sustentava ("arquivar sob um repositório a
> esconde das sessões onde precisa reaparecer"), derrubada na apuração seguinte
> do mesmo dia: 58 das 62 observações abertas estão sob um projeto, 40 sob
> `rainforest-mind`, e nenhuma delas reaparece ou deixa de reaparecer por causa
> disso. Duas rodadas para o mesmo parágrafo. Prescrição não vale por ser
> sensata, e justificativa não vale por ser plausível: as duas valem quando a
> ferramenta real as executa.
