# Plano: /setup vira entrevista guiada

Design: docs/rainforest/design/2026-10-17-setup-entrevista-guiada.md

Fatos medidos ao escrever (2026-10-17): o `CHAVES` de `hooks/lib/config.cjs` tem **40**
chaves (o "43" do design contou as linhas do estado, que inclui o dial); a tabela de
`skills/setup/SKILL.md` documenta 5. O `run-vigia.ps1` pergunta o toggle por
`setup.cjs --ligado vigias` (linha 42). Os nomes de ronda (`-Vigia`) são os arquivos de
`vigias/*.md`: `batedor-repos`, `jardineiro-ideias`, `revisao-bimestral`,
`sentinela-foco`, `vigia-tickets`. Transcrito real do Claude Code: as primeiras linhas
(`last-prompt`, `mode`, `permission-mode`) não têm `cwd`; a primeira linha que tem o
campo `cwd` é a que diz a pasta da sessão. As integrações já têm checador em
`hooks/lib/integracoes.cjs` (`INTEGRACOES`).

## O que não pode quebrar
- `setup.cjs --ligar`, `--desligar`, `--ligado` e o estado sem argumento mantêm sintaxe, saída e exit code — mensagens de gate, `/saude` e `run-vigia.ps1` dependem deles.
- `setup.cjs` sem argumento continua só lendo: nada é gravado.
- Quem tem `vigias: true` gravado e nenhuma chave de ronda continua com as cinco rondas rodando (padrão das cinco chaves novas é `true`).
- `--aplicar` nunca grava parcial (valida tudo antes da primeira escrita), nunca escreve `FOCO.md` e nunca sobrescreve `ESTRATEGIA.md` existente.
- Primeira vez grava no escopo `usuario`; nada vai para `.rainforest/config.json` do projeto sem `--escopo projeto` explícito.

## Tarefas

### 1. Campo `entrevista` no catálogo e conferidor do setup [tipo: implementar]
atende: D4, D7, D8, D12
arquivos: `hooks/lib/config.cjs`, `scripts/conferir-setup.cjs`, `scripts/testa-conferir-setup.sh`
depende de: nenhuma
prova: `node scripts/conferir-setup.cjs --so-catalogo`
mutacao:
  arquivo: `scripts/conferir-setup.cjs`
  de: `const semCampo = nomes.filter((k) => !Object.prototype.hasOwnProperty.call(CHAVES[k], 'entrevista'));`
  para: `const semCampo = [];`
  bateria: `bash scripts/testa-conferir-setup.sh`
  fixture: `testa-conferir-setup.sh, caso "catalogo com ponte-codex sem campo entrevista e recusado"`
pronto quando: com o `CHAVES` real, `node scripts/conferir-setup.cjs --so-catalogo` sai 0; com um JSON do `CHAVES` gerado do real por `node -e` e com o campo `entrevista` apagado de `ponte-codex`, passado por `--config <arquivo.json>`, sai 1 e a saída nomeia `ponte-codex` — provado por `bash scripts/testa-conferir-setup.sh`, cujos casos rodam o conferidor sobre o catálogo real e sobre cópias mutadas, nunca lendo o texto do fonte do conferidor.

Conteúdo:
- `hooks/lib/config.cjs` exporta `GRUPOS_ENTREVISTA = ['dados', 'idioma', 'projetos', 'ferramentas', 'fechar', 'estrategia', 'foco']` (ordem de D8) e cada chave do `CHAVES` ganha `entrevista`:
  - `idioma` → `{ grupo: 'idioma', detectar: {} }`
  - `ponte-claude` → `{ grupo: 'ferramentas', detectar: {} }` (preferência, sempre pergunta)
  - `ponte-codex`, `conselho-codex`, `transfer-codex`, `gate-review-codex` → `{ grupo: 'ferramentas', detectar: { executaveis: ['codex'] } }`
  - `ponte-gemini` → `{ grupo: 'ferramentas', detectar: { executaveis: ['gemini'] } }`
  - `conselho-gemini` → `{ grupo: 'ferramentas', detectar: { env: ['GEMINI_API_KEY'] } }`
  - `integracao-whatsapp-mcp` → `{ grupo: 'ferramentas', detectar: { integracao: 'whatsapp-mcp' } }`; `integracao-sabia` → `{ grupo: 'ferramentas', detectar: { integracao: 'sabia' } }` (nome = chave de `INTEGRACOES`)
  - `vigias` → `{ grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } }`
  - `fechar-mergear`, `executar-autonomo` → `{ grupo: 'fechar', detectar: {} }`
  - todas as demais (gates, `fluxo`, `aviso-fluxo`, `poda`, `branch-forcar`, `principal-livre`, `visibilidade-repo`, `pastas`, `codex-modelo-*`, `contrato-veredito`, `agente-folha`, `busca-na-raiz`, `bateria-sem-timeout`, `subagente-*`, `matar-por-nome`) → `entrevista: null`, explícito.
- `scripts/conferir-setup.cjs` (cabeçalho `// @categoria: sensor`) confere: (a) toda chave tem a propriedade própria `entrevista`; (b) `grupo` pertence a `GRUPOS_ENTREVISTA`; (c) `detectar` só usa as formas `executaveis`, `env`, `integracao`, e `integracao` existe em `INTEGRACOES`; (d) sem `--so-catalogo`: o conjunto de chaves da tabela de `skills/setup/SKILL.md` é igual ao do `CHAVES` nos dois sentidos, listando faltantes e sobrantes por nome; (e) sem `--so-catalogo`: a ordem dos subtítulos `###` da seção `## Ordem da entrevista` do SKILL.md casa com `GRUPOS_ENTREVISTA`. Flags `--config <arquivo.json>` (um JSON do `CHAVES` e do `GRUPOS_ENTREVISTA`, não uma cópia do `.cjs` — fora de `hooks/lib/` os `require` relativos dele quebram) e `--skill <arquivo>` para a bateria apontar cópias. Exit 1 com a lista; 0 limpo.

### 2. Vigias por ronda [tipo: implementar]
atende: D6, D12
arquivos: `hooks/lib/config.cjs`, `vigias/run-vigia.ps1`, `scripts/testa-setup.sh`
depende de: 1
prova: `node scripts/setup.cjs --ligado vigia-tickets`
mutacao:
  arquivo: `vigias/run-vigia.ps1`
  de: `$estadoRonda = & node (Join-Path $plugin "scripts\setup.cjs") --ligado $chaveRonda 2>$null`
  para: `$estadoRonda = 'ligado'; $global:LASTEXITCODE = 0`
  bateria: `bash scripts/testa-setup.sh`
  fixture: `testa-setup.sh, bloco "ronda desligada com vigias ligado para limpo"`
pronto quando: com `config.json` de usuário numa caixa de areia contendo `{"vigias":true,"vigia-tickets":false}`, `powershell -File vigias/run-vigia.ps1 -Vigia vigia-tickets` sai 0, imprime que a ronda `vigia-tickets` está desligada e não acrescenta linha ao `ERROS.md`; com o mesmo config, `-Vigia batedor-repos` passa do toggle e para no erro seguinte ("sem destino de envio"); com `{"vigias":true}` sozinho, as cinco rondas passam do toggle — provado por `bash scripts/testa-setup.sh`, nos blocos novos ao lado do bloco 4 existente.

Conteúdo: cinco chaves `vigia-batedor-repos`, `vigia-jardineiro-ideias`, `vigia-revisao-bimestral`, `vigia-sentinela-foco`, `vigia-tickets` — `boolean`, `padrao: true`, `entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } }`. No `run-vigia.ps1`, logo depois do bloco do toggle geral: `$chaveRonda = if ($Vigia -like 'vigia-*') { $Vigia } else { "vigia-$Vigia" }`, a linha do `de:` acima, e o mesmo tratamento do geral (desligado = exit 0 sem ERROS.md; não conseguir perguntar = ERROS.md e exit 1). Mensagem sem travessão (o comentário das linhas 47-52 explica o porquê).

### 3. `setup.cjs --plano-entrevista` [tipo: implementar]
atende: D1, D4, D8, D10, D11
arquivos: `scripts/setup.cjs`, `scripts/testa-setup-entrevista.sh`
depende de: 1, 2
prova: `bash scripts/testa-setup-entrevista.sh`
mutacao:
  arquivo: `scripts/setup.cjs`
  de: `const perguntar = meta.entrevista !== null && detectado !== false;`
  para: `const perguntar = meta.entrevista !== null;`
  bateria: `bash scripts/testa-setup-entrevista.sh`
  fixture: `testa-setup-entrevista.sh, caso "ferramenta ausente no PATH nao vira pergunta"`
pronto quando: com `RFM_ROOT` apontando para pasta vazia e `PATH` sem `codex`, `node scripts/setup.cjs --plano-entrevista` devolve JSON com `primeira_vez: true`, `passos` na ordem de `GRUPOS_ENTREVISTA`, `ponte-codex` com `detectado: false` e `perguntar: false`, nenhuma chave de `entrevista: null` em `passos` e todas elas em `fixas`; com um `CLAUDE_CONFIG_DIR` de caixa cujo `projects/x/sessao.jsonl` repete o formato real (três linhas sem `cwd` antes, depois uma linha `attachment` com `cwd` apontando para um repo git de caixa), `sugestoes.projetos` traz esse caminho, e um `cwd` de pasta inexistente ou sem `.git` não aparece — provado por `bash scripts/testa-setup-entrevista.sh`.

Forma: sai um JSON só no stdout, exit 0, nada gravado. `passos` traz **todos** os grupos de `GRUPOS_ENTREVISTA`, inclusive os sem chave (`dados`, `projetos`, `estrategia`, `foco`) com `chaves: []` — é por eles que a skill anda. A varredura de projetos honra `CLAUDE_CONFIG_DIR` (senão `~/.claude`), lê só o `.jsonl` mais novo de cada pasta de `projects/` e para na primeira linha com `cwd`. O caso "ferramenta ausente" tira `codex` do `PATH` sem tirar o `node`: nesta máquina eles moram em pastas diferentes (`AppData/Roaming/npm` e `Program Files/nodejs`), conferido em 2026-10-17. `primeira_vez` = pasta de dados ausente **ou** `nivel: plugin`. Cada item de chave: `{ chave, valor, origem, detectado, perguntar }`, onde `detectado` é `null` quando `detectar` é `{}`, e senão o resultado de `caminhoExecutavel` / env não-vazio / checador de `INTEGRACOES` (timeout dele próprio). Projetos sugeridos excluem slugs e caminhos já em `projetos.json`. Idioma **não** é sugerido pelo script: quem sugere é a skill, pela língua em que ele está escrevendo (D10).

### 4. `setup.cjs --aplicar <arquivo.json> [--ensaio]` [tipo: implementar]
atende: D5, D9, D11, D13
arquivos: `scripts/setup.cjs`, `scripts/testa-setup-entrevista.sh`, `hooks/lib/config.cjs`

Emenda de 2026-10-17, rodada 2 do `revisar` (achado 6): `hooks/lib/config.cjs` entra para exportar o `validarTipo`, que o `--aplicar` passa a usar em vez de manter uma cópia.
depende de: 3
prova: `bash scripts/testa-setup-entrevista.sh`
mutacao:
  arquivo: `scripts/setup.cjs`
  de: `if (errosAplicar.length > 0) process.exit(2);`
  para: `if (false) process.exit(2);`
  bateria: `bash scripts/testa-setup-entrevista.sh`
  fixture: `testa-setup-entrevista.sh, caso "payload com uma chave invalida nao grava nenhuma"`
pronto quando: com payload `{"chaves":{"ponte-codex":true,"chave-inexistente":true}}`, `--aplicar` sai 2, nomeia `chave-inexistente` no stderr e o `config.json` de usuário fica com o mesmo hash de antes; com payload válido e `--ensaio`, o stdout traz, para cada chave que muda, o nome, o valor antes e o depois (`ponte-codex: false -> true`) e diz se `ESTRATEGIA.md` será criada ou deixada como está, sem mudar hash de arquivo nenhum; sem `--ensaio`, `setup.cjs --ligado ponte-codex` passa a sair 0, o `.rainforest/config.json` do projeto continua inexistente, e um `ESTRATEGIA.md` pré-existente mantém o hash — provado por `bash scripts/testa-setup-entrevista.sh`.

Forma: payload `{ chaves: {<chave>: <valor>}, projetos: [{slug, caminho, apelido?}], estrategia?: "<texto>" }`. Valida tudo primeiro (chave existe, valor bate com o tipo, caminho de projeto existe) acumulando em `errosAplicar`; só depois escreve. Pasta de dados ausente → chama `criar()` antes. Escreve pelo `trocar()` existente com escopo `usuario`, ou `projeto` só com `--escopo projeto` explícito; projetos pelo `registrarProjeto()` existente. `ESTRATEGIA.md` só nasce se ausente, de um `ESTRATEGIA_MODELO` curto com o texto dado, declarado ao lado do `FOCO_MODELO` que o `setup.cjs` já tem (o `scripts/foco.cjs` não tem modelo reaproveitável: o `separar` só divide um FOCO.md existente; a regra de não sobrescrever é a mesma dele). Nunca toca `FOCO.md`. A pessoa lê a saída do `--ensaio` para decidir: o critério acima falha se o valor de antes sumir da linha.

### 5. Skill e comando do setup reescritos como entrevista [tipo: docs]
atende: D1, D2, D3, D5, D7, D8, D9, D10, D13
arquivos: `skills/setup/SKILL.md`, `commands/setup.md`
depende de: 1, 2, 3, 4
mutacao: n/a
  motivo: texto de skill não tem comportamento a inverter; a coerência com o catálogo é conferida pelo `conferir-setup.cjs` da tarefa 1, que já tem mutação própria.
pronto quando: com o `skills/setup/SKILL.md` e o `CHAVES` reais, `node scripts/conferir-setup.cjs` sai 0 (tabela com as 45 chaves nos dois sentidos e a seção `## Ordem da entrevista` com subtítulos na ordem de `GRUPOS_ENTREVISTA`), e a leitura do revisor confirma contra o design: primeira vez = entrevista e setup feito = "refazer ou mudar uma parte" (D1); uma pergunta por turno, "manter / ajustar / refazer" para o que já existe, nada gravado antes de `--aplicar --ensaio` mostrado e aceito, conferência rodando `setup.cjs` de novo e lendo a saída (D5); escopo `usuario` na primeira vez e aviso de commit antes de `projeto` (D9); idioma sugerido pela língua dele e nunca cópia de CLAUDE.md ou memória (D10); estratégia opcional (D13); foco entregue ao `/foco` (D8); gates listados no resumo e não perguntados (D4) — provado por `node scripts/conferir-setup.cjs` e pelo veredito do `revisar`.

### 6. README, CHANGELOG e versão [tipo: docs]
atende: D6, D11
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`

Emenda de 2026-10-17, na abertura do `revisar`: o plano citava `.claude-plugin/marketplace.json`, mas a versão mora nos dois `plugin.json` (Claude e Codex) e no selo do README — medido com `grep -rn 1.67.11` ao executar a tarefa. O `marketplace.json` não foi tocado.
depende de: 5
mutacao: n/a
  motivo: documentação e número de versão; a subida de versão é conferida pelo `conferir-versao.cjs` do CI.
pronto quando: com o diff contra `origin/main`, `node scripts/conferir-versao.cjs` sai 0 com a versão em `1.68.0` nos manifestos; a linha do `/setup` na tabela de comandos do README descreve a entrevista (não mais "liga/desliga gates e fluxo") e o CHANGELOG lista as cinco chaves `vigia-*` com o padrão `true` e os dois modos novos do `setup.cjs` — conferido pelo revisor contra D6 e D11.
