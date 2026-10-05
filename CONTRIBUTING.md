# Como mexer neste repositório

O plugin é o **código**; o `FOCO.md`, o `ideias.jsonl` e o `projetos.json` são
**dados do usuário** e moram em `~/.rainforest`, fora daqui. Nada neste repo deve
ler o seu acervo para funcionar, e nada dele deve escrever caminho de máquina
nenhuma dentro de arquivo versionado.

## Antes de abrir PR

```
bash scripts/varrer-baterias.sh
CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh
```

A segunda linha é a mesma que o CI roda em passo próprio (ver abaixo) — rode-a
você também, e não só no CI, senão a divergência só aparece quando alguém digita
o override na mão.

Todas verdes, sem exceção. **Node é a única dependência**: as baterias não usam
outra linguagem — nem para montar fixture, nem para conferir JSON. Isso vale para
quem contribui, não só para quem instala; promessa de runtime que não alcança o
caminho de teste deixa de fora quem quer validar a própria mudança.

Isso é conferido por catraca, não por leitura: `scripts/testa-dependencias-de-bateria.sh`
recusa bateria que chame `jq`, `rg` ou `python` pelo nome (Issues #157, #158 e
#159 — o runner do Actions tem `jq` e `python3`, a máquina de quem instala não).
Bateria cujo **alvo** é Python (`testa-medir-injecao.sh`, `testa-statusline.sh`)
resolve o interpretador uma vez em `$PY`, testando que ele roda, e **pula com
exit 3** quando não há Python 3 — "não rodou" nunca se confunde com "quebrou" nem
com "verde". Também por catraca (Issue #160): bateria que lê configuração aponta
`RFM_ROOT` para uma raiz descartável, para o veredito não depender do
`config.json` de quem a roda.

A última linha roda o **gêmeo** em Python de `conferir-entrega.cjs` (o de
`ideias.cjs` foi aposentado em 2026-08-22, depois que a bateria gêmea parou de
provar equivalência). Ela é a exceção que confirma a regra: ali o Python **é o
teste**, não o meio — a mesma bateria roda contra as duas implementações, e é
isso que prova que o port não perdeu garantia. Apagar um gêmeo é apagar a
prova; escrever teste novo em Python é adicionar dependência sem precisar.

O CI roda essa linha do gêmeo num **passo próprio** do job `baterias`
(`.github/workflows/baterias.yml`, depois de "Rodar as baterias"), não dentro de
`scripts/varrer-baterias.sh` nem da bateria padrão — decisão D5. Sem isso a
garantia só existe quando alguém digita o override na mão: foi assim que ela
congelou por três semanas sem ninguém ver (Issue #303) — 21 casos vermelhos no
gêmeo, zero no `.cjs`, e nenhuma bateria do caminho default acusou nada.

Bateria nova entra com pelo menos um caso de **mutação** — sabota o mecanismo e
exige que ele reprove. Trava que nunca foi vista travando não é evidência de nada.

## Campo obrigatório novo vem com o passado resolvido, no mesmo commit

Esta é a regra que este repo aprendeu do jeito caro, e ela vale para qualquer
esquema de dado (o `ideias.jsonl` hoje, o `projetos.json` amanhã).

Quando um campo passa a ser **cobrado**, o mesmo commit resolve o acervo que já
existe, de um destes três jeitos — e diz qual escolheu:

| Caminho | Quando serve |
|---|---|
| **backfill** | o valor é derivável (do git, de outro campo, de convenção) |
| **anistia por data**, em constante declarada | o valor é autoral e não há de onde inferir |
| **opcional para quem nasceu antes** | o campo só faz sentido no fluxo novo |

E a bateria tem que provar as duas metades: **linha herdada não derruba o gate, e
linha nova derruba.**

> 2026-08-11: `gancho` virou campo obrigatório das ideias abertas sem nenhuma das
> três coisas acima. O `conferir` — que é o gate de saúde do acervo — ficou
> vermelho no mesmo commit, com 35 problemas em linhas que nenhuma sessão tinha
> causado, e ficou assim por um dia inteiro. Gate permanentemente vermelho não é
> gate: a sessão que o encontra assim aprende a ignorá-lo, e aí ele para de pegar
> o problema **novo**, que é a única coisa que ele existe para pegar. Corrigido na
> Issue #3 com anistia por data (`GANCHO_EXIGIDO_DESDE`), e a dívida continua
> impressa em toda execução, porque anistia que esconde vira esquecimento.

## Duas irmãs da mesma regra

- **Contagem diz de qual conjunto saiu.** `35 de 55 abertas` e nunca `35`. O mesmo
  arquivo mostrou 35 num comando e 72 em outro, sem nenhum dos dois dizer o
  universo — e o que estava errado era o segundo.
- **Varredura não aborta por causa de uma linha.** Comando que varre o acervo
  conserta o que consegue inferir, **relata** o que precisa de texto humano, e sai
  com código ≠ 0 porque parcial não é pronto. Abortar na primeira linha
  irreparável deixa o comando inútil para todas as outras.

## Arquivo novo na pasta de dados nasce com três portas

Quem **escreve** (o comando dono), quem **mostra** (o `/setup`) e quem **checa** (o
`/saude`, quando houver como falhar em silêncio). Enquanto as três não existirem, a
entrega está pela metade.

A porta do meio é mecânica: os arquivos que o plugin possui na pasta de dados vivem
em **uma** lista no `scripts/setup.cjs` (`ARQUIVOS`), lida por quem semeia e por
quem mostra. `scripts/testa-setup.sh` compara o que existe no disco depois do
`--criar` com o que a saída do estado **nomeia**, e a mutação tira um item da lista
para exigir que ele desapareça do estado.

> 2026-08-12: o `projetos.json` nasceu, o `--criar` aprendeu a semeá-lo, e o estado
> nunca soube que ele existia — quem instalasse não tinha onde ver a configuração
> nova. Horas depois, no mesmo dia, a mesma coisa com as pontes de Codex/Gemini:
> capacidade nova exposta só pelo comando que a criou. Nas duas vezes quem apontou
> foi o usuário, e nas duas a regra já estava escrita — como observação plantada,
> que não trava nada. Daí a lista única e o teste com mutação.

## Dependência externa nasce desligada

Recurso que precisa de PowerShell agendado, bridge, plugin de terceiro ou serviço
entra como chave em `hooks/lib/config.cjs` com padrão **falso**, e quem lê a chave
trata falha de leitura como desligado. Quem instalou o plugin não deve descobrir
dependência por mensagem de erro — e a abertura de sessão só reporta o que a
instalação **declara**.

## Regra e injeção

As regras vivem em `skills/rainforest-mind/SKILL.md`. O que fica **antes** da
marca `<!-- detalhe -->` é injetado em toda sessão e paga token; o resto carrega
sob demanda. Incidente datado vai em **blockquote** — o hook o remove da injeção,
e ele continua no arquivo ao lado da regra que fundamenta.

O bloco de núcleos tem teto em bytes (`NUCLEOS_MAX_BYTES`), e é catraca: crescer
regra dói na hora de escrever, não na hora de ler. Se o seu texto não couber,
a saída é **subtrair**, não aumentar o teto.

**Sem mod, o hook entrega o núcleo; com mod, as elaborações chegam inteiras.**
Sem o mod (Codex, ou Claude Code anterior à 2.1.287), o `SessionStart` entrega só
o núcleo, com `NUCLEOS_MAX_BYTES` de 6.000 B, o bloco de memória com
`MEMORIA_MAX_BYTES` de 3.000 B e o conjunto com `ORCAMENTO_BYTES` de 8.100 B,
como sempre. Com o mod (`hooks/register.ts`), a abertura vira seção do system
prompt, fora do teto de entrega do hook, e as elaborações
(`skills/rainforest-mind/references/regra-NN.md`) das regras listadas em
`elaboracoes` de `hooks/abertura-mod.json` (hoje 16, 12, 11 e 17) entram
inteiras. O hook fica de reserva e não duplica (D7): quando o mod monta a seção,
ele tira as entradas da abertura do `SessionStart`. Lista e orçamentos moram nesse
JSON, não aqui: `orcamentoRegrasBytes` de 40.960 B (núcleo medido mais
elaborações), `orcamentoFocoBytes` de 12.288 B, `orcamentoMemoriaBytes` de
8.192 B e `orcamentoTotalBytes` de 61.440 B, a soma exata das três partes.
`scripts/sugerir-elaboracoes.cjs` só sugere, a partir das observações; quem muda
a lista edita o JSON. Falha do mod é falha aberta: a seção não entra, nada sai do
`SessionStart` e o hook segue entregando. O mod só vale a partir da sessão
seguinte à atualização do plugin.

**A faixa do mod.** A entrada do mod é `hooks/mod.tsx`: liga a abertura
(`hooks/register.ts`, intacto) e desenha a faixa acima do prompt (`ui.render` em
`AbovePrompt`). São no máximo 4 linhas (`MAX_LINHAS` em `hooks/faixa-puro.mjs`):
foco, fluxo, relógio e Q, cada uma cortada em `bodyColumns`. Com menos espaço, sobra
primeiro a Q, depois o relógio, depois o fluxo. A faixa só aparece com fluxo em curso, Q aberta
ou relógio aceso, e o foco sozinho não a acende. O fluxo vem de todos os worktrees do repositório,
por `scripts/faixa-dados.cjs` (somente leitura, reusa `proximo` e
`tituloDoFocoAtivo`). Quando o mesmo slug aparece em mais de um worktree, vale a
cópia mais avançada, e a de worktree de subagente (`.claude/worktrees/agent-*`)
só vale quando é a única. As Q saem do texto final do turno (`e.answer` do
`turn.complete`, só da sessão principal) pelos dois marcadores de `MARCADORES_Q`,
`❓ **Q<n> — título**` e `**Q<n>.**` (também em blockquote e item de lista), fora
de cerca de código (```` ``` ```` ou `~~~`). O título é só a pergunta (corta no
primeiro `?`, `:`, ` — ` ou `. `), e cada Q ganha uma fatia da largura para todas
aparecerem. Uma resposta sem Q zera a linha, e a mensagem do usuário
(`prompt.submit`) também: as Q respondidas saem na hora. "Esconder" vale até a assinatura mudar: Q nova ou resolvida,
etapa nova ou mudança nos agentes em voo. A faixa atualiza em `session.start`, em `turn.complete` e ao
pressionar; no meio do turno, só a limpeza das Q no envio da mensagem. Falha de leitura apaga só a linha afetada e
nunca quebra a sessão. Controle de terminal (ESC, C1, bidi) é trocado por espaço
antes de desenhar. A faixa não repete a statusline (jornada, prazo, versão). A
prova de engine é `claude plugin test .` (`hooks/mod-faixa.test.tsx`, terminal e
desktop); a lógica, `node hooks/testa-mod-faixa.cjs`.

**O relógio do mod.** A quarta linha da faixa é `⏰ jornada 9h12 · 20h40 | <pasta> parada há 32 min`
(`hooks/relogio-puro.mjs`, sem Node e sem `$`). A jornada (efetiva e hora) aparece quando as
efetivas passam de 9 h (`LIMITE_EFETIVA_MIN`), ou de noite (das 19 h às 5 h, `HORA_NOITE` e
`HORA_FIM_MADRUGADA`) com mensagem do usuário nos últimos 30 min (`JANELA_MSG_MIN`). A janela
parada mais antiga além da `Ociosidade máxima:` do `FOCO.md` (45 min se ausente,
`OCIOSIDADE_PADRAO_MIN`) é nomeada pela pasta, e ` (+k)` conta as demais; só entram janelas
esperando você há menos de 6 h (`JANELA_VIVA_MS` em `scripts/relogio-sessoes.cjs`). O relógio lê
`sessoes.json` a cada 1 min (`scripts/relogio-sessoes.cjs`) e a jornada a cada 5 min
(`scripts/jornada.cjs --json`) por `$.clock.every`, ligado no `session.start` e cancelado no
`session.end`, e só nasce em sessão interativa. "Esconder" não volta com os minutos: a jornada
volta no dia seguinte, e a janela parada quando outra vira a mais parada ou uma nova cruza o
limite. Quando a jornada acende, uma nota de uma vez por dia vai no prompt seguinte digitado no
composer, como `context` do `prompt.submit` (o modelo lê, o usuário não vê); avisar ou calar
continua sendo decisão do modelo, pela regra 8. Falha de leitura apaga só a linha do relógio. A
prova de engine é `hooks/mod-relogio.test.tsx` (`claude plugin test .`); a lógica,
`node hooks/testa-mod-relogio.cjs`.

## Versão: o release é entrega própria, e o PATCH existe

O bump vai num **commit próprio**, com título `Versao <x.y.z>: <o que o lote
entregou>`, e é o último passo do lote — não vai de carona no commit da feature.

Qual casa mexe:

| casa | quando | exemplo |
|---|---|---|
| **PATCH** (`0.78.0` → `0.78.1`) | o lote só **conserta** — defeito, texto errado, número desatualizado. Nada mudou de forma para quem já leu o README | correção de contagem, conserto de trava que já existia |
| **MINOR** (`0.78.1` → `0.79.0`) | entrou coisa nova, ou mudou o contrato de algo — trava nova, regra nova, comando novo, campo obrigatório | a trava de repo alheio; a partição de uma elaboração em duas |
| **MAJOR** | ainda não. O `0.` da frente é SemVer dizendo *"o contrato pode mudar sem aviso"*, e isso continua verdade enquanto as 17 regras mudam de forma | — |

Até 2026-08-26 **todo** release foi MINOR, inclusive os que só consertavam
defeito — o PATCH existia e nunca foi usado. A distinção não é burocracia: o
número é o único sinal que diz se quem instala precisa reler o README ou não.

**Dois lugares repetem o número e têm que andar juntos:** o
`.claude-plugin/plugin.json` e o badge de versão no topo do `README.md`.

E o motivo de o bump não ser opcional: o plugin que **executa** não é este clone,
é o cache `~/.claude/plugins/cache/<marketplace>/<plugin>/<versão>/`, indexado
pela versão. Sem bump, o `claude plugin update` não tem versão nova para buscar e
o trabalho fica na `main` sem chegar em máquina nenhuma. Quem mede isso é
`node scripts/conferir-versao.cjs` (exit 2 acima do teto), chamado pelo `fechar`.

> 2026-08-26: o `plugin.json` ficou em 0.77.0 com **18 commits** de trabalho
> mergeado além dele — quatro PRs de regra, três defeitos de produção, uma trava
> de borda nova, nada rodando. O `/saude` já dizia "o que EXECUTA está atrás: 18
> commit(s) atrás". Faltava a regra estar escrita, e é este parágrafo.

## Issue e PR

Issue com o comando exato e a saída colada vale dez vezes uma descrição. Se o
relato vier de uma sessão sua com o próprio plugin, rode
`node scripts/conferir-publicacao.cjs <arquivo>` antes de publicar: ele **sai com
código 2** se houver telefone, JID, e-mail, caminho de home ou credencial no
texto.

`main` é protegida: toda mudança entra por PR, inclusive a do dono do repo.
