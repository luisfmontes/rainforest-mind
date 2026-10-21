# Portaria fora de repo e aviso de escrita pelo shell (#565, #564)

## Objetivo
Dois buracos de trava que deixam a regra sem saída ou sem sinal:
- **#565**: com o cwd da sessão fora de um repo git, o harness recusa `isolation: "worktree"`, e a
  portaria recusa agente que escreve sem esse parâmetro. Nenhum caminho despacha agente que escreve,
  e a janela principal acaba fazendo a tarefa, contra a regra 10.
- **#564**: o `aviso-fluxo.cjs` só está registrado em `Write|Edit|MultiEdit|NotebookEdit`. Código
  escrito pelo shell (`python patch.py`, `sed -i`, `cat >`) entra sem fluxo aberto, sem nenhum sinal.

## Decisões fechadas
- **D1 — A portaria aceita agente que escreve sem `isolation` só fora de repo e com worktree declarado
  e conferido** — porquê (Q1 A do usuário): o `gate-worktree.cjs` já garante o fato que a regra 11
  quer (escrita de subagente só em worktree linkado). A portaria exige o parâmetro, e o parâmetro não
  pode existir quando o harness não tem repo para isolar. As condições, todas juntas:
  - `payload.cwd` não está dentro de repo git nenhum (`git -C <cwd> rev-parse` falha);
  - o prompt traz uma linha isolada `Worktree: <caminho absoluto>`;
  - o caminho é um worktree linkado: `--git-common-dir` diferente de `--git-dir`, e o
    `--show-toplevel` dele é o próprio caminho (normalizado, por igualdade).

  Valendo as três, a raiz da portaria passa a ser esse worktree: manifesto, estágio aberto e
  `leve` se leem de lá. Faltando qualquer uma, a negação de hoje continua. Fora de repo, ela ganha
  uma linha com a saída (`Worktree:` no briefing). Agente que escreve continua nunca nomeado. Com o
  cwd dentro de repo, nada muda: `isolation: "worktree"` segue obrigatório.
- **D2 — Aviso de uma linha na abertura quando o cwd não é repo git** — porquê (P2 da #565, Q1 A):
  a regra 14 manda anunciar ambiente que bloqueia regra. O texto diz que despacho com
  `isolation: "worktree"` não funciona daqui, e aponta as duas saídas: abrir a sessão na pasta do
  repo, ou despachar com a linha `Worktree:` (D1). O aviso vai no bloco "Dependências de ambiente" do
  `foco-session-start.cjs`. Com o cwd em repo, não sai nada.
- **D3 — Hook novo `PostToolUse` em `Bash|PowerShell` que avisa código mudado sem fluxo** — porquê
  (Q2 A): o comando já rodou, então não barra, mas não deixa passar em silêncio. Decide por fato
  (`git status`), não por grafia de comando: a lista de grafias não fechou no #561.
  - O repositório é o do cwd do evento (`--show-toplevel`). Valem os mesmos critérios do
    `aviso-fluxo.cjs`: sem `agent_id`, repo com trilho (rainforest ou protheus), chave
    `aviso-fluxo` ligada, nenhum fluxo aberto na branch e sem `leve`.
  - O hook guarda, por sessão e repo, o conjunto de caminhos de código sujos (`git status
    --porcelain`, as mesmas extensões do `aviso-fluxo`, fora de `docs/`) no diretório temporário do
    SO. Cada chamada compara o conjunto atual com o guardado. Caminho novo no conjunto dispara o
    aviso, e o conjunto guardado é atualizado.
  - Sem conjunto guardado (primeira chamada da sessão), a base é vazia: o código já sujo avisa uma
    vez. É código fora de fluxo do mesmo jeito.
  - O aviso sai em stderr com exit 2 (no `PostToolUse` isso chega ao modelo sem desfazer nada),
    nomeia os arquivos e dá as mesmas saídas da mensagem do `aviso-fluxo` (abrir o fluxo ou `leve`).
  - Os helpers comuns (trilho, fluxo aberto, branch padrão, mensagem com comando colável) saem do
    `aviso-fluxo.cjs` para `hooks/lib/aviso-fluxo-comum.cjs`. Os dois hooks usam o mesmo código.
  - Custo aceito: um processo e um `git status` por chamada de Bash/PowerShell. Hoje a mesma chamada
    já sobe 6 hooks no `PreToolUse`. O veto a `PostToolUse` do design
    `2026-08-17-memoria-e-dados-do-rainforest` (D12) é da marca d'água da memória, que podia pegar
    carona no `Stop`. Aqui o aviso só serve na hora.
  - Limite aceito: arquivo que já estava sujo e muda de novo não reaparece no aviso. Ele já avisou
    na primeira vez.
- **D4 — Baterias com contornos e vizinhos**:
  - portaria: casos novos em `hooks/testa-portaria-fluxo-pulado.cjs` (ou bateria própria). Passa:
    cwd fora de repo, `Worktree:` de worktree linkado, fluxo aberto lá. Barram: cwd fora de repo
    sem `Worktree:`; `Worktree:` apontando para o checkout principal (não linkado), para uma pasta
    que não existe, ou para um subdiretório do worktree; cwd dentro de repo sem `isolation`, mesmo
    com `Worktree:`; agente nomeado.
  - aviso no shell: bateria nova `hooks/testa-aviso-fluxo-shell.cjs`. Avisa: `echo x > a.py` sem
    fluxo; `sed -i` em `.sh` rastreado. Não avisa: fluxo aberto, `leve`, arquivo em `docs/`,
    extensão que não é de código, subagente, chave desligada, segunda chamada sem mudança nova, repo
    sem trilho.
  - abertura: caso no teste do `foco-session-start` com cwd fora de repo (sai a linha) e dentro
    (não sai).
- **D5 — MINOR 1.71.0, CHANGELOG, README** — porquê (Q3 A): entra um hook novo e a portaria muda de
  contrato. O README ganha a linha do hook novo na tabela de hooks e a regra 10/11 da portaria fora
  de repo.

## Avaliado e descartado
- Só o aviso na abertura, sem afrouxar a portaria (Q1 B): deixa a regra 10 sem saída.
- Matcher `PreToolUse` que reconhece `>`, `tee`, `sed -i`, `python` (Q2 B): barra antes, mas é lista
  de grafias e nunca fecha.
- Conferir no `Stop` em vez de `PostToolUse`: um processo por turno, mas o aviso chega depois do
  turno inteiro, quando o código já foi usado.

## Fora de escopo
- Escrita pelo shell em repo diferente do cwd (caminho absoluto para outro repo): o hook olha o
  repo do cwd. Fica para quando aparecer.
- Escrita de subagente pelo shell: quem cuida do agente que escreve é a portaria.
- Fora de repo com `isolation: "worktree"` funcionando por hook `WorktreeCreate`: não existe hoje.

## Varredura
docs/rainforest/varredura/2026-10-21-portaria-aviso-bash.txt — só histórico já mergeado (#430, #440,
#442, #474, #152); nenhuma Issue aberta sobre o mesmo tema além da #564 e da #565.

## Em aberto
- (vazio)
