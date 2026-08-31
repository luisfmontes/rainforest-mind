# Ideias — colheita de 2026-08-28 (revisão externa, sem limite de ambição)

Vinte ideias, uma por linha de `/ideia` se quiser plantar. Cada uma com o
pitch e por que cabe na filosofia da casa (trava com exit code, cresce por
subtração, fato não sobe pro usuário, medição antes de automação).

## Agentes novos

**1. `sabotador` — o advogado do defeito.** Depois do verificar aprovar, um
agente em worktree read-only recebe o diff + os critérios com uma única
missão: produzir a entrada que quebra o que a bateria não pegou. Se conseguir,
vira reprovação com evidência colada. Os dois achados de revisor independente
citados no fonte provam que esse papel rende — hoje ele é eventual; vira nó do
grafo, opcional por chave (`--ligar sabotador`), para entrega de risco.

**2. `arqueologo-ativo` — lições viram memória, não só histórico.** Ronda que
lê `estado/*.json` fechados + git log e escreve observações de um tipo novo
(`licao`): por que reprovações aconteceram, quais critérios nasceram mal
escritos, quais estimativas erraram. O estágio `plano` passa a receber as
lições casadas por FTS: "critério parecido com o seu já reprovou 3× por X".
A arqueologia que hoje é comando vira ciclo.

**3. `cartografo` — o mapa do território.** Deriva (nunca à mão) um mapa
módulo → bateria que o cobre → último fluxo que mexeu → densidade de lições.
O briefing do executar ganha uma linha: "você está entrando em território da
`testa-estado.sh`, 2 lições registradas". Barato, e mata o "não sabia que isso
tinha teste".

**4. `porteiro-de-dependencias` — revisor com outro perfil de risco.** Diff de
lockfile/manifesto não se revisa como diff de código: o que importa é
procedência, licença, superfície nova de rede. Um revisor dedicado, acionado
pelo tipo do arquivo tocado, com checklist próprio — hoje esse diff passa pelo
mesmo funil dos demais.

**5. `narrador` — o diário que o vigia envia.** Fim de dia: compila
transições de estado + observações do dia num digest humano de 10 linhas. Com
a `integracao-whatsapp-mcp` declarada, o vigia envia. O dia de hoje é o caso
de uso: você operou a floresta inteira do celular.

## Fluxos e estágios novos

**6. Fluxo `incidente` — grafo curto para produção quebrada.** O fluxo de 7
estágios é para construir; incêndio pede outro: `reproduzir → conter →
corrigir → post-mortem`, com `PRE_REQUISITOS` próprio e o post-mortem
plantando uma `/ideia` automaticamente. Sem isso, incidente vira trabalho
fora do fluxo — exatamente o que o radar de escopo existe para acusar.

**7. Fluxo `experimento` — spike com data de morte.** Timebox declarado no
início; no fim, gate binário: promover (obriga passar pelo brainstorm) ou
descartar (obriga escrever o "por que não" na memória). Mata o protótipo
eterno e alimenta o banco com o motivo — a decisão descartada de hoje é a
pergunta repetida de daqui a três semanas.

**8. `ensaio` — dry-run do plano antes do executar.** Agente barato,
read-only, caminha o plano contra o repo: comando de critério existe?
fixture citada existe? bateria nomeada roda? Plano com critério
infalsificável é a causa raiz de metade das reprovações em série — pegar
antes custa um agente; pegar depois custa 3 giros e o teto do D3.

**9. `estimar` — previsão gravada, calibração medida.** Campo opcional no
plano: tentativas e duração previstas por tarefa. O estado grava previsto vs.
real. Nada cobra nada no começo — é coleta. Em dois meses, o teto de
tentativas e a catraca de relógio deixam de ser chute: viram percentil dos
seus próprios dados. "Medição antes" aplicado a si mesmo.

## Memória e conhecimento

**10. Convicções — a memória episódica vira semântica.** Observação que se
repete N vezes promove a `conviccao` (com contador e origens); convicções
entram acima das recentes na abertura. Evidência nova que contradiz uma
convicção não coexiste em silêncio: marca conflito e sobe como Q. É o degrau
acima do `consolidar` que acabamos de desenhar.

**11. `porque <arquivo:linha>` — a trilha de decisão mecânica.** git blame →
commit (com o selo da ideia 16) → plano → design → decisão D_n. A cadeia
inteira já existe no repo; falta só o caminhante. Para um lead, é a resposta
de onboarding definitiva: o júnior pergunta "por que isso é assim" e o
comando responde com a decisão e o porquê originais.

**12. `semear --equipe` — o pacote de conhecimento sanitizado.** Exporta
designs + lições + convicções sem dados pessoais (sem FOCO, sem ideias, sem
memória de sessão) num pacote que outro dev importa. O plugin já é toolkit
individual; isso o torna semente de equipe — e força a linha clara entre o
que é método (compartilhável) e o que é seu (local).

## Harness e travas

**13. Hook `Stop` do estágio em voo.** Pendente da primeira revisão: fim de
turno com estágio aberto sem `marcar` → aviso (ou bloqueio com motivo).
Mecaniza o "não chama de pronto" na última fronteira que falta.

**14. Custo por estágio no estado.** Tamanho de transcript consumido por
estágio, gravado no fechamento. `fechar` imprime "este fluxo custou X". É o
dado que falta para as Qs que hoje se fecham por chute (teto 3, vagas 9+5,
gatilhos 60/50/10) fecharem por medição.

**15. Selo de proveniência no commit.** `fechar` carimba a mensagem de commit
com slug + hash do design aprovado. De graça, torna a ideia 11 mecânica e a
`arqueologia` à prova de história recontada.

**16. Catraca de relógio por tarefa.** A catraca por relógio que você já
desenhou, um nível abaixo: tarefa passando de 2× a estimativa (ideia 9) faz o
heartbeat sugerir decompor — sugestão, não trava, até os dados da 14
dizerem onde o joelho da curva está.

## Ecossistema e trabalho

**17. Territórios — pacotes de domínio plugáveis.** Um "território" adiciona
ao plano templates de critério e padrões de bateria do domínio: `território
protheus` (TLPP/AdvPL — compilação, teste em ambiente, padrões TOTVS),
`território sql`, `território docker`. O fluxo é o mesmo; a régua fica
nativa do domínio. É o caminho de o rainforest servir a equipe inteira sem
inchar o núcleo.

**18. Decisão remota — a Q chega no bolso e volta.** O teto de 3 reprovações
travou às 15h e você está fora: o vigia envia a Q com a recomendada pelo
WhatsApp; sua resposta cai numa caixa de entrada (arquivo assinado) que o
`estado.cjs liberar` aceita como decisão registrada. A sessão de hoje inteira
foi a prova do conceito manual — isso fecha o ciclo por máquina.

**19. Modo mentor.** Chave que faz cada trava, ao disparar, explicar em duas
linhas o que barrou e por que a regra existe — citando a lição de origem.
Para você, ruído; para o dev da equipe no primeiro mês, é o método se
ensinando sozinho. Desligado por padrão, óbvio.

**20. Placar — o painel estático da floresta.** HTML gerado dos
`estado/*.json` + memória: fluxos por semana, tentativas por estágio, custo
(ideia 14), lições recentes, ideias plantadas vs. colhidas. Zero servidor,
um arquivo, regenerável — o primo dashboard da camada Obsidian que você já
desenhou.

## Se fosse para escolher três amanhã

**8 (ensaio)** ataca a causa raiz das reprovações em série e conversa direto
com o teto do D3 que acabamos de desenhar; **15 (selo)** custa quase nada e
destrava a 11; **14 (custo por estágio)** é a coleta que transforma todos os
chutes numéricos de hoje em medição — e a casa inteira prefere medição.

**21. O contrato de território (promovida a design no mesmo dia).** Domínio é
skill, papel é agente; território mora fora do rainforest, aqui fica só o
contrato — extraído do primeiro caso (Python), validado pelo segundo (AdvPL,
que já existe). Design rascunho: `2026-08-28-contrato-de-territorio.md`, para
colher depois dos fluxos 1–3.
