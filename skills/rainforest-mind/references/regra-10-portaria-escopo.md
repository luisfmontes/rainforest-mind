# Regra 10 — escopo da portaria e níveis de manifesto

Separado de `regra-10-portaria.md` em 2026-09-14 pelo mesmo motivo que partiu
aquele arquivo do `regra-10.md`: o teto de bytes de um `reference` existe para
que consultar uma regra custe menos de 3k tokens, e o escopo não cabia lá.
Decisão e medições completas em
`docs/rainforest/design/2026-09-13-portaria-em-nivel-de-plugin.md`.

## Onde a portaria vale

**Em toda sessão em que o plugin está habilitado.** Ela é registrada no
`hooks/hooks.json` do **plugin**, com matcher `Task|Agent`.

Até 2026-09-13 ela dependia de registro no `.claude/settings.json` do projeto —
o que era certo sobre a implementação e errado sobre a regra. Registrada assim,
valia **só no repositório do próprio plugin**, enquanto o núcleo da regra 10,
injetado em toda sessão, prometia um portão em todo lugar. Era a opção (2) na
prática e a (1) no texto. A decisão do usuário na Issue #241 foi subir a
realidade até o texto, não encolher o texto até a realidade.

A saída de emergência continua não sendo variável de ambiente (isso seria a
exceção em runtime que a regra proíbe): é tirar o bloco do `hooks/hooks.json`,
que é arquivo versionado e passa pelo `revisar` — a mesma porta do manifesto.

## Dois níveis de manifesto, e o do repo substitui

1. `<repo>/.rainforest/agentes.json` — se existir, é **o** manifesto. Sozinho.
2. `<plugin>/.rainforest/agentes.padrao.json` — o padrão embarcado, que responde
   quando o repo não tem o próprio.

Achado por `path.resolve(__dirname, '..', ...)`, **não** por `CLAUDE_PLUGIN_ROOT`:
o harness expande essa variável na *string do comando* do `hooks.json`, e contar
com ela no `env` do processo seria suposição não medida cujo custo de erro é o
gate morrer em toda sessão.

**Substitui, não soma.** Merge apagaria a diferença entre *não declarei* e
*declarei e tirei*, que é justamente a diferença que este portão decide: um repo
que precise barrar um agente tem de conseguir barrá-lo, e com soma ele voltaria
pelo padrão. Substituição também deixa o arquivo legível sozinho — o que está
escrito nele é o que vale, sem simular a fusão de cabeça.

Um terceiro nível, na raiz de dados do usuário entre o repo e o padrão, foi
**avaliado e descartado**: o usuário escolheu entre "substitui" e "soma", e um
nível a mais é decisão que ele não tomou.

## "Manifesto ausente" mudou de significado

**Repo sem manifesto próprio é o caso NORMAL**, não o caso negado. A ausência que
ainda nega é a do **padrão embarcado**, e ela não é decisão sobre agente nenhum:
é instalação quebrada do plugin.

A distinção **não** é o exit code — `negar()` também sai 2, e 2 é o único código
que barra (0 passa; qualquer outro é erro não-bloqueante, que foi o fail-open da
rodada 6). A distinção é outra, e é o que o código garante:

1. **nenhuma linha no log.** Uma linha de `deny` afirmaria que houve decisão
   sobre aquele agente; não houve.
2. **a mensagem aponta para o plugin**, não para o repo do usuário, que não tem
   nada a consertar.

Manifesto do **repo** inválido é caso diferente e **nega** — não cai no padrão.
Cair no padrão daria a esse repo *mais* agentes do que ele declarou, que é o
oposto do que substituir significa.

Toda negação por agente não declarado diz **qual** dos dois manifestos foi lido e
de qual nível veio. Com dois níveis possíveis, "não consta no manifesto" sozinho
manda conferir o arquivo errado.

## Destino do log de despacho

Antes: `<projeto>/.rainforest/portaria/despachos.jsonl`. Enquanto a portaria
valia só neste repositório isso era invisível — a linha está no `.gitignore`
daqui. Valendo em todo repo, passaria a criar pasta não rastreada dentro de
repositório de cliente, aparecendo no `git status` de outra pessoa. Sujar repo
alheio é a versão pequena de alterar o ambiente do usuário, que a regra 15 proíbe.

Agora: a **raiz de dados**, resolvida por `hooks/lib/raiz.cjs` — mecanismo que já
existia e já era testado, em vez de um caminho fixo novo. Medido em 2026-09-13,
desta árvore e de um repo de cliente: os dois resolvem para a raiz global do
usuário. `RFM_ROOT` é o nível 1 dessa cadeia, então bateria se isola apontando
para caixa de areia — **nenhum teste escreve na pasta pessoal de verdade**.

O campo `repo` entra em cada linha porque, centralizado, o log deixa de dizer por
vizinhança de onde veio cada decisão.

**A divergência, declarada:** um repositório que tenha o próprio `.rainforest/`
com marcador (`FOCO.md` ou `ideias.jsonl`) mantém o log lá. Não é escape: é um
repo que **optou** por ter dados próprios do rainforest, e o log acompanha a raiz
que governa.

A amostra de payload (`portaria/amostra.json`) segue a mesma regra por outro
caminho: só é escrita quando o projeto aberto **é** o próprio plugin, porque ela
existe para virar documentação versionada daqui. Num repo de cliente ela não tem
leitor nem destino.

## O que não mudou

Manifesto **e** estágio ativo continua sendo a regra. Repo sem fluxo aberto
continua sem estágio, e lá o caminho é a autorização explícita do usuário na
sessão — que dispensa o portão de estágio e **só** ele, mantendo as travas de
`escreve: true` (`isolation: "worktree"`, despacho sem `name`).
