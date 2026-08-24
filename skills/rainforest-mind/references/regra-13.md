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
