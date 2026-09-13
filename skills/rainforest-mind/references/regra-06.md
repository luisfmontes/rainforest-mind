# Regra 6 — Triagem de achado e plantio de ideias

## Triagem: o teste de uma linha

Achado que não é a tarefa atual (bug, ideia, observação sobre método) precisa ser **triado antes de subir**: é o **código** que faz errado, uma **melhoria** que seria bacana, ou **eu** que cometi um erro de método?

A triagem usa a tabela de `commands/issue.md` seção 2 e `commands/feedback.md` seção 1: procure ali a classificação exata. Na dúvida, pergunte em uma linha. **Achados que caem em mais de uma categoria são DUAS coisas — nunca uma escolha:** um defeito descoberto por engano meu é Issue (código errado é código errado) mais `/feedback` (engano meu é observação de método); não existem "meio-termos" que compõem escolha.

### Conserta na hora

Defeito que **bloqueia o trabalho em curso** não sobe como Issue: conserta e segue. O limite é claro: "bloqueia" quer dizer a tarefa atual não continua sem consertar. Erro que não bloqueia vira Issue e segue normalmente.

Razão: plantio resgata tópicos depois; semente plantada é prioridade baixa. Defeito que impede a tarefa atual é prioridade imediata por definição.

### O que sobe é rascunho escrito, não pergunta

A tentação ao achar defeito é perguntar: "quer que eu registre?" — essa pergunta transfere a decisão de registrar um erro da ferramenta para quem a usa, e a resposta óbvia é sim. A pergunta só adia. Issue tem uma **confirmação depois de escrito** (é irreversível e indexada), mas o rascunho já vai completo no fluxo do comando — nunca como pergunta pendente.

Se achar que pode não ser Issue (dúvida sobre o que é), escreva-a mesmo assim; a dúvida sobe junto com o rascunho em uma linha, e quem despachou aprova antes de publicar em `commands/issue.md` passo 7.

### O incidente que fundamenta

> **2026-08-24:** Uma observação privada (`obs-2026-08-24-defeito-do-plugin-oferecido-como-ideia`) foi plantada com gancho de retorno, mas ficou 19 dias sem ser colhida. Nesse período, ao menos 6 defeitos do plugin entraram no acervo como "ideia de melhoria". O motivo: observação de método só é colhida por **plantio**, e o próprio mecanismo que a triagem descrevia (plantio de achado) é o que mantinha essa observação invisível — o defeito preservava a si mesmo.
> re-verificar: `git log -S 'obs-2026-08-24' --oneline`

## Plantio de ideias

Ideia solta no meio de outra atividade → oferecer:
"planto essa pra depois?" Se sim, acrescentar uma linha em `ideias.jsonl`
(raiz deste repo; formato definido em `commands/ideia.md`) com **contexto**
(de onde surgiu, por que foi plantada) e **projeto/repo** a que pertence
("solta" se nenhum — perguntar em uma linha se não estiver óbvio), e
confirmar: "plantada, de volta a [tarefa]". Plantada ≠ descartada: a ideia
sai da cabeça dele para um lugar confiável, criando raiz até a estação
certa — e precisa carregar contexto suficiente pra ser entendida meses
depois, em outra sessão, sem esta conversa. **Toda ideia plantada leva um
gancho de retorno concreto** — que evento, data ou condição a traz de volta
("quando o Template ALFA fechar", "na próxima vez que mexer no vault").
Sem gancho, "depois" é futuro distante e futuro distante não regula
comportamento presente (Barkley, cegueira do tempo): a ideia vira sedimento
em vez de semente. Gancho não óbvio → perguntar em uma linha, junto do
projeto. Se o que ele quer não é uma
ideia nova competindo, mas **abandonar algo em andamento** ("não quero mais
isso"), a pergunta de fechamento muda: "você já pegou o que veio buscar
aqui?" — se sim, é conclusão legítima do ciclo mergulhar-fundo-e-sair (perfil
multipotencial, não falta de compromisso); registrar como concluído ou
abandonado consciente, nunca como pendência solta.

## Nota: "nunca barrar defeito"

Esta regra (regra 6, triagem obrigatória) e a regra 9 (freio de Pareto) trabalham juntas: regra 9 barra **polimento de coisa pronta**, mas nunca defeito. Se encostou aqui lendo sobre triagem, o ponto é que defeito não sobe como ideia (regra 6), e só é consertado na hora se bloqueia o trabalho em curso — o que não bloqueia vira Issue e entra na fila normal. Veja `references/regra-09.md` para onde o freio é real (melhoria em coisa pronta) e onde é proibido (correção de defeito).
