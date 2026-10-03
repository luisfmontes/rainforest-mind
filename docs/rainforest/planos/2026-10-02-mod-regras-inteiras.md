# Plano: abertura inteira (regras, foco e memoria) por mod via prompt.compose

Design: docs/rainforest/design/2026-10-02-mod-regras-inteiras.md

Base: worktree `fluxo/mod-regras-inteiras`, HEAD `14b442fc`, pai `d5d2a203`. Versao publicada hoje: 1.35.2.

## Achados que ajustam o design

1. **D3 nao fecha a conta.** As quatro elaboracoes somam 31.465 B (regra-16 7.551, regra-12 10.491, regra-11 10.121, regra-17 3.302) e o nucleo atual mede 5.914 B: 37.379 B, acima de 32 KB. Decisao A do usuario (abaixo). Este plano esta escrito para A1 (40 KB).
2. **"3000 B do hook" e exato so para a memoria** (`hooks/lib/memoria-sessao.cjs:23`, `MEMORIA_MAX_BYTES: 3000`). O foco tem `ORCAMENTO_BYTES: 8100`, `NUCLEOS_MAX_BYTES: 6000`, `FOCO_MAX_BYTES: 2600` (`hooks/lib/contexto-sessao.cjs:38`); o agregado de `scripts/orcamento.cjs` e 15.600 B. As invariantes usam os numeros reais.
3. **D9 sobre `/clear`:** o `/clear` dispara `session.end` com `reason: 'clear'` e nenhum `session.start` (reference.md:27). A tarefa 6 monta de forma preguicosa e memoizada no primeiro `prompt.compose` e zera o cache no `session.end` com `reason: 'clear'`.
4. **Os traits do `prompt.compose` nao tem "subagente"** (`claude-code.d.ts:7869`). A tarefa 1 mede traits, numero de ferramentas e ids das secoes dentro do subagente.
5. **Claude Code sem mods diante de `modules` no `hooks.json`:** nao medido (so ha o 2.1.288 aqui). Decisao E do usuario.

## O que não pode quebrar

- **Sem mod, a abertura pelo hook sai byte a byte igual a de hoje** (Codex, Claude Code antigo, mod ausente). Prova: `cmp` do stdout inteiro de `hooks/foco-session-start.cjs` e `hooks/memoria-session-start.cjs` contra golden do commit base `d5d2a203`, extraido por `git archive d5d2a203 hooks scripts skills` no scratchpad (nunca `git show ref:caminho`), sobre copia isolada de dados (`RFM_ROOT`).
- **Os orcamentos do hook nao mudam de valor:** `ORCAMENTO_BYTES: 8100`, `NUCLEOS_MAX_BYTES: 6000`, `FOCO_MAX_BYTES: 2600`, `FOCO_MIN_BYTES: 700`, `MEMORIA_MAX_BYTES: 3000`. `node scripts/orcamento.cjs --agregado` e a secao 1c de `scripts/testa-orcamento.sh` seguem verdes sem edicao.
- **A secao `hooks` do `hooks/hooks.json` fica intacta;** so entra a chave `modules`. Prova: `deepStrictEqual` entre o `hooks` do base e o do HEAD.
- **Falha do mod e falha aberta:** gerador com exit != 0, JSON invalido ou timeout faz o mod devolver `next(e)` sem alterar nada e sem remover as entradas do SessionStart.
- **O filtro do `classic.SessionStart` so remove o que os dois hooks da abertura emitiram;** a entrada do `hooks/codex-transfer-session-start.cjs` e de qualquer outro hook fica.
- **Codex nao muda:** `.codex-plugin/plugin.json` so muda de versao; `node scripts/contrato-plugin-codex.cjs` passa antes e depois.
- **`varrer-baterias` nao depende do binario `claude`** (CI: `.github/workflows/baterias.yml:164`). A logica do mod vive em `.mjs` puro testado em Node; `claude plugin test` e os e2e sao prova local, em arquivo sem prefixo `testa-`.
- **O canario da tarefa 1 e inerte sem `RFM_CANARIO_MOD`.**
- **O ambiente do usuario nao muda:** sem `CLAUDE_CODE_PLUGIN_DIRS`, sem edicao de settings. Atualizar o plugin instalado e acao do usuario.
- **`skills/rainforest-mind/references/regra-*.md` nao sao editados** (`regra-12.md` esta a 9 B do teto `REFERENCE_MAX_BYTES: 10500`).
- **`claude plugin validate <raiz do repo>` sai 0** depois de cada tarefa que toca `hooks/hooks.json` ou `hooks/*.mjs|ts`.

## Ordem e paradas

Todas as tarefas dependem da 1, entao todas sao `paralela: nao`. Nota para humano: depois da 2, as tarefas 3, 4 e 5 nao dividem arquivo e podem ser despachadas juntas.

- **PARADA 1, depois da tarefa 1:** o `executar` nao segue ate (1) o PR da tarefa 1 passar na CI e ser mesclado (janela principal); (2) o usuario rodar `claude plugin update` (CONTRIBUTING.md:147); (3) a medicao rodar em sessao nova pelo marketplace, sem `--plugin-dir`, e passar. Se falhar, o fluxo volta ao usuario com a saida colada. Na mesma parada o usuario decide B (politica de subagente).
- **PARADA 2, antes da tarefa 7:** decisao B registrada.

## Decisões do usuário

Respondidas em 2026-10-02:
- **A. Orcamento das regras: 40 KB (40.960 B)**, as quatro elaboracoes (16, 12, 11, 17). A r11 e a terceira mais citada; a tarefa 1 mede ate 48.000 chars.
- **C. Chave para desligar o mod: nao agora.** O hook atual ja e a reserva; se o mod atrapalhar, vira tarefa pequena no `/setup`.
- **D. Teto do foco no destino mod: 12.288 B** (FOCO.md real tem 8.905 B; a bateria de orcamento avisa se crescer).
- **E. Claude Code antigo com `modules`: risco aceito.** O plugin roda nas duas contas do usuario, ambas na 2.1.288 e com auto-update.

Pendente:
- **B. O mod entrega a abertura ao subagente?** Decide-se na Parada 1, com a medicao da tarefa 1.

## Tarefas

### 1. Prova de carregamento pelo marketplace: mod canario no plugin real e medicao no prompt de subagente [tipo: pesquisar]
atende: D10
arquivos: `hooks/hooks.json`, `hooks/register.ts`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: nenhuma
paralela: nao
mutacao: n/a
  motivo: tarefa de medicao em sessao real; a falsificacao e o controle sem `RFM_CANARIO_MOD`, que tem de devolver `NENHUM`. O codigo definitivo do mod nasce na tarefa 6.

Passos:
1. Branch `fluxo/mod-regras-inteiras-canario` a partir de `origin/main` (a versao tem de sair antes do resto).
2. `hooks/hooks.json` ganha a chave `modules` com `./register.ts`, `hooks` intacto.
3. `hooks/register.ts`: o prototipo medido, acrescentando a secao so quando `$.env.get("RFM_CANARIO_MOD")` vier nao vazio; id `rainforest-mind:canario`, escopo `session`, >= 49.000 chars com canarios `RF-TETO-CANARIO-1024/3072/16384/32000/40000/48000`, mais as linhas `RF-TETO-TRAITS-<e.traits unidos por +>`, `RF-TETO-TOOLS-<e.tools.length>` e `RF-TETO-IDS-<ids das secoes de next(e) unidos por +>`.
4. `claude plugin validate <raiz do repo>` sai 0.
5. Versao 1.36.0 (MINOR) em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, badge do `README.md` e nota no `CHANGELOG.md`, em commit proprio `Versao 1.36.0: ...`, ultimo do lote; `node scripts/conferir-versao.cjs` sai 0.

**PARA aqui** (Parada 1). Medicao, em sessao nova com o plugin pelo marketplace e sem `--plugin-dir` (conferir antes a versao ativa no cache da conta):
- Principal: `RFM_CANARIO_MOD=1 claude -p --model haiku "Procure no seu system prompt linhas no formato RF-TETO-CANARIO-<numero>. Responda SO com os numeros, ou NENHUM."`
- Controle: o mesmo comando sem a variavel.
- Subagente: `RFM_CANARIO_MOD=1 claude -p --model haiku "Use a ferramenta Agent com subagent_type general-purpose e este prompt: 'Procure no seu system prompt linhas no formato RF-TETO-<palavra>-<valor>. Responda SO com as linhas, ou NENHUM.' Devolva a resposta do subagente literal."`

pronto quando: com o plugin 1.36.0 instalado pelo marketplace numa sessao nova sem `--plugin-dir`, o comando principal com `RFM_CANARIO_MOD=1` devolve `1024, 3072, 16384, 32000, 40000, 48000`, o controle sem a variavel devolve `NENHUM`, e o comando de subagente devolve ou as linhas `RF-TETO-*` (colar TRAITS, TOOLS e IDS do subagente ao lado dos da principal) ou `NENHUM` — qualquer dos dois fecha a tarefa, com as tres saidas coladas na evidencia e no PR. Provado por `RFM_CANARIO_MOD=1 claude -p --model haiku "<prompt principal>"` devolvendo os seis numeros e `claude -p --model haiku "<prompt principal>"` devolvendo `NENHUM`.

### 2. Configuracao fixa das elaboracoes e dos orcamentos do destino mod [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/abertura-mod.json`, `hooks/lib/abertura-mod.cjs`, `hooks/testa-abertura-mod-config.sh`
depende de: 1
paralela: nao
prova: `bash hooks/testa-abertura-mod-config.sh`
mutacao:
  arquivo: `hooks/lib/abertura-mod.cjs`
  de: `if (soma > cfg.orcamentoTotalBytes) throw new Error(`
  para: `if (false) throw new Error(`
  bateria: `bash hooks/testa-abertura-mod-config.sh`
  fixture: `testa-abertura-mod-config.sh, caso "partes somam mais que o total declarado e recusado"`
pronto quando: com o `hooks/abertura-mod.json` real do repo, a lib devolve elaboracoes `[16,12,11,17]`, regras 40960, foco 12288, memoria 8192 e total 61440, cada regra resolve para um `skills/rainforest-mind/references/regra-NN.md` existente, e a soma das elaboracoes (31.465 B) mais o nucleo medido (5.914 B) cabe em `orcamentoRegrasBytes`; com um JSON cuja soma das partes passa de `orcamentoTotalBytes`, ou com uma regra sem arquivo, a lib recusa dizendo o campo e a regra. Provado por `bash hooks/testa-abertura-mod-config.sh`, que roda a lib contra o JSON real e contra duas copias adulteradas e sai 0 so quando as duas adulteradas sao recusadas.

Nota: o `de:` e texto que a propria tarefa escreve (o arquivo ainda nao existe). O JSON tem as chaves `elaboracoes`, `orcamentoRegrasBytes`, `orcamentoFocoBytes`, `orcamentoMemoriaBytes`, `orcamentoTotalBytes`; o total e a soma exata das tres partes. Zero `skipped`.

### 3. Destino mod no gerador do foco: regras com elaboracao inteira, foco sem corte, dependencias [tipo: implementar]
atende: D3, D6, D8
arquivos: `hooks/lib/contexto-sessao.cjs`, `hooks/foco-session-start.cjs`, `hooks/testa-abertura-mod-foco.sh`
depende de: 2
paralela: nao
prova: `bash hooks/testa-abertura-mod-foco.sh`
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: `const tetos = o.destino === 'mod' ? { ...TETOS, ...o.tetosMod } : TETOS;`
  para: `const tetos = TETOS;`
  bateria: `bash hooks/testa-abertura-mod-foco.sh`
  fixture: `testa-abertura-mod-foco.sh, caso "destino mod entrega a elaboracao inteira das quatro regras"`
pronto quando: com `RFM_ROOT` numa copia do `~/.rainforest` real (FOCO.md de 8.905 B) e as `references/` reais, `node hooks/foco-session-start.cjs --destino mod` emite JSON cujo `additionalContext` contem verbatim a primeira e a ultima linha de cada um dos quatro `regra-NN.md` e o FOCO.md inteiro, sem o aviso "O foco não coube" e sem marca de corte, com <= 53.248 B, e o cabecalho deixa de dizer "Isto é o NÚCLEO" e nomeia as regras que vem inteiras; sem a flag, o stdout e identico (`cmp`) ao golden do commit base `d5d2a203`; com a config recusada pela lib da tarefa 2, sai com exit != 0, stderr nao vazio e sem JSON parcial. Provado por `bash hooks/testa-abertura-mod-foco.sh`, que monta o golden por `git archive d5d2a203 hooks scripts skills` no scratchpad.

Nota: o destino mod parametriza os pontos onde os TETOS entram em `montarContexto` (`contexto-sessao.cjs:1167`, `:1188`, `:1196`, `:1205`, `:1206`, `travarOrcamento` em `:1053`); ler antes de editar. Mesma `montarContexto`, sem reescrever a montagem.

### 4. Destino mod no gerador da memoria: 8 KB, sem o corte por linha [tipo: implementar]
atende: D5, D8
arquivos: `hooks/lib/memoria-sessao.cjs`, `hooks/memoria-session-start.cjs`, `hooks/testa-abertura-mod-memoria.sh`
depende de: 2
paralela: nao
prova: `bash hooks/testa-abertura-mod-memoria.sh`
mutacao:
  arquivo: `hooks/lib/memoria-sessao.cjs`
  de: `const tetoBytes = Number.isInteger(o?.tetoBytes) ? o.tetoBytes : TETOS.MEMORIA_MAX_BYTES;`
  para: `const tetoBytes = TETOS.MEMORIA_MAX_BYTES;`
  bateria: `bash hooks/testa-abertura-mod-memoria.sh`
  fixture: `testa-abertura-mod-memoria.sh, caso "14 observacoes com subtitulo longo chegam inteiras no destino mod"`
pronto quando: com um banco de memoria de 14 observacoes vivas, cada uma com subtitulo >= 190 B e rotulo de projeto real, `node hooks/memoria-session-start.cjs --destino mod` emite um `additionalContext` com as 14 linhas, nenhuma terminando em `…`, com <= 8.192 B; sem a flag, no mesmo banco, a saida e identica ao golden do commit base `d5d2a203` e cortada pela escada atual; e o `systemMessage` e o mesmo nos dois destinos. Provado por `bash hooks/testa-abertura-mod-memoria.sh`.

Nota: a fixture segue o idioma de `hooks/testa-memoria-session-start.sh`; nunca o banco vivo do usuario.

### 5. Script que sugere a nova lista de elaboracoes a partir das observacoes [tipo: implementar]
atende: D4
arquivos: `scripts/sugerir-elaboracoes.cjs`, `scripts/testa-sugerir-elaboracoes.sh`
depende de: 2
paralela: nao
prova: `bash scripts/testa-sugerir-elaboracoes.sh`
mutacao:
  arquivo: `scripts/sugerir-elaboracoes.cjs`
  de: `.sort((a, b) => b[1] - a[1] || a[0] - b[0])`
  para: `.sort((a, b) => a[0] - b[0])`
  bateria: `bash scripts/testa-sugerir-elaboracoes.sh`
  fixture: `testa-sugerir-elaboracoes.sh, caso "ranking por citacoes: r16 antes de r12 antes de r11"`
pronto quando: com um `ideias.jsonl` (formato real, somente leitura) em que as linhas `"tipo":"observacao"` citam a regra 16 trinta vezes, a 12 vinte e oito, a 11 dezessete e a 17 catorze, o script imprime as regras nessa ordem com as contagens, marca quais ja estao em `hooks/abertura-mod.json`, e nao altera nenhum arquivo (hash de `hooks/abertura-mod.json` e do `ideias.jsonl` iguais antes e depois). Provado por `bash scripts/testa-sugerir-elaboracoes.sh`.

Nota: a fonte e a mesma da medicao do design: linhas `tipo: observacao` do `ideias.jsonl` (via `scripts/ideias.cjs`/raiz de dados), contando cada regra uma vez por observacao pelo padrao `regra[s]? ?N` (1 a 17). Rodado a mao (D4); nunca chamado por hook.

### 6. Mod definitivo: secao `rainforest-mind:abertura`, remocao da entrada do SessionStart, montagem unica [tipo: implementar]
atende: D1, D2, D7, D8, D9
arquivos: `hooks/register.ts`, `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura.cjs`, `hooks/mod-abertura.test.ts`
depende de: 3, 4
paralela: nao
prova: `node hooks/testa-mod-abertura.cjs`
mutacao:
  arquivo: `hooks/abertura-mod-puro.mjs`
  de: `if (memo) return memo;`
  para: `if (false) return memo;`
  bateria: `node hooks/testa-mod-abertura.cjs`
  fixture: `testa-mod-abertura.cjs, caso "tres composes, um unico par de $.process.run"`
pronto quando: com as saidas JSON reais dos dois geradores (`--destino mod`, sobre a copia do `~/.rainforest` real) e as entradas reais de `additionalContext` que os hooks atuais emitem no SessionStart, o mod registra exatamente `session.end`, `prompt.compose` e `classic.SessionStart`; acrescenta uma unica secao `{ id: 'rainforest-mind:abertura', scope: 'session' }` ao fim de `sections`, montada uma vez (3 composes seguidos chamam `$.process.run` so 2 vezes) e remontada depois de `session.end` com `reason: 'clear'`; em `classic.SessionStart` remove so as entradas dos dois hooks da abertura e mantem a do `codex-transfer-session-start.cjs`; e com gerador saindo != 0, JSON invalido ou timeout devolve `next(e)` intacto sem remover nada. Provado por `node hooks/testa-mod-abertura.cjs` (importa o `.mjs` e injeta um `$` falso); prova local de engine: `claude plugin test <raiz do repo>` rodando `hooks/mod-abertura.test.ts` e `claude plugin validate <raiz do repo>` saindo 0.

Notas: geradores por `$.process.run` com `node <raiz do plugin>/hooks/foco-session-start.cjs --destino mod`, `CLAUDE_PROJECT_DIR` explicito e `timeoutMs: 60000` (o hook do foco ja levou 6-8 s, issue #243). O filtro reconhece as entradas pelos prefixos reais dos dois hooks (`RAINFOREST MIND ATIVO`; o cabecalho e os avisos da memoria), fixados em constante e testados contra a saida real em tres cenarios (memoria normal, so aviso, foco so com ponteiro). O canario da tarefa 1 sai no mesmo commit.

### 7. Filtro do prompt de subagente, segundo a decisao B [tipo: implementar]
atende: D2, D9
arquivos: `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura.cjs`, `hooks/mod-abertura.test.ts`
depende de: 6
paralela: nao
prova: `node hooks/testa-mod-abertura.cjs`
mutacao:
  arquivo: `hooks/abertura-mod-puro.mjs`
  de: `if (!entregaNestePrompt(e)) return resultado;`
  para: `if (false) return resultado;`
  bateria: `node hooks/testa-mod-abertura.cjs`
  fixture: `testa-mod-abertura.cjs, caso "prompt de subagente nao recebe a secao"`
pronto quando: com `e.traits`, `e.tools` e ids de secao iguais aos medidos dentro do subagente na tarefa 1, o mod devolve as `sections` sem `rainforest-mind:abertura` e sem chamar `$.process.run`; com os valores medidos da sessao principal, acrescenta; e em sessao real, `claude -p --plugin-dir <raiz> --model haiku` pedindo a um subagente as ocorrencias de `RAINFOREST MIND ATIVO` no seu system prompt devolve `NENHUM`. Provado por `node hooks/testa-mod-abertura.cjs` e pelo comando de subagente. Se a tarefa 1 mostrar que a secao nao chega ao subagente, a tarefa fecha como nao aplicavel com a medicao colada; se o usuario escolher outra politica em B, ou nao houver discriminante, a tarefa nao comeca e o plano volta ao estagio `plano`.

### 8. A bateria de orcamento aprende o destino mod [tipo: implementar]
atende: D11
arquivos: `scripts/orcamento.cjs`, `scripts/exporta-hooks-sessao-start.cjs`, `scripts/testa-orcamento.sh`
depende de: 3, 4
paralela: nao
prova: `node scripts/orcamento.cjs --agregado --destino mod | grep -q "SessionStart mod (additionalContext agregado)"`
mutacao:
  arquivo: `scripts/orcamento.cjs`
  de: `process.exit(avaliacaoMod.estado === 'estouro' ? 1 : 0);`
  para: `process.exit(0);`
  bateria: `bash scripts/testa-orcamento.sh`
  fixture: `testa-orcamento.sh, nova secao "destino mod: soma das partes acima do total declarado estoura"`
pronto quando: com `RFM_ROOT` numa copia do `~/.rainforest` real, `node scripts/orcamento.cjs --agregado --destino mod` executa os dois geradores com `--destino mod` pelo mesmo `executarHooksSessionStart`, soma os `additionalContext`, compara com `orcamentoTotalBytes` lido de `hooks/abertura-mod.json` e sai 0 com a linha `SessionStart mod (additionalContext agregado): <N> B / teto 61440 B`; com uma copia do JSON cuja soma das partes passa do total, sai 1; e `--agregado` sem `--destino` da o mesmo resultado de hoje, com as secoes existentes de `testa-orcamento.sh` (inclusive a 1c) verdes. Provado por `bash scripts/testa-orcamento.sh` e por `node scripts/orcamento.cjs --agregado --destino mod` nos dois desfechos.

### 9. Verificacao pela saida real: canario e2e com o plugin local e controle sem ele [tipo: pesquisar]
atende: D12
arquivos: nenhum
depende de: 6, 7, 8
paralela: nao
mutacao: n/a
  motivo: tarefa de medicao; a falsificacao sao o controle sem o mod e a contagem exata de ocorrencias, dentro do proprio comando.
pronto quando: numa sessao nova com o plugin deste worktree (`claude -p --plugin-dir <worktree> --model haiku`), o prompt "Liste os cabecalhos `# Regra NN —` do seu contexto e quantas vezes aparece a frase `Isto é o NÚCLEO das regras`" devolve os de 16, 12, 11 e 17 e a frase 0 vezes, e uma frase conhecida do FOCO.md alem dos primeiros 2.600 B e uma linha de memoria aparecem; o mesmo prompt sem `--plugin-dir` devolve a frase 1 vez e nenhum cabecalho elaborado. Provado por esses dois comandos `claude -p`, com as saidas coladas.

Nota: se `--plugin-dir` nao sobrepuser o plugin instalado de mesmo nome, a medicao fica para a tarefa 11 e a tarefa 9 registra isso. `$.prompt.compose()` chamado de comando nao vale como prova.

### 10. Documentacao do destino mod [tipo: docs]
atende: D3, D6, D7
arquivos: `CONTRIBUTING.md`, `README.md`
depende de: 9
paralela: nao
mutacao: n/a
  motivo: tarefa de documentacao, sem comportamento a inverter; a falsificacao e a coerencia com o design e com `hooks/abertura-mod.json`.
pronto quando: o paragrafo novo de "Regra e injeção" em `CONTRIBUTING.md` diz que sem mod o hook entrega o nucleo com `NUCLEOS_MAX_BYTES` de 6.000 B como hoje, que com mod as elaboracoes da lista fixa de `hooks/abertura-mod.json` chegam inteiras e o hook fica de reserva sem duplicar (D7), que lista e orcamentos moram nesse JSON e `scripts/sugerir-elaboracoes.cjs` so sugere; os numeros do texto sao os do JSON e os tetos do hook sao os valores atuais; e o `README.md` aponta o requisito de Claude Code 2.1.287+ e o que acontece sem ele. Provado por um `node -e` que le `hooks/abertura-mod.json` e os `TETOS` exportados de `hooks/lib/contexto-sessao.cjs` e `hooks/lib/memoria-sessao.cjs`, extrai os numeros do paragrafo e sai 1 se algum divergir.

### 11. Versao 1.37.0, CHANGELOG, publicacao e medicao final [tipo: configurar]
atende: D12
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 10
paralela: nao
mutacao: n/a
  motivo: tarefa de configuracao de versao; quem prova o efeito e a medicao em sessao nova pelo marketplace.
pronto quando: com a versao 1.37.0 em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` e no badge do `README.md`, e a nota no topo de `CHANGELOG.md` no commit `Versao 1.37.0: ...` (ultimo do lote), `node scripts/conferir-versao.cjs` sai 0; e, depois do PR mesclado e do `claude plugin update` feito pelo usuario, numa sessao nova instalada pelo marketplace e sem `--plugin-dir`, o prompt da tarefa 9 devolve os cabecalhos das regras 16, 12, 11 e 17 e a frase do nucleo 0 vezes. Provado por `node scripts/conferir-versao.cjs` e pelo comando `claude -p` da tarefa 9 sem `--plugin-dir`.

## Cobertura

D1 → 6. D2 → 6, 7. D3 → 2, 3, 10. D4 → 2, 5. D5 → 2, 4. D6 → 3, 10. D7 → 6, 10. D8 → 3, 4, 6. D9 → 6, 7. D10 → 1. D11 → 8. D12 → 9, 11.

## Lacunas conhecidas

- Comportamento de Claude Code sem mods diante de `modules` no `hooks.json` (decisao E).
- Se `--plugin-dir` sobrepoe um plugin instalado de mesmo nome (tarefas 1 e 9).
- Se um `prompt.compose` pode disparar antes do `session.start` (por isso a montagem e preguicosa).
- Se `node` esta no PATH do `$.process.run` e se `CLAUDE_PROJECT_DIR` chega ao filho (a tarefa 6 passa explicito).
- Onde `claude plugin test` procura `*.test.ts` e se aceita import de `.mjs`.
