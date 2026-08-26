# Regra 17 — Multi-janela: paralelo é intenção, janela parada é o alerta

O usuário
roda várias sessões ao mesmo tempo (heartbeat em `sessoes.json`, injetado na
abertura). Se outra sessão está ativa no projeto do foco (campo Projeto do
FOCO.md), o radar **desta** fica leve — trabalho paralelo é escolha dele, não
desvio, e cobrar desvio em cada janela transforma o radar em ruído. O alerta
que importa é o inverso: a sessão do projeto do foco **esperando o usuário**
(turno encerrado, sem resposta dele) além da `Ociosidade máxima:` do FOCO.md
(default 45 min; configurável por foco — ele muda falando ou via `/foco`)
enquanto as outras trabalham — nomear uma vez, "a janela do foco esfriou".
Claude trabalhando sozinho nunca conta como ociosidade: o cronômetro mede o
usuário, não a máquina.

**Estado compartilhado se escreve pelo script, não à mão.** As janelas gravam
nos mesmos arquivos, então o que foi lido no começo do turno já está velho na
hora de gravar.

> 2026-08-09: o `ideias.jsonl` cresceu por baixo de uma janela entre duas
> operações dela — só a releitura evitou apagar a ideia de outra sessão.

No `ideias.jsonl` isso é código desde
2026-08-08: `node scripts/ideias.cjs {plantar|colher|iniciar|unificar|
listar|conferir}` (portado do gêmeo em Python em 2026-08-11, para tirar Python
do caminho de execução; o gêmeo provou o port e foi aposentado em 2026-08-22)
faz trava entre sessões, releitura do arquivo vivo, backup,
escrita atômica, carimbo de data pelo relógio **local** e conferência byte a
byte das linhas não-alvo, revertendo com exit ≠ 0. **Não edite o arquivo à
mão nem com script improvisado**, e não passe data nenhuma — quem carimba é
ele. Escreva o JSON de entrada com ferramenta de escrita de arquivo, nunca
por heredoc do shell: o shell come as barras do caminho do Windows. Nos
arquivos ainda sem trava (FOCO.md, `sessoes.json`) vale a versão manual:
reler o vivo, append de uma linha, conferir que a contagem subiu 1.

**Enlace com regra 16:** antes de recomendar mudança em branch/worktree/fluxo,
a regra 16 consulta este radar (sessoes.json). Paralelo ativo sai da rodada ou
entra bloqueado.

**Pergunta ampla ("o que fazemos hoje?") se responde no escopo DESTA sessão,
nunca no do foco visto de fora.** Sinal barato para saber se esta sessão é a do
foco, antes de investigar qualquer coisa: comparar o `cwd` desta sessão com o
campo Projeto do `FOCO.md`. Divergindo, a pergunta ampla não puxa para dentro
daqui o trabalho que outra janela está fazendo.

A comparação é **normalizada, nunca crua**: o harness manda `C:\Projetos\x` e
o `FOCO.md` manda `C:/Projetos/x`, então barra invertida vira barra e tudo vira
minúscula antes de comparar — e por igualdade, nunca por prefixo. É o que
`normalizarCwd()` faz em `hooks/lib/contexto-sessao.cjs`; a olho, o cuidado é o
mesmo. Comparar cru trata a mesma pasta como duas e responde "divergindo" quando
esta sessão *é* a do foco.

> 2026-08-13: "o que propõe para fazermos hoje?", perguntado numa sessão em
> `C:\Projetos\rainforest-mind`, recebeu uma proposta inteira do trabalho que
> OUTRA janela fazia em outro repositório. O `FOCO.md` já dizia "sessão nessa
> pasta = sessão do foco", e esta sessão não estava na pasta.
