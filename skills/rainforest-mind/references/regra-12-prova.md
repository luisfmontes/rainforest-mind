# Regra 12 — a prova mede o defeito

Elaboração dos parágrafos de `references/regra-12.md` que tratam do que uma
prova realmente mede. A regra se aplica pela frase curta que mora lá; aqui
estão as perguntas de leitura e o porquê.

**A prova pode ser verdadeira e medir outra coisa que o defeito.** Comando e
saída colados não bastam. A pergunta de leitura é *"esta saída cairia igual se o
defeito não existisse?"* — a forma barata é nomear qual asserção mudou de lado e
conferir que é a que cobre o conserto (número de asserções derrubadas fora da
faixa esperada é sinal de que a prova mede outro portão). Quatro armadilhas já
vistas: fixture onde o ataque não chega; **controle que também produziria o
efeito sem o hook** (sandbox que impede a escrita de qualquer jeito — ausência
do efeito não prova o bloqueador; pedem-se duas provas: o motivo explícito do
hook e um controle em que a mesma operação teria permissão); prova rodada no
worktree do agente e não na árvore de **destino** (o cherry-pick vem antes da
prova, não depois); e variável de ambiente do lado de quem lê —
`printf '%s' "$P" | VAR=x node hook`, nunca `VAR=x cmd1 | cmd2`, em que `VAR`
vale só para o `cmd1` e o hook cai na raiz real do usuário. Por fim, número que
**contradiz a percepção direta dele** tem a premissa de agregação conferida
antes de ser apresentado: a média de vetores de um grupo misturado não se
parece com ninguém, e um resumo não é observação.

> 2026-09: um conserto de segurança foi dado como provado enquanto o commit
> vivia só no worktree do agente e as provas chamavam a função fora da
> fronteira de isolamento; um critério de plano com a variável antes do cano
> disparou a manutenção contra a raiz real do usuário (nada se perdeu por
> sorte de estado); e uma similaridade média de 0,087 quase fez a janela
> contradizer quem ouviu a pessoa — medindo fala a fala, 14 de 69 falas
> pontuavam 0,70 ou mais.

**Verde em uma máquina só prova uma máquina.** Suíte 100% verde local não é
evidência de nada quando todas as execuções são no mesmo ambiente: a pergunta
não é quantas vezes passou, é **em quantos ambientes**. CI vermelho só no runner
se reproduz localmente antes do próximo push — TMP com nome 8.3, usuário sem
identidade git, fim de linha LF — e a versão **anterior** roda como contraprova,
que tem de falhar igual ao log do CI. Ao diagnosticar, ler a saída da própria
ferramenta antes de propor causa: a hipótese plausível custa um ciclo inteiro.

> 2026-08-17 e 2026-09-04: dois defeitos de produto (um gate barrando commit
> legítimo, uma conferência errada por caminho 8.3) viveram escondidos porque a
> máquina local não tem alias 8.3 e o runner tem; a aposta em identidade git
> ausente custou um push e um run, e o primeiro conserto de outro PR foi
> empurrado sem reproduzir a condição do runner — três pushes até ficar verde.

**Conserto de casamento leva duas mutações.** Regex, glob ou comparação:
desligar o ramo (`if (achou)` virando `if (false)`) prova que o ramo é testado,
não que o padrão é estreito; a segunda mutação **alarga o padrão**, e o fixture
dela sai da reprodução literal do achado, antes de qualquer variação minha.

> 2026-09-21: um conserto de regex entrou com a mutação do ramo vermelha, mas o
> padrão casava qualquer cabeçalho com a palavra e a revisão seguinte reprovou.
> A mutação que alarga o padrão só ficou vermelha com os fixtures copiados da
> reprodução do revisor; com os meus, sobreviveu.
