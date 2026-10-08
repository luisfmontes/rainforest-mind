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
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`, `scripts/testa-utilidade-canais.sh`, `scripts/testa-utilidade.sh`
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
arquivos: `README.md`, `docs/runtime-e-orcamento.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
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

## Emendas

**Emenda 1 de 2026-10-08 — versão 1.49.0, não 1.48.0 (tarefa 9).** A `origin/main` publicou a 1.48.0 no mesmo dia (PR #432), depois da base deste fluxo; `node scripts/conferir-versao.cjs` recusa bump que não supera a `origin/main`. O critério da tarefa 9 passa a ler `1.49.0` onde diz `1.48.0`, nos dois `plugin.json` e no CHANGELOG. Nada mais muda.

**Emenda 2 de 2026-10-08 — dois arquivos que o revisar achou fora de `arquivos:`.** `scripts/testa-utilidade.sh` entra na tarefa 6: o caso D10 antigo compara a lista EXATA de colunas de `uso_memoria`, e a coluna `canal` exigiu acrescentar `"canal"` a ela (uma linha; a lista continua exata). `.codex-plugin/plugin.json` entra na tarefa 9: o `CONTRIBUTING.md`, seção Versão, manda subir os dois `plugin.json` juntos, e `conferir-versao.cjs` confere os dois.

**Emenda 3 de 2026-10-08 — revisar reprovou com 4 achados medidos.** As tarefas 11 a 13 abaixo consertam os achados; nenhuma decisão do design muda.

### 11. Hooks: transcrito não re-lido, 30 termos mais raros, subagente sem dedupe da sessão [tipo: implementar]
atende: D3, D5, D6
arquivos: `hooks/lib/memoria-assunto.cjs`, `hooks/memoria-assunto-prompt.cjs`, `hooks/memoria-assunto-agente.cjs`, `hooks/testa-memoria-assunto.cjs`, `hooks/testa-memoria-assunto-prompt.cjs`, `hooks/testa-memoria-assunto-agente.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-memoria-assunto-prompt.cjs`
mutacao:
  arquivo: `hooks/memoria-assunto-prompt.cjs`
  de: `persistirServidos(arquivo, servidos);`
  para: `void 0;`
  bateria: `node hooks/testa-memoria-assunto-prompt.cjs`
  fixture: `testa-memoria-assunto-prompt.cjs, caso "pedido sem acerto grava o arquivo da sessao e o segundo nao rele o transcrito"`
pronto quando: (achado 1) depois do primeiro pedido da sessão, com ou sem acerto, o arquivo `<raiz>/memoria-assunto/<sessao>.json` existe (a semeadura roda uma vez por sessão), gravado por uma única chamada `persistirServidos(arquivo, servidos);` ANTES do teste de bloco vazio, e a semeadura lê só os primeiros 2 MiB do transcrito (o attachment de SessionStart vem no começo) — provado por um caso com transcrito sintético de 40 MB (SessionStart no início + enchimento) em que o hook sai 0 em < 1,5 s nas duas primeiras chamadas; (achado 2) a consulta FTS usa os **30 termos mais raros** do texto (menor document frequency > 0 em `observacoes_fts`), montada por uma função exportada `construirQueryAssunto(conexao, texto)` que a calibração também usará, com `const LIMITE_TERMOS = 30;` — provado por um caso em que um briefing de ~150 termos comuns ao corpus e sem os termos raros de nenhum alvo devolve `[]`; (achado 4) o hook do `Agent` não lê nem grava o arquivo da sessão (cada subagente é contexto novo): na mesma sessão, pedido seguido de `Agent` do mesmo assunto entrega ao subagente as mesmas memórias que o pedido recebeu, e o pedido seguinte não perde nada por causa do subagente — provado por `node hooks/testa-memoria-assunto.cjs`, `node hooks/testa-memoria-assunto-prompt.cjs` e `node hooks/testa-memoria-assunto-agente.cjs` com `0 falha(s)` cada, os casos novos nomeados.

(A tarefa 12 original foi substituída pela da emenda 5, mais abaixo.)

### 13. Extrator reconhece a linha cortada em 300 caracteres [tipo: implementar]
atende: D7, D8
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade-canais.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-utilidade-canais.sh`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (formatarObservacao(row, apelidos, TETO_LINHA_ASSUNTO) === linhaServida) return { origem: 'observacao', id: row.id, conteudo: row.conteudo };`
  para: `if (false) return { origem: 'observacao', id: row.id, conteudo: row.conteudo };`
  bateria: `bash scripts/testa-utilidade-canais.sh`
  fixture: `testa-utilidade-canais.sh, caso "servida do canal assunto cortada em 300 caracteres casa com o id"`
pronto quando: com uma observação cujo texto passa de 300 caracteres servida pelo bloco `## Memória do assunto` (linha formatada com teto 300, terminando em `…`), `acharAlvo` devolve o id dela (comparando também com `formatarObservacao(row, apelidos, TETO_LINHA_ASSUNTO)`, `TETO_LINHA_ASSUNTO = 300` importado ou espelhado de `hooks/lib/memoria-assunto.cjs`), ela entra em `uso_memoria` com nota e `canal = 'pedido'`, e não reaparece como não-servida no contrafactual — provado por `bash scripts/testa-utilidade-canais.sh` com o caso novo `ok` e `0 falha(s)`, e `bash scripts/testa-utilidade.sh` com `19 ok, 0 falha(s)`.

**Emenda 4 de 2026-10-08 — alvo de mutação da tarefa 13 com o retorno real.** O plano escreveu o retorno de `acharAlvo` como `{ origem, refId }`; o real é `{ origem, id, conteudo }` (o chamador lê `alvo.id` e `alvo.conteudo`). O `de:`/`para:` da tarefa 13 passa a usar o retorno real.

**Emenda 5 de 2026-10-08 — a tarefa 12 passa a `implementar` e ganha o teto de frequência.** Medido na integração da tarefa 11, na cópia do banco real: um briefing de receita de bolo recebeu 2 memórias sem relação (bm25 -16,9 e -16,0). As palavras do assunto (`bolo`, `cenoura`, `chocolate`) têm df 0 e saem da consulta; sobram palavras comuns (`a`, `e`, `de`, `com`, `uma`), cuja soma encosta no limiar. A tarefa 12 abaixo substitui a anterior: além de recalibrar, a consulta descarta termo com df acima de um teto (fração do corpus), e a calibração escolhe teto e limiar juntos.

### 12. Recalibrar o limiar com teto de frequência na consulta [tipo: implementar]
atende: D3, D7
arquivos: `scripts/calibrar-limiar-assunto.cjs`, `docs/rainforest/referencia/2026-10-08-limiar-memoria-assunto.md`, `hooks/lib/memoria-assunto.cjs`, `hooks/testa-memoria-assunto.cjs`
depende de: 11
paralela: nao
prova: `node hooks/testa-memoria-assunto.cjs`
mutacao:
  arquivo: `hooks/lib/memoria-assunto.cjs`
  de: `const raros = comDf.filter((t) => t.df <= tetoDf);`
  para: `const raros = comDf.filter((t) => true);`
  bateria: `node hooks/testa-memoria-assunto.cjs`
  fixture: `testa-memoria-assunto.cjs, caso "texto so com palavras comuns do corpus nao injeta"`
pronto quando: `construirQueryAssunto` descarta termos com df > `TETO_DF_FRACAO` × total de observações vivas (uma expressão só, na forma do `de:` acima; nenhum caso lê o fonte), e a calibração (mesma cópia do banco e transcritos da tarefa 2, consulta montada pela função do hook) mede pelo menos 3 tetos (0,5%, 1%, 2%) × pelo menos 5 limiares, escolhe o par pelo critério da tarefa 2 (maior fração útil com ≥ 30% dos pedidos com alguma injeção) e grava no documento a seção "Recalibração (teto de frequência)" com a tabela e as linhas `LIMIAR_BM25 = <n>` e `TETO_DF_FRACAO = <f>`, iguais às constantes exportadas pelo hook; o briefing "Escreva uma receita de bolo de cenoura com cobertura de chocolate, farinha, ovos, açúcar, forno a 180 graus por quarenta minutos, e explique como untar a forma." contra a cópia do banco real devolve `[]` — provado por `node hooks/testa-memoria-assunto.cjs` com o caso novo `ok` e `0 falha(s)`, `node -p "const L=require('./hooks/lib/memoria-assunto.cjs');L.LIMIAR_BM25+' '+L.TETO_DF_FRACAO"` batendo com o documento, e a saída de `buscarPorAssunto` do briefing do bolo colada (`[]`).

**Emenda 6 de 2026-10-08 — revisar (rodada 2) reprovou com 5 achados.** A tarefa 14 os conserta; nenhuma decisão do design muda.

### 14. Medição do canal novo: apelido, contagem de buscas, corte por `mais:`, ordem do attachment e matcher [tipo: implementar]
atende: D5, D7, D8, D9
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade-canais.sh`, `hooks/hooks.json`, `hooks/testa-memoria-assunto-prompt.cjs`
depende de: nenhuma
paralela: nao
prova: `bash scripts/testa-utilidade-canais.sh`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (formatarObservacao(row, null, TETO_LINHA_ASSUNTO) === linhaServida) return { origem: 'observacao', id: row.id, conteudo: row.conteudo };`
  para: `if (false) return { origem: 'observacao', id: row.id, conteudo: row.conteudo };`
  bateria: `bash scripts/testa-utilidade-canais.sh`
  fixture: `testa-utilidade-canais.sh, caso "servida do assunto com projeto pelo nome do harness casa com o id mesmo com apelido"`
pronto quando: (1) `acharAlvo` casa a linha do canal do assunto montada com o projeto cru (`formatarObservacao(row, null, 300)`, como o hook monta) mesmo quando a sessão tem apelido de projeto — numa linha só, na forma do `de:` acima; caso com transcrito de `cwd` num repositório git cujo nome curto difere do projeto gravado na observação; (2) `contarBuscasArquivo` só conta `tool_use` de `Bash`/`PowerShell` cujo `input.command` executa `memoria.cjs buscar` — caso com `Agent`, `Write` e `Edit` que citam o comando contando 0; (3) o corte por `mais:` vale só para o bloco da abertura; o do assunto vai até o próximo `\n## ` ou o fim — caso com observação contendo `jamais:` no texto mantendo as duas linhas inteiras; (4) se o attachment `hook_additional_context` vier ANTES da linha `user` do pedido no transcrito, a injeção se ancora no pedido seguinte (nunca `indiceInjecao = -1` com o próprio pedido no texto posterior) — caso com as duas ordens dando a mesma nota; (5) `hooks/hooks.json` registra o hook do subagente com matcher `Task|Agent`; e o comentário de `hooks/testa-memoria-assunto-prompt.cjs` não cita mais -16 — provado por `bash scripts/testa-utilidade-canais.sh` com os casos novos `ok` e `0 falha(s)`, `bash scripts/testa-utilidade.sh` com `19 ok, 0 falha(s)`, e `node -e "const h=require('./hooks/hooks.json');const p=(h.hooks||h).PreToolUse;console.log(p.some(e=>e.matcher==='Task|Agent'&&JSON.stringify(e).includes('memoria-assunto-agente')))"` imprimindo `true`.
