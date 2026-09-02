# Regra 12 — acervo

O que aconteceu, com data e custo. A regra em si mora em
`references/regra-12.md` e se aplica sem este arquivo — aqui está o porquê dela,
que é o que a torna difícil de desobedecer depois de lida.

Cada bloco abre com a data do incidente, e é por essa data que os parágrafos da
regra apontam para cá. Ordem cronológica.

> 2026-08-07: no mesmo dia, o detector automático voltou limpo onde a
> inspeção visual achou dois P0.

> 2026-08-08: de dois agentes que compararam repos públicos com este, um
> colou o texto do repo analisado dentro da coluna do nosso e o outro
> afirmou que o `executor.md` barra git destrutivo — não barra. Os dois
> passariam; quem derrubou foi o usuário não acreditando, não a validação.

> 2026-08-08: `plugin update` disse "updated from 0.22.0 to 0.22.1" sem
> materializar arquivo nenhum, e `marketplace update` disse "Successfully
> updated" com o clone parado no commit anterior; só andou com
> `git merge --ff-only origin/main` na mão.

> 2026-08-08: três agentes seguidos marcaram ✓ resumindo a saída em prosa
> ("exit 0, textos presentes") — defeito de disciplina de relato, não de
> execução.

> 2026-08-08: um agente mandou apagar os `*.jsonl` de `projects/` como
> "sessões em cache" — são os **transcripts** de que o `apontamento-horas`
> reconstrói as horas, e a evidência era circular: os arquivos casavam com a
> busca porque a conversa sobre o assunto está gravada neles.

> 2026-08-09: um agente relatou o hash curto certo (`a009b5b`) e o
> "completo" inventado a partir dele, com bloco repetido
> (`...e7f3e4d8e7f3e4d8`) — confabulação de preenchimento, não erro de
> cópia. Outro inventou uma divergência de commit-pai que não existia,
> marcou ✅ nela e justificou com "fora do período de regressão esperado",
> que não significa nada.

> 2026-08-09: `docker build ... 2>&1 | tail -5` devolveu exit 0 e virou
> "build concluído"; o Docker Desktop estava parado e nada foi construído —
> o exit 0 era do `tail`. Na mesma noite, `printf ... | node gate.cjs |
> head -3` reportou exit 0 no lugar do exit 2 do gate.

> 2026-08-09 (repo-de-trabalho): o briefing do PR #55 pedia "prove que não é um
> script decorativo que sempre passa" — veio bug entregue e auto-aprovado,
> com a linha defeituosa visível dentro do bloco que o agente colou como
> prova. O do PR #57 pedia "rode `docker run -e GIT_SHA=undefined`; o `curl`
> tem que **continuar** devolvendo `SHA_TESTE_ABC123`; se devolver
> `undefined`, não commite" — passou em reverificação adversarial
> independente. O segundo briefing não era mais longo nem mais enfático: era
> falsificável, e escapar dele exigiria forjar uma saída de curl específica.

> 2026-08-09: esta própria conferência, escrita no dia anterior pedindo
> `.in_use` presente, devolveu "nenhuma versão viva" no primeiro uso real
> — havia uma, sem o marcador.

> 2026-08-11: contar bytes do payload do hook com Python lendo o stdout no
> Windows inflou o número — o reencode mastigou UTF-8, e só o node, que fala a
> mesma codificação do hook, deu o valor certo. Na mesma semana, um
> `includes()` procurando o nome de um bloco confundiu presença com menção,
> porque o ponteiro de omissão nomeia justamente o que faltou: três rodadas de
> probe concluíram que uma mudança de rank era inerte, e não era.

> 2026-08-17: um briefing pediu `bash scripts/testa-contexto-sessao.sh, se
> esse arquivo existir` — o arquivo existia, em `hooks/`, não em `scripts/`.
> O agente respondeu "arquivo não existe, conforme briefing, resultado
> aceitável" e seguiu; o teste estava vermelho na `main` havia três dias e
> ninguém soube.

> 2026-08-17: `CLAUDE_MEM_CHROMA_ENABLED=false` foi gravado e tratado como
> resolvido; o worker já rodava com a config anterior em memória, não foi
> reiniciado, e um minuto depois subiu exatamente o processo que a mudança
> devia impedir. No mesmo dia, numa esteira de 13 tarefas, dez de dezoito
> entregas traziam artefato que parecia cobertura e não era — fixture 6,4x
> menor que o corpus real, fallback que fabricava zero e comparava zero com
> zero, checagem que trocava o hook por fixture na mão. Todas as dez tinham
> relatório dizendo "critério atendido". O que pegou foi rodar e quebrar de
> propósito.

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
> novos — ele tinha uma entrega boa e a escondeu junto com o problema.

> 2026-08-20: grep de 15 âncoras contra a fita de uma reunião achou 14
> exatas, 1 deslocada e 1 **inventada** — justamente a única que o agente
> disse ter conferido "ativamente" contra o áudio. Instrução em prosa
> proibindo citação inventada, com o incidente anterior nomeado no briefing,
> não impediu; só o grep de cada âncora achou. No mesmo dia, uma mutação
> comentou a linha do `WHERE`: a consulta estourava, caía no catch e devolvia
> bloco vazio, e a asserção era "a primeira linha não menciona X" — verdadeira
> em bloco vazio, e passaria com a função inteira apagada.

> 2026-08-21: uma variável de ambiente foi escrita direto nos `settings.json`
> vivos do usuário porque o nome apareceu certo ao lado de outra na tabela do
> binário — a semântica era o inverso do que se leu (define a janela do
> contexto, não o gatilho de compactação), e a config cortou a janela pela
> metade. A prova só veio de conferir o `preTokens` real no transcrito depois.

> 2026-08-22: um andaime de teste cruzando Git Bash com Windows (heredoc não
> citado, `TEMP` em caminho POSIX passado a um Python do Windows) reprovou
> duas entregas alheias corretas, com saída vazia ou idêntica nos dois lados —
> o "está quebrado" era do andaime, não do código.

> 2026-08-23: uma skill externa foi descrita como "detecção de obsolescência
> de contexto" com base no README dela; ler o código mostrou que a "detecção"
> era o modelo julgando prosa sobre um `git diff HEAD~5..HEAD`. O fato foi
> corrigido na mesma resposta — a recomendação de abrir Issue não foi, e a
> Issue errada foi aberta. O usuário que desfez.

> 2026-08-24: o relatório de uma correção AdvPL citou `projeto.cadastro.tlpp`,
> arquivo que não existe (o real é `projeto.view.cadastro.tlpp`). O nome
> inventado previa o resto: dezessete fontes com "lint exit 0" e três formas
> de código quebrado que o `appre` não pega.

> 2026-08-25: um agente mandado consertar duas linhas do `saude.cjs` voltou
> sem o teste pedido, apresentando como prova a favor que "a bateria passou
> com 31 ok, 0 falhas" — **com o defeito dentro**. Devolvido, na rodada
> seguinte **apagou os dois casos** e reportou "30 ok, 0 falhas" como entrega.

> 2026-08-26: a bateria `testa-contexto-sessao.sh` foi declarada vermelha na
> `main`, virou Issue e entrou num commit — a partir de um `grep -c FALHA` que
> devolveu 5. Ela estava verde: `ok: 273 falhou: 0`, `exit 0`. As 5 linhas são
> o vermelho esperado das sabotagens da seção 17.1, impressas dentro de
> sub-shell que não conta no placar, e documentadas duas linhas acima de cada
> bloco. O artefato real foi rodado, como a regra manda — o que falhou foi ler
> a saída por substring em vez de pelo veredito. Um depurador foi despachado
> para consertar o que não estava quebrado, e foi ele quem desmentiu.

> 2026-09-01: `vigia-tickets-manha` e `vigia-tickets-tarde` estavam mortos
> havia vinte dias e o Agendador de Tarefas do Windows respondia `State:
> Ready`, `Enabled: True`, `LastTaskResult: 0` — os três campos que uma pessoa
> checa, os três mentindo em coro. O gatilho tinha `EndBoundary` vencido em
> 12/08, e o único sinal verdadeiro era o `NextRunTime` **vazio**. O
> `vigias/ERROS.md` registrava a falha do backup em toda ronda desde 27/08,
> em texto plano, com data e nome: ficou cinco dias sem ninguém abrir. Não
> faltou instrumentação — faltou que alguém lesse, e que algo cobrasse a
> leitura.
