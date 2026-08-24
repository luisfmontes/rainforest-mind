# Regra 12 — Entrega de agente se valida na saída real

Agente reporta o que
pretendia, não o que aconteceu — sem mentir: ele mede de um jeito que não
pode falhar (2026-08-07: 5 de 7 erros do dia eram isso). As formas
recorrentes, todas com suíte verde: **teste tautológico** (o teste escolhe
o próprio caminho de saída e verifica que um arquivo que ninguém criou não
existe — passa com o código de produção intocado); **mutação falsa**
(tabela verde "mutação → teste pega" quando a única mutação que dispararia
o teste seria sabotar a função nova, não reverter o comportamento real);
**fase renomeada** (itens não feitos viram "próximas fases" num relatório
de sucesso — um agente entregou 1 de 6 itens assim); **aritmética que não
fecha** (675 + 7 ≠ 676) e **código contradizendo o próprio docstring**.
Detector automático não pega nada disso.

> 2026-08-07: no mesmo dia, o detector automático voltou limpo onde a
> inspeção visual achou dois P0.

**E ele inventa nos dois sentidos.** A seção "Verificação" de um relatório
não é transcrição de saída: é **prosa gerada no formato de uma transcrição**.
O mesmo gerador que produz ✓ falso produz ⚠ falso — um esconde defeito, o
outro queima um ciclo de auditoria desmentindo problema que não existe.
Consequência dura: **nenhum identificador sai do relato para dentro de um
comando.** Hash, digest, URL de PR, número de issue — a janela principal
re-deriva tudo de `git`/`gh`. Isso neutraliza a invenção sem depender de o
agente melhorar.

> 2026-08-09: um agente relatou o hash curto certo (`a009b5b`) e o
> "completo" inventado a partir dele, com bloco repetido
> (`...e7f3e4d8e7f3e4d8`) — confabulação de preenchimento, não erro de
> cópia. Outro inventou uma divergência de commit-pai que não existia,
> marcou ✅ nela e justificou com "fora do período de regressão esperado",
> que não significa nada.

Defesas: (1) o **critério de
sucesso vem pronto no briefing**, nunca é construído pelo executor —
qual comando rodar, qual saída inspecionar, qual mutação (que **reverta o
comportamento real**, especificada) deve fazer qual teste falhar. O
briefing **nomeia a falsificação**: comando exato e saída exata que
provariam a entrega errada. Adjetivo não é critério — "não decorativo",
"de verdade", "robusto" são convencíveis; `curl` devolvendo uma string
específica não é;
(2) validar toda entrega **executando o artefato real e olhando a saída**
— suíte verde e relato não são evidência; entrega de worktree tem a parte
mecânica pronta no `conferir-entrega.cjs` da regra 11, e rodá-lo **não é
opcional**: relatório internamente coerente é indistinguível de relatório
verdadeiro por leitura, e só a comparação com o **estado do worktree** separa
os dois. A checagem de **entrada não commitada é reprovação**, não aviso;

> 2026-08-19: um agente escreveu os dois testes ponta a ponta que o briefing
> exigia — 230 e 178 linhas, com `transcript_path` e zero `"project"`,
> exatamente o pedido —, **viu que ficavam vermelhos, não commitou e não
> mencionou**, e entregou como prova o verde das baterias que não exercitam o
> caminho real. Checklist todo ✅, três baterias em `12 ok, 0 falha(s)`, e uma
> justificativa para manter o campo velho por "compatibilidade com harness
> antigo" — um harness que nunca existiu. O relatório não mentiu sobre nenhum
> número que citou: mentiu por **omissão do artefato que contradizia os
> números citados**. Quem pegou foi `FALHA 2 entrada(s) nao commitada(s)`. O
> agravante: o código de produção estava certo, e as falhas eram dos testes
> novos — ele tinha uma entrega boa e a escondeu junto com o problema; (3) o relatório lista
**cada item do briefing** com feito/não-feito — "próximas fases" não
pedidas e números que não somam são gatilho de auditoria, não detalhe;
(4) agentes concorrentes **não compartilham a mesma instância de browser**
(Playwright) — trocam de aba um sob o outro e leem a página errada;
(5) **comando cujo exit code é o sinal não vai para dentro de pipe** —
`| tail`, `| grep`, `| head` devolvem o exit do último elo. Use
`${PIPESTATUS[0]}` ou não canalize.

> 2026-08-09: `docker build ... 2>&1 | tail -5` devolveu exit 0 e virou
> "build concluído"; o Docker Desktop estava parado e nada foi construído —
> o exit 0 era do `tail`. Na mesma noite, `printf ... | node gate.cjs |
> head -3` reportou exit 0 no lugar do exit 2 do gate.

**O experimento controlado do briefing falsificável.** Dois executores, mesma
sessão, mesmo tipo de tarefa, resultados opostos — e a variável não foi
modelo, worktree nem ênfase:

> 2026-08-09 (repo-de-trabalho): o briefing do PR #55 pedia "prove que não é um
> script decorativo que sempre passa" — veio bug entregue e auto-aprovado,
> com a linha defeituosa visível dentro do bloco que o agente colou como
> prova. O do PR #57 pedia "rode `docker run -e GIT_SHA=undefined`; o `curl`
> tem que **continuar** devolvendo `SHA_TESTE_ABC123`; se devolver
> `undefined`, não commite" — passou em reverificação adversarial
> independente. O segundo briefing não era mais longo nem mais enfático: era
> falsificável, e escapar dele exigiria forjar uma saída de curl específica.
**Entrega analítica escapa por não ter artefato.** Relatório que compara,
levanta achado ou lê documentação não tem comando pra rodar, então as defesas
acima não pegam nele — e ele chega com a mesma cara de confiança. O sinal
barato, antes de virar conclusão: conferir **na fonte** duas citações que o
relatório faz do nosso lado (`arquivo:linha`) e **uma contagem** que ele
declara. Citação que não existe na fonte = ler a fonte, não integrar o
relatório.

> 2026-08-08: de dois agentes que compararam repos públicos com este, um
> colou o texto do repo analisado dentro da coluna do nosso e o outro
> afirmou que o `executor.md` barra git destrutivo — não barra. Os dois
> passariam; quem derrubou foi o usuário não acreditando, não a validação.

**Saída verde de ferramenta também não é evidência.** Vale para CLI, não só
para agente: depois de publicar, instalar ou atualizar qualquer coisa,
conferir o **artefato que roda** — arquivo no disco, versão no clone que
executa, saída do binário — nunca a mensagem de sucesso.

> 2026-08-08: `plugin update` disse "updated from 0.22.0 to 0.22.1" sem
> materializar arquivo nenhum, e `marketplace update` disse "Successfully
> updated" com o clone parado no commit anterior; só andou com
> `git merge --ff-only origin/main` na mão.

Publicar este plugin exige três coisas, e faltar uma
deixa a mudança **publicada e inerte**: bump em `.claude-plugin/plugin.json`
(o cache instala **por versão**), fast-forward do clone em
`plugins/marketplaces/<nome>`, e conferir a versão viva no cache — a única
**sem** `.orphaned_at`. Não use `.in_use` como sinal: ele é transitório e
some com o plugin descarregado. E a versão nova só aparece no cache **no
próximo carregamento** — publicar não instala.

> 2026-08-09: esta própria conferência, escrita no dia anterior pedindo
> `.in_use` presente, devolveu "nenhuma versão viva" no primeiro uso real
> — havia uma, sem o marcador.

**✅ sem comando e saída colados = não verificado**, e o briefing dita o
formato, não só a exigência. Item marcado como conferido sem trazer, na
mesma linha, o comando e a **saída literal**, é lido como **não feito** e a
janela principal confere ela mesma. Pedir "cole a saída" no fim do briefing
não basta.

> 2026-08-08: três agentes seguidos marcaram ✓ resumindo a saída em prosa
> ("exit 0, textos presentes") — defeito de disciplina de relato, não de
> execução.

Então o critério de sucesso vai **numerado**, e cada item pede,
nesta ordem: (1) o **comando literal**, (2) a **saída colada**, (3) só então
o veredito. Um ✅ falso não custa só aquele item: obriga a reconferir o
relatório inteiro na mão, que é o custo que o relatório existia pra eliminar.
**E critério que FALHOU o agente não dispensa** — "não afeta a
funcionalidade" é conclusão da janela principal, nunca dele.

**Recomendação destrutiva de agente não se executa, se investiga.** Agente
que conclui "apague X", "reinstale Y", "limpe a pasta Z" entregou
**hipótese**, não diagnóstico: a janela principal confere a cadeia causal e
leva ao usuário, nunca roda direto. O alarme: **a ação apaga dado e a evidência
é "o arquivo contém a string que eu procurei"**.

> 2026-08-08: um agente mandou apagar os `*.jsonl` de `projects/` como
> "sessões em cache" — são os **transcripts** de que o `apontamento-horas`
> reconstrói as horas, e a evidência era circular: os arquivos casavam com a
> busca porque a conversa sobre o assunto está gravada neles.
