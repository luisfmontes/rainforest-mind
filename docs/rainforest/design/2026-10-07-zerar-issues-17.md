# Zerar issues: #409-#414, #417

## Objetivo
Fechar as sete issues abertas depois da 1.44.0 numa rodada só (MINOR 1.45.0 — chave de config `pastas` e flag `--raiz` novas): pasta de docs do repo adotada pelo mapa, design e plano; config de projeto visível em worktree; desligar gate só por variável e config; raiz do código separada da raiz do estado na catraca do verificar; `. arquivo` lido pelo gate de Issue; dois falsos positivos do gate de publicação; e a retirada do contorno do `cc-plugin-sec-default` que a revisão de segurança apontou no #418.

Para quem: o Luís e quem usa o plugin em repo de cliente onde o plugin `protheus` já mantém `docs/legado/` e `docs/plans/`. O rainforest **convive** com essas pastas, não as substitui.

## Decisões fechadas

### #412 — pasta de docs do repo (ampliada: mapa, design e plano)
- **D1 — chave de config nova `pastas` (tipo novo `pastas` em `hooks/lib/config.cjs`: objeto com `mapas`, `design`, `planos` opcionais, cada um caminho relativo, confinado ao repo, sem `..`); resolvedor único `hooks/lib/pastas-docs.cjs` exporta `pastaDe(tipo, {raiz})` com a ordem: (1) chave `pastas` do config; (2) para `mapas`, `docs/legado/COBERTURA.md` existente → `docs/legado`; (3) para `design` e `planos`, `docs/plans/` com algum `*-design.md` ou `*.gates.json` → `docs/plans`; (4) padrão `docs/rainforest/<tipo>`** — porquê: um lugar só decide a pasta, e a skill, o agente e os scripts leem dele; a detecção usa marcadores específicos do plugin `protheus` (COBERTURA de arqueologia, `*.gates.json`), não o nome genérico `docs/plans/` sozinho.
- **D2 — em pasta adotada (fora de `docs/rainforest/`), design e plano levam sufixo: `<slug>-design.md` e `<slug>-plano.md`; no padrão o nome segue `<slug>.md`. `scripts/pastas-docs.cjs caminho --tipo <t> --slug <s>` imprime o caminho para as skills usarem** — porquê: design e plano têm o mesmo nome `<slug>.md` e numa pasta comum um sobrescreveria o outro; o sufixo segue a convenção que o plugin `protheus` já usa em `docs/plans/` (`-design.md`, `-plan.md`).
- **D3 — `estado.cjs`: `docDoEstagio` lê `bloco.doc || bloco.arquivo`, e `docDe(tipo, slug)` passa a usar o resolvedor de D1/D2** — porquê: o brainstorm grava `{"doc":...}` e nenhum código lê `design.doc` (`estado.cjs:1148`); hoje o design só é achado porque mora no caminho fixo.
- **D4 — mapa em `docs/legado/`: o arquivo do mapa vai para `docs/legado/<fatia>.md` no formato do rainforest; no `COBERTURA.md` existente entra **uma linha por fatia** nas colunas de lá (`| Fatia | Fontes cobertos | Demanda | Data |`), nunca a tabela de 6 colunas; o detalhe por bloco fica dentro do mapa. Sem `COBERTURA.md` adotado, segue o formato atual em `docs/rainforest/mapas/`** — porquê: um índice só por repositório, que a `/protheus:arqueologia` continua lendo; misturar dois esquemas na mesma tabela quebraria a leitura dela.
- **D5 — atualizar os caminhos fixos: `skills/arqueologia/SKILL.md`, `agents/arqueologo.md` (inclusive a condição de parada "escreve só em docs/rainforest/mapas/" → "escreve só na pasta de mapas que `pastas-docs.cjs` devolve"), `commands/arqueologia.md`, `skills/brainstorm/SKILL.md`, `commands/brainstorm.md`, `skills/plano/SKILL.md`, `skills/executar/SKILL.md`, `skills/revisar/SKILL.md`; `scripts/semear.cjs:260`, `conferir-fluxo.cjs` e `conferir-prova.cjs` usam o resolvedor no padrão** — porquê: são os pontos com o caminho fixo levantados nesta sessão; o `semear` já lê qualquer tabela com `|` sem depender das colunas.
- **D6 — estado de máquina não muda: `estado`, `portoes`, `reguas`, `varredura`, `projeto` ficam em `docs/rainforest/`; os hooks que detectam fluxo por `docs/rainforest/estado/` não mudam** — porquê: decisão do Luís (Q1-A da abertura): só scripts do rainforest leem esses arquivos, e mudá-los mexe em ~400 pontos sem ganho.

### #411 — config de projeto em worktree
- **D7 — `resolverConfig` (`hooks/lib/config.cjs:291-302`) resolve a pasta do projeto pela raiz do checkout principal: `git rev-parse --path-format=absolute --git-common-dir` a partir de `projetoDir`; se o basename for `.git`, usa o `dirname`; sem git, mantém `projetoDir` como hoje. `setup.cjs --escopo projeto` grava no mesmo lugar (`setup.cjs:45`)** — porquê: o padrão já existe em `gate-publicacao-destino.cjs:285-298` e `limpar-worktrees.cjs:365-379`; corrigido no ponto único, os ~30 leitores (gates, `estado`, `saude`, `poda`...) herdam, e o defeito também atinge subdiretório do principal, não só worktree.

### #417 — desligar gate só por variável e config
- **D8 — nenhum gate lê mais `.rainforest-gate-off`: sai a leitura dos nove gates (`gate-fechar-issue`, `gate-git-verificacao`, `gate-staging-total`, `gate-verificador-staged`, `gate-agente-em-voo`, `gate-repo-alheio`, `gate-worktree`, `gate-publicacao-destino` com `desligadoPorArquivo`); as mensagens de bloqueio citam só `RAINFOREST_GATE_OFF` e a chave de config; comentário de `config.cjs:6`, `docs/travas-mecanicas.md`, `README.md` e `.gitignore` atualizados** — porquê: o plugin roda em repo de cliente e o arquivo fica largado ou commitado (observação de 2026-09-03); o fallback para o principal que só o arquivo tinha passa a existir para o config (D7).
- **D9 — no `gate-subagente-sem-instalar`, sai a trava de criar o arquivo (`ARQUIVO_DE_DESLIGAR`, `escreveArquivoDeDesligar`, Write/Edit no nome); fica a que barra definir `RAINFOREST_GATE_OFF`** — porquê: o arquivo deixa de desligar algo, então não há o que proteger; a variável continua sendo escotilha.
- **D10 — `gate-git-verificacao.cjs:1023-1027` ganha o ramo `ehSubagente` dos outros gates: subagente não recebe a saída na mensagem; `hooks/testa-fuga-de-escotilha.sh` passa a cobrir esse gate** — porquê: medido nesta sessão, com `agent_id` o stderr nomeia a escotilha; é o único dos gates com mensagem sem esse ramo.
- **D11 — baterias trocam os casos do arquivo por: o arquivo presente **não** desliga (exit 2 mantido) e a variável desliga** — porquê: critério de pronto da Issue; o caso negativo prova que a leitura saiu.

### #413 — raiz do código no verificar
- **D12 — `estado.cjs marcar --estagio verificar --raiz <dir>` repassa `--raiz-codigo <dir>` ao `conferir-fluxo.cjs mutacoes`, que usa esse valor no lugar de `RAIZ` só para resolver onde a mutação roda (`conferir-fluxo.cjs:1045`); plano e estado continuam lidos de `RAIZ`; `<dir>` precisa existir e ser pasta, senão exit 2; `skills/verificar/SKILL.md` manda passar a flag quando o código vive em outro worktree** — porquê: mesmo nome e sentido do `--raiz` do `conferir-mutacao` e da skill executar; sem mudança de schema.
- **D13 — não gravar caminho de worktree no JSON do estado** — porquê: caminho de máquina em arquivo versionado, e fica velho quando `limpar`/`fechar` removem o worktree entre `executar` e `verificar`.

### #414 — `. arquivo` no gate de Issue
- **D14 — `gate-fechar-issue.cjs` trata `source`/`.` antes do desempacotador, como `gate-subagente-sem-gh.cjs:717-727`: lê o arquivo por `caminhoDeArquivoExecutado` + `arquivoDeScriptExecutado` e barra só se o conteúdo fecha Issue; arquivo ilegível ou caminho com variável passa** — porquê: o gatilho medido é só o `.` (`tokens-comando.cjs:780`), `set -a` e variáveis não pesam; um `.env` não fecha Issue; o gate irmão já tem o ramo.
- **D15 — a mensagem de ilegível deixa de dizer "contém variável" quando o motivo é outro; o caso `(by)` `source fechar.sh` com `gh issue close` dentro continua exit 2; `bash -c "gh issue close $N"` continua exit 2; os três repros da Issue entram na bateria com exit 0** — porquê: critério de pronto da Issue.
- **D16 — modelo de ameaça do D14: protege contra a janela principal fechar Issue sem a evidência que o gate exige; fica fora o script carregado que monta o `gh` dinamicamente a partir de variável — o mesmo limite que o `gate-subagente-sem-gh` já aceita** — porquê: perseguir shell dinâmico não tem fundo (ideia `gate-por-parser-de-shell-e-poco-sem-fundo`).

### #409 e #410 — falsos positivos do gate de publicação
- **D17 — #409: no `so_se` do padrão telefone (`conferir-publicacao.cjs:163-206`), isentar o casamento contido numa pseudo-versão Go `v\d+\.\d+\.\d+-(?:0\.)?\d{14}-[0-9a-f]{12}`, em qualquer arquivo** — porquê: `conferir(texto)` não recebe o nome do arquivo; a forma é específica o bastante para não precisar dele, e telefone fora dela segue pego.
- **D18 — #410: no padrão `credencial` (`conferir-publicacao.cjs:247`), depois de `authorization`, pular a palavra do esquema (`Bearer`/`Basic`/`Token`, com o `f"` de f-string colado) e julgar o que vem depois; `REFERENCIA_DE_VARIAVEL` ganha `{IDENT}` (f-string) e `.format(IDENT)`; isenção só quando o valor é **inteiro** uma referência** — porquê: medido nesta sessão, o valor capturado é a palavra `Bearer`, então até `"Bearer ${VAR}"` é acusado hoje; literal depois do esquema continua credencial.
- **D19 — modelo de ameaça de D17/D18: protege contra segredo e dado pessoal literal num repo público; fica fora segredo montado por concatenação de literais** — porquê: o detector é textual por linha; isso já era o limite antes.

### Contorno do `cc-plugin-sec-default` (achado da revisão de segurança, #418)
- **D20 — o mod da abertura não injeta nada quando `cc-plugin-sec-default` está presente: saem de `hooks/register.ts` os hooks `engine.create`, `session.start`, `prompt.submit` e `session.compact`, e de `hooks/abertura-mod-puro.mjs` `barraCompose`, `anexar`, `temMarca`, `MARCA` e os métodos `engineCriado`/`aoIniciar`/`aoSubmeter`/`aoCompactar`; sai a bateria `hooks/testa-mod-abertura-append.cjs`; o comentário de cabeçalho passa a dizer que, nessa conta, a abertura chega só pelo núcleo do SessionStart que o harness entrega, e que regras inteiras ali pedem liberação do admin da organização** — porquê: o plugin gerenciado barra `prompt.compose` e `classic.SessionStart` de plugin de usuário por política da organização; detectá-lo e entregar o mesmo texto como mensagem de usuário é contornar a trava. Decisão do Luís (Q8).

### Fechamento
- **D21 — versão 1.45.0 (MINOR) em `.claude-plugin/plugin.json`, manifesto do Codex, `CHANGELOG.md` e `README.md`** — porquê: chave de config e flag novas são funcionalidade.

## Avaliado e descartado
- Isenção por nome de arquivo (`go.mod`/`go.sum`) para o #409: `conferir(texto)` não recebe o arquivo (`conferir-publicacao.cjs:491`), e a regex ancorada dispensa o nome.
- Isentar só `{IDENT}` no #410 sem tratar o esquema: medido, o valor capturado é `f"Bearer`, então a isenção nunca seria alcançada.
- Gravar `executar.raiz_codigo` no estado para o #413: caminho de máquina versionado e que fica velho (D13).
- Escrever as linhas do rainforest na tabela de 6 colunas dentro do `COBERTURA.md` do protheus: dois esquemas na mesma tabela (D4).
- Detectar `docs/plans/` só pelo nome: nome genérico, usado por outros plugins; o marcador é `*-design.md`/`*.gates.json` (D1).

## Fora de escopo
- Mover estado, portões, réguas e varredura (D6).
- Os outros consumidores de `desempacotarWrapperDeString` (`gate-staging-total`, `gate-worktree`, `gate-mensagem-commit`, `gate-bateria-sem-timeout`, `gate-subagente-sem-instalar`) e o tratamento de `.`: não medidos nesta sessão; sem relato de falso positivo neles.
- Converter o mapa do rainforest para o formato `RN-<MOD>-NN`/`## Entregas` do protheus.

## Varredura
docs/rainforest/varredura/2026-10-07-zerar-issues-17.txt — só as próprias issues e antecedentes já fechados: #265 (fallback do arquivo para o principal, base do D7), #362/#405 (falsos positivos do `gate-fechar-issue`, mesmo molde do D14), #337/#260 (isenções de referência no gate de publicação, base do D18), e a observação `obs-2026-10-06-gate-off-so-por-variavel` que deu origem ao #417. Nenhum trabalho anterior sobre pasta de docs do repo ou raiz de código no verificar.

## Em aberto
Nenhum.
