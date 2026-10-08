# Plano: Memória escolhida pelo assunto — pedido, subagente e antes/depois

Design: docs/rainforest/design/2026-10-08-memoria-por-assunto.md

## O que não pode quebrar
- A abertura não muda (D2): `git diff origin/main -- hooks/memoria-session-start.cjs hooks/lib/memoria-sessao.cjs hooks/abertura-mod-puro.mjs` vazio no fim do fluxo.
- Nenhum hook novo bloqueia ou atrasa o pedido do usuário além do timeout declarado; toda falha sai com exit 0 e stdout vazio (D6).
- O `updatedInput` do hook de `Agent` preserva `description`, `subagent_type`, `model` e qualquer outro campo do `tool_input` original, e a `portaria.cjs` (mesmo matcher `Task|Agent`) continua lendo o manifesto do briefing como hoje.
- Nenhum texto de sessão entra no banco (D10): `uso_memoria` e `uso_memoria_sessoes` só ganham colunas de enumeração/contagem.
- A medição da abertura continua idêntica: as notas já gravadas em `uso_memoria` não são recalculadas, e linha antiga sem canal lê como `abertura`.

## Tarefas

### 1. Prova do harness: onde o `additionalContext` do `UserPromptSubmit` e o `updatedInput` do `Agent` aparecem [tipo: pesquisar]
atende: D1, D5, D8
arquivos: `docs/rainforest/referencia/2026-10-08-harness-prompt-e-agent.md`, `scripts/fixtures/memoria-assunto/prompt-submit.jsonl`, `scripts/fixtures/memoria-assunto/agente-pai.jsonl`, `scripts/fixtures/memoria-assunto/agente-filho.jsonl`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa sobre o comportamento do harness; não há código do repo a inverter, a falsificação é a saída real do `claude -p` colada.
pronto quando: com `claude -p` headless rodando num diretório de sandbox do scratchpad e `--settings <arquivo temporário>` declarando (a) um `UserPromptSubmit` que emite `hookSpecificOutput.additionalContext` com a marca `MARCA-ASSUNTO-7f3` e (b) um `PreToolUse` matcher `Agent` que devolve `updatedInput` com o `prompt` original + `MARCA-AGENTE-9c1` e os demais campos intactos, o documento registra, com comando e saída colados: o `type`/campo exato da linha do transcrito que carrega `MARCA-ASSUNTO-7f3`; se o subagente **recebeu** `MARCA-AGENTE-9c1` (o subagente é instruído a repetir a última linha do briefing, e a resposta dele é colada); em qual arquivo/linha do transcrito (pai e/ou `subagents/`) a marca aparece; e o veredito `D5: updatedInput VALE` ou `D5: cai para SubagentStart`. O documento registra também, numa linha própria, se o `updatedInput` é aplicado **sem** `permissionDecision` (`D5-permissao: sem permissionDecision VALE` ou `D5-permissao: exige allow`): se só vale com `allow`, o hook aprovaria em silêncio toda chamada de `Agent` de todo usuário do plugin, e o veredito de D5 passa a ser `D5: cai para SubagentStart`. A sessão headless roda com `RFM_ROOT=<sandbox>` para que heartbeat e captura de memória gravem no sandbox, não na raiz real. As três fixtures são linhas copiadas desses transcritos reais (sem edição de campo) — provado por `node -e "const fs=require('fs');for(const f of ['prompt-submit','agente-pai','agente-filho']){const t=fs.readFileSync('scripts/fixtures/memoria-assunto/'+f+'.jsonl','utf8');t.trim().split('\n').forEach(l=>JSON.parse(l));console.log(f,/MARCA-(ASSUNTO-7f3|AGENTE-9c1)/.test(t))}"` imprimindo `true` nas fixtures em que o documento diz que a marca aparece, e `grep -E '^D5: (updatedInput VALE|cai para SubagentStart)$' docs/rainforest/referencia/2026-10-08-harness-prompt-e-agent.md` devolvendo uma linha, e `grep -E '^D5-permissao: (sem permissionDecision VALE|exige allow)$'` no mesmo documento devolvendo uma linha. Nenhuma config nem dado do usuário é tocado: o mtime dos dois `settings.json` (`~/.claude/settings.json`, `~/.claude-personal/settings.json`) e o tamanho + mtime de `~/.rainforest/rainforest.db` e `~/.rainforest/sessoes.json`, capturados antes da primeira rodada headless, são iguais aos de depois da última, com as duas leituras coladas.

### 2. Calibrar o limiar bm25 nos transcritos reais [tipo: pesquisar]
atende: D3, D7
arquivos: `docs/rainforest/referencia/2026-10-08-limiar-memoria-assunto.md`, `scripts/calibrar-limiar-assunto.cjs`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa que produz um número; o script é instrumento de medição descartável, sem comportamento de produção a inverter.
pronto quando: com uma **cópia** do `~/.rainforest/rainforest.db` real (no scratchpad, aberta somente-leitura) e os transcritos das sessões já pontuadas em `uso_memoria_sessoes`, o script roda, para cada pedido digitado do usuário, a mesma busca FTS/bm25 em todos os projetos que a tarefa 3 vai usar, e pontua cada candidata com `calcularNota` (`scripts/lib/utilidade.cjs:315`) contra o texto **posterior** ao pedido (D8), e só considera candidatas com `criada_em` **anterior** ao timestamp do pedido — sem esse filtro o limiar se calibraria em memória que o hook ainda não teria. O documento registra a tabela limiar × (fração de injeções com nota ≥ 0,5, média de memórias injetadas por pedido, fração de pedidos sem injeção) para pelo menos 5 limiares, o limiar escolhido com o porquê numa linha, e o número de sessões e pedidos usados — provado por `node scripts/calibrar-limiar-assunto.cjs --db <cópia> --limiares -2,-4,-6,-8,-10` imprimindo a tabela com 5 linhas e um total de pedidos > 0, e `grep -E '^LIMIAR_BM25 = -?[0-9]+(\.[0-9]+)?$' docs/rainforest/referencia/2026-10-08-limiar-memoria-assunto.md` devolvendo uma linha. O documento não cita conteúdo de observação nem nome de projeto de trabalho (repo público): só números.

### 3. Busca por assunto: lib pura com peso do projeto, deduplicação e teto [tipo: implementar]
atende: D3, D4, D6
arquivos: `hooks/lib/memoria-assunto.cjs`, `hooks/testa-memoria-assunto.cjs`
depende de: 2
paralela: nao
prova: `node hooks/testa-memoria-assunto.cjs`
mutacao:
  arquivo: `hooks/lib/memoria-assunto.cjs`
  de: `const candidatas = linhas.filter((l) => !jaServidos.has(l.id));`
  para: `const candidatas = linhas;`
  bateria: `node hooks/testa-memoria-assunto.cjs`
  fixture: `testa-memoria-assunto.cjs, caso "memoria ja servida na sessao nao volta"`
pronto quando: com um banco de caixa de teste criado pelo `criarSchema` real de `scripts/memoria.cjs` (observações de dois projetos, uma consolidada, uma substituída), `buscarPorAssunto(conexao, texto, { projetoAtual, jaServidos, max: 3, limiar: LIMIAR_BM25 })` devolve no máximo 3 linhas, nunca uma consolidada/substituída/já servida, só candidatas com bm25 ≤ `LIMIAR_BM25` (o número da tarefa 2, numa constante exportada), e com empate de relevância a do `projetoAtual` vem primeiro; texto sem termo acima do limiar devolve `[]`; e `montarBlocoAssunto(linhas)` começa por `## Memória do assunto`, formata cada linha com `formatarObservacao` (`hooks/lib/memoria-sessao.cjs:188`) e fica ≤ 1.500 bytes — provado por `node hooks/testa-memoria-assunto.cjs` imprimindo uma linha `ok` por caso e `0 falha(s)`. O filtro de já servidas é **uma expressão só**, na forma do `de:` acima; nenhum caso de teste lê o texto do fonte.

### 4. Hook de `UserPromptSubmit` que injeta a memória do assunto [tipo: implementar]
atende: D1, D2, D3, D6, D10
arquivos: `hooks/memoria-assunto-prompt.cjs`, `hooks/testa-memoria-assunto-prompt.cjs`, `hooks/hooks.json`
depende de: 1, 3
paralela: nao
prova: `node hooks/testa-memoria-assunto-prompt.cjs`
mutacao:
  arquivo: `hooks/memoria-assunto-prompt.cjs`
  de: `process.exitCode = 0;`
  para: `process.exitCode = 1;`
  bateria: `node hooks/testa-memoria-assunto-prompt.cjs`
  fixture: `testa-memoria-assunto-prompt.cjs, caso "banco ausente sai 0 e calado"`
pronto quando: com o **payload real** de `UserPromptSubmit` (campos `prompt`, `session_id`, `cwd`, `transcript_path`, `hook_event_name`, no formato registrado pela tarefa 1) no stdin e `RFM_ROOT` apontando para uma raiz de caixa de teste com banco, o hook sai 0 com `hookSpecificOutput.additionalContext` contendo `## Memória do assunto` e no máximo 3 linhas; a segunda chamada na mesma sessão, com o mesmo pedido, não repete nenhuma memória (ids guardados num arquivo por sessão sob a raiz de dados, só ids — D10); a primeira chamada não repete memória que o bloco da abertura já serviu (o conjunto `jaServidos` nasce das servidas do `attachment` de `SessionStart` do `transcript_path`, resolvidas para id por `extrairLinhasServidas` e `acharAlvo` de `scripts/lib/utilidade.cjs`), com caso próprio na bateria; pedido que começa por `/` ou tem menos de 3 termos úteis não injeta; banco ausente, banco travado (`database is locked`), FTS ausente e stdin inválido saem 0 com stdout vazio; `hooks/hooks.json` registra o hook em `UserPromptSubmit`, síncrono, com `timeout` ≤ 5, sem remover o `heartbeat.cjs` — provado por `node hooks/testa-memoria-assunto-prompt.cjs` imprimindo `ok` por caso e `0 falha(s)`, e por `node -e "const h=require('./hooks/hooks.json');const u=JSON.stringify(h.hooks?h.hooks.UserPromptSubmit:h.UserPromptSubmit);console.log(/memoria-assunto-prompt/.test(u),/heartbeat/.test(u))"` imprimindo `true true`. A abertura fica intacta: `git diff origin/main -- hooks/memoria-session-start.cjs hooks/lib/memoria-sessao.cjs` vazio. Forma do alvo de mutação (código a nascer): o código de saída do hook se define numa única atribuição `process.exitCode = 0;` no fim do caminho de falha, sem ramo nem `process.exit` direto; nenhum caso de teste lê o texto do fonte.

### 5. Memória do assunto no briefing do subagente [tipo: implementar]
atende: D5, D6
arquivos: `hooks/memoria-assunto-agente.cjs`, `hooks/testa-memoria-assunto-agente.cjs`, `hooks/hooks.json`
depende de: 1, 3, 4
paralela: nao
prova: `node hooks/testa-memoria-assunto-agente.cjs`
mutacao:
  arquivo: `hooks/memoria-assunto-agente.cjs`
  de: `process.exitCode = 0;`
  para: `process.exitCode = 1;`
  bateria: `node hooks/testa-memoria-assunto-agente.cjs`
  fixture: `testa-memoria-assunto-agente.cjs, caso "falha sai 0 e calada"`
pronto quando: no ramo que a tarefa 1 decidir — **se `D5: updatedInput VALE`**: com o payload real de `PreToolUse` da ferramenta `Agent` (formato da fixture `agente-pai.jsonl`) no stdin, o hook sai 0 com `hookSpecificOutput.updatedInput` igual ao `tool_input` original em todo campo exceto `prompt`, e `prompt` = original + `\n\n` + bloco `## Memória do assunto` buscado pelo texto do briefing; briefing sem candidata acima do limiar sai 0 sem `updatedInput`; a `portaria.cjs` alimentada com o `prompt` resultante decide igual à alimentada com o original (mesmo exit e mesmo stdout); o caso "updatedInput preserva description, subagent_type e model" fica vermelho se o objeto montado perder qualquer campo do original; registrado em `hooks/hooks.json` no matcher `Agent` (hooks do mesmo matcher rodam em paralelo — a portaria lê o `prompt` original, então a ordem não importa). **Se `D5: cai para SubagentStart`**: o mesmo hook atende `SubagentStart`, buscando pelo `agent_type` mais o último pedido digitado da sessão (lido do `transcript_path`), e emite `additionalContext` com o bloco; o `escada-subagente.cjs` continua emitindo a escada. Nos dois ramos, falha sai 0 calada — provado por `node hooks/testa-memoria-assunto-agente.cjs` imprimindo `ok` por caso e `0 falha(s)`, com o ramo testado nomeado na primeira linha (`ramo: updatedInput` ou `ramo: SubagentStart`) e igual ao veredito da tarefa 1. Forma do alvo de mutação (código a nascer, igual nos dois ramos): o código de saída se define numa única atribuição `process.exitCode = 0;` no fim do caminho de falha; nenhum caso de teste lê o texto do fonte.

### 6. Extrator e pontuação com canal, sem nota tautológica [tipo: implementar]
atende: D8, D10
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`, `scripts/testa-utilidade-canais.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-utilidade-canais.sh`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const textoPosterior = partesTexto.slice(indiceInjecao + 1).join('\n');`
  para: `const textoPosterior = partesTexto.slice(indiceInjecao).join('\n');`
  bateria: `bash scripts/testa-utilidade-canais.sh`
  fixture: `testa-utilidade-canais.sh, caso "nota do canal pedido exclui o pedido que disparou"`
pronto quando: com as fixtures **reais** da tarefa 1 (`prompt-submit.jsonl`, `agente-pai.jsonl`, `agente-filho.jsonl`) montadas num transcrito de caixa de teste, `extrairSessao` devolve as servidas de cada canal (`abertura`, `pedido`, `subagente`) e `pontuarSessao` grava em `uso_memoria` uma linha por servida com a coluna `canal` preenchida; a nota de uma servida do canal `pedido` cujo único casamento é o próprio pedido que a disparou é `0`, e passa a > 0 quando um pedido posterior ou `tool_use` posterior contém os termos raros dela; um banco antigo sem a coluna migra (`ALTER TABLE ... ADD COLUMN canal TEXT NOT NULL DEFAULT 'abertura'`) sem perder linha e as linhas antigas leem como `abertura`; `PRAGMA table_info(uso_memoria)` não mostra coluna de texto livre nova — provado por `bash scripts/testa-utilidade-canais.sh` imprimindo `ok` por caso e `0 falha(s)`, e `bash scripts/testa-utilidade.sh` continuando com o mesmo placar de `origin/main`. Forma do alvo de mutação (código a nascer): o texto que pontua uma servida do canal novo sai de uma única expressão `partesTexto.slice(indiceInjecao + 1)`, onde `indiceInjecao` é a posição do pedido/briefing que a disparou; nenhum caso de teste lê o texto do fonte.

### 7. Relatório por canal, buscas ativas e régua D7 [tipo: implementar]
atende: D7, D9, D10
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`, `scripts/testa-utilidade-canais.sh`
depende de: 6
paralela: nao
prova: `bash scripts/testa-utilidade-canais.sh`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const fica = fracaoUtil >= REGUA_D7.util && fracaoPerda <= REGUA_D7.perda;`
  para: `const fica = fracaoUtil >= REGUA_D7.util || fracaoPerda <= REGUA_D7.perda;`
  bateria: `bash scripts/testa-utilidade-canais.sh`
  fixture: `testa-utilidade-canais.sh, caso "regua D7 exige as duas condicoes"`
pronto quando: com um banco de caixa de teste, `node scripts/memoria.cjs utilidade --relatorio` imprime, além do que já imprime: uma linha por canal com `sessões com servida útil X de Y (Z%)`; a linha `buscas ativas: A sessão(ões) principal(is) de B, C subagente(s) de D` (contadas no `pontuarSessao` pelos `tool_use` com `memoria.cjs buscar` no transcrito principal e nos de `subagents/` da sessão, gravadas como inteiros em `uso_memoria_sessoes`); e a última linha `régua D7: FICA o canal do assunto (útil Z% ≥ 40%, perdas P ≤ 1/3)` ou `régua D7: SAI o canal do assunto (...)`, com `REGUA_D7 = { util: 0.40, perda: 1/3 }` e a base `27% / 171 de 255` impressa ao lado para comparação. O caso com 45% útil e perdas em 50% imprime `SAI`; 45% e 30% imprime `FICA`; 35% e 20% imprime `SAI` — provado por `bash scripts/testa-utilidade-canais.sh` imprimindo os três `ok` da régua e `0 falha(s)`. Quem lê o relatório vê, antes da linha da régua, os dois números que a decidiram e a base de 2026-10-08. Forma do alvo de mutação (código a nascer): a decisão da régua é uma única expressão booleana `fracaoUtil >= REGUA_D7.util && fracaoPerda <= REGUA_D7.perda` atribuída a `fica`; nenhum caso de teste lê o texto do fonte.

### 8. Ideia de colher a régua D7 em 14 dias [tipo: configurar]
atende: D7
arquivos: `~/.rainforest/ideias.jsonl` (só via `node scripts/ideias.cjs plantar`)
depende de: 9
paralela: nao
mutacao: n/a
  motivo: registro de dado pelo script com trava; nenhum código do repo muda.
pronto quando: com a versão do fluxo já descrita no CHANGELOG (tarefa 9), `node scripts/ideias.cjs listar` mostra a ideia `regua-d7-memoria-por-assunto` com `gancho` contendo a data do dia da execução + 15 dias (14 de medição + 1 para a versão chegar ao cache, que só carrega no próximo carregamento) e `ao_colher` contendo `node scripts/memoria.cjs utilidade --relatorio` e a régua D7 por extenso (40% e 1/3) — provado por `grep '"id":"regua-d7-memoria-por-assunto"' ~/.rainforest/ideias.jsonl` devolvendo uma linha com os três trechos; e a ideia `rodar-relatorio-de-utilidade-da-memoria` colhida pelo `ideias.cjs colher` com nota apontando para este fluxo.

### 9. Documentação, CHANGELOG e versão [tipo: docs]
atende: D1, D2, D3, D5, D7, D9
arquivos: `README.md`, `docs/runtime-e-orcamento.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`
depende de: 4, 5, 7
paralela: nao
mutacao: n/a
  motivo: documentação; a falsificação é a coerência dos números e dos canais com o design, não um comportamento.
pronto quando: com o design e o código entregues, o README e o `docs/runtime-e-orcamento.md` descrevem os três canais com o evento real de cada um (abertura = `SessionStart`/mod; pedido = `UserPromptSubmit`; subagente = o ramo que a tarefa 1 decidiu), o teto de 3 memórias e de 1.500 bytes, o limiar da tarefa 2 e a régua D7 com os mesmos números do design (27% → ≥ 40%, 171/255 → ≤ 1/3, 14 dias); o CHANGELOG ganha a seção `## 1.48.0 — <data>` com o que muda para quem usa e "vale a partir da sessão seguinte à atualização"; `plugin.json` vai a `1.48.0` em commit próprio — provado por `node -e "const t=require('fs').readFileSync('README.md','utf8')+require('fs').readFileSync('docs/runtime-e-orcamento.md','utf8');const d=require('fs').readFileSync('docs/rainforest/design/2026-10-08-memoria-por-assunto.md','utf8');for(const n of ['40%','1/3','27%','171'])console.log(n,t.includes(n)&&d.includes(n))"` imprimindo `true` nos quatro, conferido à mão que a frase de cada número no README diz o mesmo que a decisão do design (não só contém o número), e `node -p "require('./.claude-plugin/plugin.json').version"` imprimindo `1.48.0`.

### 10. Issue do nome duplicado de projeto no banco [tipo: configurar]
atende: D4
arquivos: nenhum arquivo do repo (Issue no GitHub)
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: abre Issue; nenhum código muda.
pronto quando: com o banco real, a Issue no `luisfmontes/rainforest-mind` mostra as contagens do par `rainforest-mind` (3.182) / `C--Projetos-rainforest-mind` (1.266), saídas de `SELECT projeto, count(*) FROM observacoes GROUP BY 1 ORDER BY 2 DESC` filtradas para esse par (o repo é público: nenhum outro nome de projeto entra no corpo), diz que o mesmo padrão aparece em outros projetos do banco, e explica que a D4 contorna mas não corrige — provado por `gh issue list --repo luisfmontes/rainforest-mind --search "nome duplicado de projeto" --json number,title,state` devolvendo uma Issue `OPEN`.
