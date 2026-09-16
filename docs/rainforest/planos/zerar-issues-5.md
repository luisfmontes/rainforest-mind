# Plano: Zerar as Issues abertas, rodada 5 — as 20 medidas no código

Design: docs/rainforest/design/zerar-issues-5.md

## O que não pode quebrar
- Toda bateria que hoje passa continua passando; nenhum caso existente é apagado para caber conserto, só ajustado quando a decisão muda o comportamento (casos m/n/o do `testa-fechar-issue.sh`, D1).
- Gates que bloqueiam hoje por motivo legítimo continuam bloqueando: `git add -A` no principal, credencial real sem aspas, merge que traz conteúdo sensível **novo**, `cd <principal> && git commit` de subagente.
- A frase `CONFIRMO` continua exigida para apagar branch e worktree sujo (`limpar-branches`, `limpar-worktrees`); só sai do fechamento de Issue.
- Nenhuma tarefa escreve em `~/.rainforest` real (FOCO.md, ideias, despachos, banco): teste usa `--raiz` ou env de diretório temporário; leitura do banco real só na tarefa 14, e só `SELECT`.
- Hook que falha continua calado (exit 0 sem stdout/stderr) onde o contrato do cabeçalho diz isso.

## Notas do planejamento
- Três planejadores escreveram os blocos em paralelo, lendo o código na base `af836435`; a janela principal juntou e ajustou dependências.
- Tarefa 6: a medição mostrou que só `hooks/testa-contexto-sessao.sh` imprime sabotagem com o rótulo `FALHA` (as outras 9 baterias com `checa()` não); por isso ela toca um arquivo só, e depende da 17, que altera a mesma bateria.
- Tarefa 11: o `--git-common-dir` resolve só a leitura do `.rainforest-gate-off`; conteúdo, visibilidade e `.gitignore` continuam lidos no toplevel do worktree, senão o gate varreria a árvore errada. Desvio deliberado do texto literal da D4, que não mudava a intenção.
- Tarefa 14: no banco real, a hipótese da D9 não se confirmou — o `/saude` já acerta a pendência mais antiga, mas pela ordem de varredura do SQLite, não por contrato. A tarefa endurece com ordem explícita; o fechamento do sub-pedido da #282 diz isso, não "bug consertado".
- Tarefa 15: `rotacionar` escolhe o que descartar pela posição, não pela data, e numa cópia do FOCO.md real descartaria as duas entradas mais recentes. Encadeado ao `avanco`, apagaria a entrada recém-escrita; a correção entra na mesma tarefa (regra 6: atrapalha a tarefa, conserta na hora) e tem Issue própria (#290).
- Tarefa 17: medido ao vivo em 2026-09-16, a injeção real tem 7544 B de cabeçalho+rodapé e o foco já não cabe; a D7 ("`ORCAMENTO_BYTES` só sobe se a medição pedir") está satisfeita pela própria medição.

## Tarefas

### 1. gate-verificador-staged ignora em merge o arquivo igual a HEAD ou MERGE_HEAD [tipo: implementar]
atende: D3
arquivos: `hooks/gate-verificador-staged.cjs`, `hooks/testa-gate-verificador-staged.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-verificador-staged.cjs`
  de: `if (jaPublicado) continue;`
  para: `if (false) continue;`
  bateria: `bash hooks/testa-gate-verificador-staged.sh`
  fixture: caso novo (h) — merge trazendo `segredo.txt` idêntico ao `MERGE_HEAD` da branch mesclada
pronto quando: (`de:`/`para:` acima são trecho NOVO — `jaPublicado` não existe em `af836435`, nasce com este conserto.) Em `materializaStaged(gitTop)`, para cada `nome` staged cujo `conteudo` (via `git show :${nome}`) for **idêntico** ao blob em `HEAD:${nome}` OU (quando `git rev-parse -q --verify MERGE_HEAD` resolver) ao blob em `MERGE_HEAD:${nome}`, o arquivo NÃO é materializado nem entra em `arquivos` (`jaPublicado` computado antes do `fs.writeFileSync`, com um único `if (jaPublicado) continue;`); fora de merge (`MERGE_HEAD` não resolve) nada muda, e arquivo cujo conteúdo staged DIFERE de ambas as pontas continua sendo verificado normalmente. Reproduzido nesta sessão, CONFIRMADO: repo com `master` (commit `meu.txt`) e branch `outra` (commit `segredo.txt` = `api_key = abc123def456`), `git merge --no-commit --no-ff outra`, verificador `.rainforest/config.json` com `"verificador-staged": "bash scripts/verifica.sh"` que reprova `api_key`/`SEGREDO` — payload PreToolUse `{"cwd":"<repo>","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}` por stdin em `node hooks/gate-verificador-staged.cjs` sai **HOJE exit 2** citando `encontrado: credencial em segredo.txt` (o arquivo é idêntico ao que já está em `outra`, achado de merge "auto-suspeito", mesmo mecanismo de #275/#278). Depois do conserto o MESMO payload sai **exit 0** enquanto `segredo.txt` for o único staged; acrescentando um segundo arquivo `novo-segredo.txt` (staged, conteúdo `api_key = zzz999yyy888`, sem correspondente em `HEAD` nem `MERGE_HEAD`) o mesmo payload continua saindo **exit 2**, citando agora `novo-segredo.txt` — provado por `bash hooks/testa-gate-verificador-staged.sh` exit 0 e `node scripts/conferir-mutacao.cjs --arquivo hooks/gate-verificador-staged.cjs --de "if (jaPublicado) continue;" --para "if (false) continue;" --bateria "bash hooks/testa-gate-verificador-staged.sh"` saindo 0 (`vermelho`).

### 2. gate-mensagem-commit desmonta flag curta agrupada e isenta corpo de heredoc; mascararCorposDeHeredoc sobe para hooks/lib/heredoc.cjs [tipo: implementar]
atende: D3
arquivos: `hooks/gate-mensagem-commit.cjs`, `hooks/lib/heredoc.cjs`, `hooks/gate-staging-total.cjs`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-mensagem-commit.cjs`
  de: `const { mParts, fFile, reusaMensagem } = leFlagsCommit(desmontarFlagsCurtas(achado.argsToks));`
  para: `const { mParts, fFile, reusaMensagem } = leFlagsCommit(achado.argsToks);`
  bateria: `bash hooks/testa-gate-mensagem-commit.sh`
  fixture: caso novo — `git commit -qm "teste"` (e `-am`, `-qam`) passam a resolver a mensagem em vez de barrar com "nenhuma mensagem resolvivel"
pronto quando: (`de:`/`para:` acima são trecho NOVO — `desmontarFlagsCurtas` não existe em `af836435`, nasce com este conserto.) (i) `desmontarFlagsCurtas(argsToks)` — nova função — desmonta, ANTES de `leFlagsCommit`, todo token não citado que casa `/^-([aq]*)([mF])(.*)$/` em tokens separados (uma letra `-a`/`-q` por grupo, depois `-m`/`-F`, depois o restante colado como token de valor quando não vazio); `-m`/`-F` isolados continuam produzindo exatamente os mesmos tokens de hoje (não regressão), e `-a` sozinho (sem `m`/`F`) não casa e continua barrando por falta de mensagem — CONFIRMADO ao vivo nesta sessão: payload `{"cwd":"<repo>","tool_name":"Bash","tool_input":{"command":"git commit -q -m base"}}` sai exit 0, e o MESMO commit escrito como `git commit -qm base` (uma sessão real bateu nisto reproduzindo a #263 durante a medição desta rodada) sai **HOJE exit 2** com `Motivo: nenhuma mensagem resolvivel (sem -m, sem -F, sem flag de reuso)`; depois do conserto `git commit -qm base`, `git commit -am "x"` e `git commit -qam "x"` saem exit 0 resolvendo a mensagem "x"/"base", e `git commit -a` (sem `m`) continua saindo exit 2; (ii) `hooks/lib/heredoc.cjs` passa a exportar `mascararCorposDeHeredoc`, movida de `hooks/gate-staging-total.cjs` junto com as duas funções de que depende (`posicoesDeOperadorHeredoc`, `alvoDoRedirecionamentoEhExecutadoDepois`) e o `EXECUTAM_ARQUIVO`, sem mudar assinatura (`mascararCorposDeHeredoc(cmd)`) nem as quatro condições documentadas no docblock de origem; `gate-staging-total.cjs` não define mais essas três funções e as importa de `./lib/heredoc.cjs`, e `bash hooks/testa-gate-staging-total.sh` sai 0 com o mesmo placar de hoje (número de casos citado no commit, sem regressão); `gate-mensagem-commit.cjs` chama `mascararCorposDeHeredoc(cmd)` e passa o resultado para `achaGitCommit` no lugar de `cmd` cru — CONFIRMADO ao vivo: payload com `command` = heredoc `cat > issue.md <<'MD'` cujo corpo tem a linha `git commit` (bare, sem `-m`) sai **HOJE exit 2** ("nenhuma mensagem resolvivel"), porque `achaGitCommit` segmenta o corpo não mascarado e acha o `git commit` da linha do meio; depois do conserto o mesmo payload sai exit 0 (corpo de heredoc não citado como comando, tratado como dado) — provado por `bash hooks/testa-gate-mensagem-commit.sh` exit 0, `bash hooks/testa-gate-staging-total.sh` exit 0, e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 3. gate-staging-total mantém o -C resolvido e nomeia o segmento que bloqueou [tipo: implementar]
atende: D3
arquivos: `hooks/gate-staging-total.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `dirC = ultimoDirC;`
  para: `dirC = null;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: caso novo — `git -C "<outro-repo>" add f2.txt; iex "$cmd"` (PowerShell) cita `<outro-repo>` em "Repo:", não o cwd do evento
pronto quando: (`de:` acima é trecho NOVO — `ultimoDirC` não existe em `af836435`; `para:` reproduz o `dirC = null;` que já está hoje no ramo `if (g.incerto)`, linha 507.) `main()` passa a rastrear `let ultimoDirC = null;`, atualizado a cada iteração do laço de segmentos sempre que `g.dirC` for truthy (mesmo quando `motivoDe(g)` for `null`, isto é, mesmo quando aquele segmento sozinho não bloqueia); no ramo `if (g.incerto)`, a linha `dirC = null;` vira `dirC = ultimoDirC;` (mantém o último `-C` explícito visto no comando, em vez de descartá-lo); `bloqueia()` ganha um `Segmento: ${texto do segmento que casou}` logo após a linha `Comando:`, para o segmento que efetivamente disparou o bloqueio — CONFIRMADO ao vivo nesta sessão, contra dois repositórios reais: `principal` (cwd do evento, sem stage) e `outro` (com `f2.txt` staged), payload PowerShell `{"cwd":"<principal>","tool_name":"PowerShell","tool_input":{"command":"git -C \"<outro>\" add f2.txt; iex \"$cmd\""}}` sai **HOJE exit 2** com `Repo: <principal>` (o `-C` para `<outro>` é descartado porque o segmento seguinte, `iex "$cmd"`, é `incerto`) — o resíduo do segundo sintoma da #258/#261 (`gate-staging-total.cjs:496-508`); depois do conserto o mesmo payload continua saindo exit 2 (conservador — ainda pode esconder `git add -A`), mas `Repo: <outro>` (o `-C` explícito sobrevive) e o stderr contém `Segmento: iex "$cmd"` (ou equivalente, o texto exato do segmento incerto), deixando claro que o bloqueio não é sobre o `git -C add` — provado por `bash hooks/testa-gate-staging-total.sh` exit 0 e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 4. conferir-fluxo mutacoes: exit != 0 do conferir-mutacao (1,3,4,5,outros) reprova; bateria: perde a crase residual [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`, `skills/plano/SKILL.md`
depende de: nenhuma
paralela: sim

Dois consertos no mesmo trecho de `cmdMutacoes()` (CONFIRMADO, `scripts/conferir-fluxo.cjs:698-840`):

(a) **#281** — hoje só `exit === 2` (mutante sobreviveu) marca a variável que decide
o exit final do subcomando (`scripts/conferir-fluxo.cjs:713,820,839`, CONFIRMADO por
leitura). Os exits 1, 3, 4, 5 e qualquer outro (inclusive o 6 de "bateria colapsou",
que a Issue não cita mas cai em "outros") viram `pulada (...)` e **não** afetam o exit
final — que sai 0 mesmo quando nenhuma mutação declarada foi de fato medida. Conserto:
`if (exit !== 0) algumSobreviveu = true;` logo após `const exit = resultado.status;`
(linha 813), cobrindo todos os exits não-zero num só lugar (a linha 820 dentro do ramo
`exit === 2` fica redundante e pode continuar ali sem efeito colateral). A linha final
(839) não muda de forma — muda de significado, porque `algumSobreviveu` passa a cobrir
"sobreviveu OU não foi medido".

(b) **#254(b)** — `bateria: `campos.bateria.replace(/^`|`$/g, '')`` (linha 748,
CONFIRMADO) só tira crase que esteja exatamente no início/fim da string inteira. Um
campo como o que a própria Issue #254 registrou —
`` bateria: `node hooks/testa-portaria-manifesto.cjs` (tarefa 6) `` — fica com a crase
de fechamento E o `(tarefa 6)` colados ao comando, que passa a ser o argumento
`--bateria` de verdade. Conserto: extrair só o PRIMEIRO trecho entre crases, com o
mesmo padrão que `extrairArquivos` já usa (`match(/`([^`]+)`/g)`, `scripts/conferir-fluxo.cjs:625`,
CONFIRMADO — reuso, não invenção), caindo para o valor bruto trimado se não houver
crase nenhuma.

(c) **#254(c)** — documentar em `skills/plano/SKILL.md`, na seção "Campo obrigatório:
`mutacao:`" (depois do bloco de exemplo, por volta da linha 101, CONFIRMADO): `de:` e
`para:` são texto **copiado** do fonte (nunca prosa, mesmo com um trecho entre crases
no meio de uma frase — é exatamente o formato que a Issue #281 mostra falhando), e
`bateria:` é só a linha de comando, sem anotação depois da crase de fechamento (Issue
#254). Nota para humano fica em outro lugar do plano, nunca dentro nem colada ao campo.

mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `process.exit((algumSobreviveu || algumaFalhaDeMedicao) ? 1 : 0);`
  para: `process.exit(algumSobreviveu ? 1 : 0);`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: nova asserção de exit code sobre o plano `t-de-nao-casa` já existente em `scripts/testa-conferir-fluxo.sh:821-836` — hoje esse bloco só tem `exige_msg` (checa texto, não exit code), que é exatamente o buraco que deixou a Issue #281 passar despercebida. O conserto acrescenta, logo após a linha 836: `exige 1 "de nao encontrado reprova (Issue #281)" env RFM_ESTADO_ROOT="$S" node "$CHECADOR" mutacoes --slug t-de-nao-casa`

NOTA sobre o campo `de:` acima: é trecho **NOVO** que o conserto (a) cria — não existe
hoje no fonte (hoje a linha 839 é literalmente o `para:` abaixo, CONFIRMADO por grep,
1 ocorrência). `para:` reverte para o texto de hoje.

pronto quando:
- com um plano cujo `mutacao.de:` de uma tarefa não bate no fonte declarado (entrada real: o fixture `t-de-nao-casa`, que já existe em `scripts/testa-conferir-fluxo.sh` com `de: \`linha que nao existe em lugar nenhum\``), rodar `env RFM_ESTADO_ROOT="$S" node scripts/conferir-fluxo.cjs mutacoes --slug t-de-nao-casa` devolve exit **!= 0** — provado por `bash scripts/testa-conferir-fluxo.sh` (hoje esse mesmo comando sai exit 0, CONFIRMADO pela leitura do código: só a mensagem é checada, não o exit code)
- com a entrada real registrada na Issue #254 — `` bateria: `node hooks/testa-portaria-manifesto.cjs` (tarefa 6) `` num bloco `mutacao:` de plano —, o comando extraído e efetivamente executado por `conferir-mutacao.cjs` é `node hooks/testa-portaria-manifesto.cjs`, sem o `` ` (tarefa 6)`` colado; provado por uma nova fixture `t-bateria-com-nota` em `scripts/testa-conferir-fluxo.sh` cuja bateria é um script trivial sempre-verde, e cujo `exige_msg` confirma que a saída não contém `RECUSADO` nem erro de comando não encontrado
- superfície humana: quem lê a saída de `mutacoes --slug <x>` para decidir se fecha o `verificar` (a mesma pessoa do incidente #254, que leu 9 linhas e viu "1 de 9 medida, e fechou") vê, para cada `pulada`, a MESMA palavra `pulada` de antes (não muda o texto) — mas agora o exit code, que é o único campo que `estado.cjs marcar --estagio verificar` lê, deixa de mentir sobre "medi e passou" quando na verdade "não medi nada"

---

### 5. conferir-fluxo creep: globs_isentos cobre reguas/ e skills/<s>/references/; extrairArquivos soma as ### N. repetidas [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-fluxo.cjs`, `skills/revisar/SKILL.md`, `scripts/testa-conferir-fluxo.sh`
depende de: 4
paralela: nao

Dois consertos, ambos em `scripts/conferir-fluxo.cjs` (CONFIRMADO por leitura):

(a) **`extrairArquivos` não soma emendas** (`scripts/conferir-fluxo.cjs:598-636`,
função usada só pelo `creep`, distinta de `extrairMutacao`). O loop testa primeiro se
a linha abre a tarefa N (`continue` se sim) e só DEPOIS testa se deve encerrar
(`break` ao achar QUALQUER outro `###`/`##`). Como o teste de abertura vem antes, uma
repetição EXATA de `### N.` logo em seguida não quebraria — mas assim que aparece
QUALQUER outra tarefa (`### 2.`, etc.) entre a primeira ocorrência de `### 1.` e uma
emenda posterior também chamada `### 1.`, o `break` da linha 614 **encerra o loop
inteiro**, e a emenda nunca é lida. É a forma real do bug: plano com

```
    ### 1. Tarefa original
arquivos: `a.js`

    ### 2. Outra tarefa
arquivos: `x.js`

    ### 1. Tarefa original (emenda)
arquivos: `b.js`
```

hoje devolve `['a.js']` para a tarefa 1, nunca `['a.js', 'b.js']`.

Conserto: ao chegar em outra seção, sair do modo "dentro da tarefa" **sem** encerrar a
varredura do documento inteiro — para que uma repetição posterior de `### N.` ainda
seja alcançada. Por causa da restrição de formato do bloco `mutacao:` (campo `de:`/`para:`
só aceita UMA linha física — `scripts/conferir-fluxo.cjs:414`, regex sem `s` que
resolveria isso, CONFIRMADO — o parser do próprio plano corta no fim da linha), o
if de saída de seção (hoje três linhas, 613-615) precisa ser reescrito **numa linha só**
de propósito, para caber inteiro no campo `de:` abaixo.

(b) **`globs_isentos` não cobre `reguas/` nem `skills/*/references/`**
(`scripts/conferir-fluxo.cjs:514-525`, CONFIRMADO). Acrescentar `'docs/rainforest/reguas/'`
(incondicional — a skill `regua` exige commitar esse arquivo antes da 1ª rodada) e,
depois do array, uma isenção condicional derivada de `globs` (já computado nas linhas
487-493): para cada glob que bater com `^skills/([^/]+)/SKILL\.md$`, empurrar
`skills/<nome>/references/` para `globs_isentos`. Trecho a acrescentar (grep-verificável
por contagem: 0 ocorrências de `references/` em `globs_isentos` hoje, 1 depois):

```javascript
  for (const g of globs) {
    const m = g.match(/^skills\/([^/]+)\/SKILL\.md$/);
    if (m) globs_isentos.push(`skills/${m[1]}/references/`);
  }
```

(c) **Documentar em `skills/revisar/SKILL.md`** (seção "Creep: medido contra o plano,
não contra o gosto", linhas 113-126, CONFIRMADO) os dois carve-outs acima, com a
pergunta-teste que resolve a divergência real da Issue #279 (dois revisores, mesmo
diff, veredito oposto sobre `docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md` e
`skills/executar/references/runtime-do-agente.md`): **o arquivo existe porque outra
regra documentada do repo obrigou a criá-lo?** Nomear as classes já existentes no
código (`docs/rainforest/{design,planos,estado,portoes}/`, `relatorios/`) mais as duas
novas (`docs/rainforest/reguas/`; `skills/<s>/references/` só quando `skills/<s>/SKILL.md`
está em `arquivos:` de alguma tarefa do plano).

mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (em_tarefa && (linha.startsWith('###') || linha.startsWith('##'))) { em_tarefa = false; continue; }`
  para: `if (em_tarefa && (linha.startsWith('###') || linha.startsWith('##'))) { break; }`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: nova seção em `scripts/testa-conferir-fluxo.sh` (sandbox git de verdade, mesmo molde da seção 10/11 do arquivo, linhas 534-614) com um plano de 3 tarefas (`### 1.`, `### 2.`, `### 1. (emenda)` — arquivos `a.js`, `x.js`, `b.js`) e um commit que só toca `b.js`; a asserção nova é `exige 0 "arquivo coberto so pela ### 1. repetida (emenda, #279)" ... creep --slug <t> --base <A> --head <B>`

NOTA sobre `de:`/`para:` acima: `de:` é o if grafado **numa linha só** — forma NOVA que
este conserto cria, diferente de como a função está formatada hoje (três linhas,
613-615, CONFIRMADO por grep — `if (em_tarefa && (linha.startsWith` ocorre 1 vez). É
uma concessão deliberada ao formato do campo do plano, não um objetivo de estilo.
`para:` também vai numa linha só, e reproduz o comportamento de hoje (`break`), só que
reformatado — o que importa para a mutação é o comportamento, não a grafia.

pronto quando:
- com um plano cuja tarefa 1 aparece duas vezes no documento, separadas por uma tarefa 2 (entrada real: a fixture da seção nova, acima), rodar `node scripts/conferir-fluxo.cjs creep --slug <t> --base <A> --head <B>` contra um commit que só toca o arquivo declarado na SEGUNDA ocorrência de `### 1.` sai `ok: sem creep` — hoje (CONFIRMADO pela leitura do código) esse mesmo commit seria recusado como creep, porque a segunda ocorrência nunca é lida
- com um diff que só toca `docs/rainforest/reguas/<nome>.md`, sem nenhuma tarefa do plano declarando esse caminho em `arquivos:`, `node scripts/conferir-fluxo.cjs creep` sai `ok: sem creep`
- com uma tarefa cujo `arquivos:` inclui `` `skills/exemplo/SKILL.md` `` e um diff que toca `skills/exemplo/references/algo.md` (não declarado em nenhuma tarefa), o mesmo comando sai `ok: sem creep`; e com um diff que toca `skills/outra/references/algo.md` cujo `skills/outra/SKILL.md` NÃO está em `arquivos:` de tarefa nenhuma, o comando continua reprovando (RECUSADO) — prova de que a isenção é condicional, não um glob largo escondendo creep de verdade (o mesmo defeito que a nota de 2026-08-13 já registrou para `design/**`, `scripts/conferir-fluxo.cjs:500-505`)
- superfície humana: um revisor lendo `skills/revisar/SKILL.md` decide, sem julgamento, sobre os dois arquivos nomeados na Issue #279 (`docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md` e `skills/executar/references/runtime-do-agente.md`) — falsificável conferindo que a pergunta-teste ("o arquivo existe porque outra regra documentada do repo obrigou a criá-lo?") aparece ANTES da lista de classes, e que a lista bate exatamente com o que este conserto implementou em código (nem mais nem menos classes do que `globs_isentos` reconhece — coerência, não presença de string solta)

---

### 6. baterias com checa(): a demonstração de sabotagem ganha rótulo distinto de "  FALHA " [tipo: teste]
atende: D4
arquivos: `hooks/testa-contexto-sessao.sh`
depende de: 17
paralela: nao

Levantamento CONFIRMADO por grep nos 10 arquivos que o design aponta como tendo
`checa()` (`hooks/testa-contexto-sessao.sh`, `hooks/testa-escada-subagente.sh`,
`hooks/testa-gate-agente-em-voo.sh`, `hooks/testa-memoria-session-start.sh`,
`scripts/testa-conferir-duplicacao.sh`, `scripts/testa-conferir-versao.sh`,
`scripts/testa-exporta-hooks-sessao-start.sh`, `scripts/testa-jornada.sh`,
`scripts/testa-memoria-somente-leitura.sh`, `scripts/testa-saude.sh`), mais os dois
citados na regra ("se também imprimirem, inclua e anote"):
`scripts/testa-limpar-branches.sh` e `scripts/testa-conferir-fluxo.sh`.

**Só `hooks/testa-contexto-sessao.sh` imprime o defeito.** Ele tem 5 chamadas da
forma `( checa "<nome>" tem "<esperado>" "$S_MUTx" )` (linhas 2077, 2094, 2112, 2199,
2216, CONFIRMADO por grep) — um subshell que roda `checa()` sabendo que ela vai
IMPRIMIR "FALHA" (porque a saída do mutante não bate com o padrão esperado), como
prova textual de que a asserção morde. Rodei a bateria real: `bash
hooks/testa-contexto-sessao.sh` sai exit 0, placar `ok: 284  falhou: 0`
(CONFIRMADO por execução — a Issue #270 registra 277, de um commit anterior; o
número mudou, o defeito não), e `grep -c '  FALHA '` na saída dá **5** — exatamente
essas 5 linhas de demonstração, indistinguíveis de falha real para quem faz
`grep FALHA` (foi o que aconteceu no PR #267 segundo a Issue).

Os outros 9 arquivos definem `checa()` mas **não têm nenhuma ocorrência de
`SABOTAGEM`** nem do padrão `( checa ...)` em subshell (CONFIRMADO por grep —
zero resultados nos 9). `scripts/testa-limpar-branches.sh` faz mutação embutida
(seções "MUTACAO", 6 ocorrências) mas usa o helper `tem()`, não `checa()`, e só
imprime "FALHA" quando a mutação **não** produz o efeito esperado — ou seja, só em
falha real; não precisa do conserto. `scripts/testa-conferir-fluxo.sh` também faz
sabotagem embutida (seção 7/8, linha 474) mas o helper ali já imprime "ok" no
caminho esperado e "FALHA" só quando a mutação NÃO teve efeito (falha real) — também
não precisa do conserto. Os dois foram checados e ficam de fora, por não
reproduzirem o defeito da Issue #270.

Conserto: um helper novo, `mostra_mutante()`, que faz a MESMA comparação de `checa()`
mas imprime um rótulo que não colide com "FALHA " em nenhum grep de triagem — a
Issue #270 sugere `ESPERADO-VERMELHO` como um dos dois formatos aceitáveis. As 5
chamadas `( checa ... )` viram chamadas diretas a `mostra_mutante` (sem subshell,
que deixa de ser necessário porque o novo helper não mexe em `ok`/`falhou`).

mutacao:
  arquivo: `hooks/testa-contexto-sessao.sh`
  de: `echo "  ESPERADO-VERMELHO $nome (modo=$modo, padrao='$pad')"`
  para: `echo "  FALHA $nome (modo=$modo, padrao='$pad')"`
  bateria: `bash -c "! bash hooks/testa-contexto-sessao.sh 2>&1 | grep -q '^  FALHA '"`
  fixture: SABOTAGEM 1 (hoje linha ~2068-2083, `dentroDoExpediente: sem expediente no config devolve null (nao false)`) — a primeira das 5 chamadas convertidas de `( checa ... )` para `mostra_mutante`

NOTA: `de:` é trecho NOVO que este conserto cria (a função `mostra_mutante` não existe
hoje). `para:` reproduz o texto que `checa()` já imprime hoje no ramo de falha
(`hooks/testa-contexto-sessao.sh:129`, CONFIRMADO) — a reversão faz a nova função
voltar a se comportar como a antiga, colidindo de novo com "FALHA ".

pronto quando:
- entrada real: a mesma saída que confundiu quem leu o PR #267 — `bash
  hooks/testa-contexto-sessao.sh 2>&1 | grep -c '  FALHA '` dá **0** num run limpo
  (placar `falhou: 0`), contra **5** hoje (medido acima); e `grep -c 'ESPERADO-VERMELHO'`
  na mesma saída dá **5** — as 5 demonstrações continuam presentes e legíveis, só que
  com rótulo que não casa `grep FALHA`
- superfície humana: quem faz a triagem de um CI vermelho de verdade (o cenário do
  #267 — 3 falhas reais misturadas com as 5 demonstrações) roda `grep -E "FALHA|VERMELHA"
  no log e vê SÓ as falhas reais na contagem de "FALHA", sem precisar ler as 3 linhas
  de contexto acima de cada demonstração para descartá-la manualmente (que é como a
  sessão do #270 foi enganada)

---

### 7. conferir-mutacao roda numa cópia temporária da árvore; testa-limpar-branches.sh para de fazer cp sobre o fonte do repo [tipo: implementar]
atende: D5
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`, `scripts/testa-limpar-branches.sh`
depende de: nenhuma
paralela: sim

Dois mecanismos, mesma causa raiz (Issue #266): mutar o fonte compartilhado da
árvore de trabalho, mesmo que por um intervalo curto, expõe o mutante a quem mais
lê aquele caminho — outra bateria, outra janela, `varrer-baterias.sh`. CONFIRMADO
por leitura de código nos dois arquivos.

**(a) `scripts/conferir-mutacao.cjs`.** Hoje `alvo = path.resolve(raiz, rel)`
(linha 374, CONFIRMADO — única ocorrência por grep) aponta para dentro da MESMA
`--raiz` que a bateria roda (`rodaBateria(bateria, raiz, ...)`, linhas 396 e 485).
A escrita da mutação (`fs.writeFileSync(alvo, ...)`, linha 473) e a restauração
(`armarRestauracao`/`restaurar`, linhas 133-159) só fecham a janela DEPOIS que a
bateria pós-mutação já rodou — durante a execução, o arquivo real está mutado no
disco, visível a qualquer leitor concorrente.

Conserto: antes de ler `original` (linha 380, hoje o primeiro acesso ao arquivo),
criar uma cópia descartável de toda a `raiz` num diretório temporário
(`fs.mkdtempSync(path.join(os.tmpdir(), 'conferir-mutacao-'))` +
`fs.cpSync(raiz, raizExecucao, { recursive: true, filter: p => path.relative(raiz, p) !== '.git' })`
— exclusão só do `.git` de TOPO da árvore, não de `.git` aninhado em fixture
nenhuma; `fs.cpSync` já é padrão usado no repo, `hooks/testa-portaria-nucleo.cjs:334`,
CONFIRMADO — reuso, não dependência nova). `alvo` passa a resolver contra
`raizExecucao`, e as DUAS chamadas de `rodaBateria` (baseline e pós-mutação) passam
a rodar com `cwd: raizExecucao`. A limpeza do diretório temporário entra no MESMO
mecanismo de `armarRestauracao`/sinal que já existe (linhas 141-150), trocando "reescrever
o byte original" por "apagar a cópia inteira" — e como o fonte real nunca é tocado,
deixa de existir a classe de defeito inteira, não só o sintoma (linha do próprio
Issue #266, "Direção sugerida").

**(b) `scripts/testa-limpar-branches.sh`.** `$SRC` é a raiz do checkout real
(`SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`, linha 27, CONFIRMADO), e
o literal `"$SRC/scripts/limpar-branches.cjs"` aparece **25 vezes** (CONFIRMADO por
`grep -c`) — como comando executado pelas 5 funções `roda*` (linhas 52, 221, 222,
228, 229) E como alvo mutado/restaurado em 6 seções de sabotagem (154-167, 312-324,
409-420, 485-496, 560-571, 621-633). O próprio comentário do arquivo já documenta o
risco (linhas 32-36): "se a bateria for interrompida no meio... o script fica MUTADO
no repositório" — hoje só um `trap cleanup EXIT` cobre a saída limpa; não cobre a
JANELA durante a execução, que é o que a Issue #266 mede.

Conserto: uma cópia de trabalho `LB="$SBP/limpar-branches.cjs"`, criada uma vez logo
depois de `SBP="$(novo_sandbox)"` (linha 43) a partir de `$SRC/scripts/limpar-branches.cjs`
(cópia — o único lugar em que `$SRC/scripts/limpar-branches.cjs` continua aparecendo
como ORIGEM de leitura, nunca como destino de escrita). Todas as 5 funções `roda*`
passam a invocar `node "$LB"`; as 6 seções de sabotagem passam a fazer `cp`/mutar/
restaurar `$LB` em vez do arquivo em `$SRC`. `cleanup()` (linha 38) restaura `$LB` a
partir de `$ORIGINAL_LIMPAR`, não mais o arquivo em `$SRC`. Como `$LB` já mora dentro
de `$SBP`, que já está em `SANDBOXES` e já é varrido pelo `trap cleanup EXIT`
existente, não é preciso nenhum mecanismo de limpeza novo.

mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `const alvo = path.resolve(raizExecucao, rel);`
  para: `const alvo = path.resolve(raiz, rel);`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: nova seção "== 22. mutacao roda em copia: o arquivo real fica intocado durante a bateria mutada (Issue #266) ==", acrescentada ao fim de `scripts/testa-conferir-mutacao.sh` (depois da seção 21, linha 876+)

NOTA: `de:` é o trecho que este conserto cria (`raizExecucao` não existe hoje como
variável). `para:` é exatamente a linha de hoje (`scripts/conferir-mutacao.cjs:374`,
CONFIRMADO, única ocorrência).

A nova seção 22 precisa provar exatamente o que a Issue mede — não "a bateria sai
0", mas o EFEITO COLATERAL durante a execução: um fonte fixture com um marcador
(`// Fixture: recusa`, o mesmo que a seção 5 já usa) e uma bateria que DORME por um
tempo mensurável (ex.: `bateria-lenta-2s.sh`, `sleep 2`), disparada em BACKGROUND
(`CHK ... --bateria 'bash bateria-lenta-2s.sh' & PID=$!`); enquanto ela roda, o
teste principal lê `$CAIXA/fonte.cjs` (o caminho real, o mesmo passado em `--raiz`)
e confere que o marcador `// Fixture: recusa` **ainda está lá, sem a marca mutada**;
depois, `wait "$PID"` recolhe o exit code normal do caso. Padrão de background já
usado em outras baterias do repo (`scripts/testa-saude.sh`, CONFIRMADO por grep),
não é mecanismo novo.

pronto quando:
- entrada real: uma bateria de `conferir-mutacao.cjs` que dorme 2s rodada em paralelo com uma leitura do MESMO caminho de `--arquivo` relativo à `--raiz` real (a fixture acima) — durante os 2s, o conteúdo lido é o ORIGINAL (sem a mutação), não o mutado; hoje (CONFIRMADO por leitura de código, `alvo` aponta pra dentro de `raiz`) essa mesma leitura veria o texto mutado
- entrada real: rodar `bash scripts/testa-limpar-branches.sh` e, em paralelo (processo separado iniciado antes das seções de MUTACAO, ou um `git status --porcelain -- scripts/limpar-branches.cjs` disparado por outra sessão durante a execução da bateria completa), confirmar que `scripts/limpar-branches.cjs` do checkout real nunca aparece como modificado — falsificável por grep estrutural: `grep -c '\$SRC/scripts/limpar-branches\.cjs' scripts/testa-limpar-branches.sh` cai de **25** (CONFIRMADO, contagem atual) para no máximo 2 (as duas cópias iniciais lendo de `$SRC`, nunca escrevendo nele), e nenhuma dessas ocorrências remanescentes é o primeiro argumento de um `cp` cujo SEGUNDO argumento seja `$SRC/...` nem o argumento de um `node`

---

### 8. limpar-branches: caminhoTemp de um nível só; varredura reconhece os dois formatos [tipo: implementar]
atende: D4
arquivos: `scripts/limpar-branches.cjs`, `scripts/testa-limpar-branches.sh`
depende de: 7
paralela: nao

CONFIRMADO por leitura: `caminhoTemp` (linhas 158-160) monta
`` `/tmp/worktree-${nomeBranch}-${Date.now()}` `` sem sanitizar `nomeBranch`. Uma
branch como `codex/fix-malformed-json` produz `/tmp/worktree-codex/fix-malformed-json-<13
dígitos>` — dois NÍVEIS de diretório, porque a barra da branch vira separador de
caminho. A varredura (`varrerTemporariosVazados`, linha 199) testa
`RE_TEMP_DESTE_SCRIPT.test(path.basename(caminho))`, e o `basename` desse caminho é
só `fix-malformed-json-<13 dígitos>` — nunca casa com `^worktree-.+-\d{13}$`, então o
temporário de branch com barra nunca é limpo.

Medição real, agora (CONFIRMADO por `git worktree list`, feita nesta sessão de
planejamento — só leitura, nada foi apagado): **250** worktrees registrados sob
`/tmp/worktree-codex/` neste clone, de um total de **274** worktrees listados — o
mesmo resíduo que a Issue #287 mediu em ~252.

Os dois consertos da D4 entram juntos (a Issue já pede os dois; a régua da tarefa
proíbe metade):

**1. `caminhoTemp` gera nome de um nível só** — substitui `/` por `-` no nome da
branch antes de montar o caminho, para que NENHUM temporário novo nasça de dois
níveis.

**2. A varredura reconhece os dois formatos** — para não deixar os já vazados
(as 250 medidas acima) presos para sempre, além de checar `path.basename(caminho)`
contra `RE_TEMP_DESTE_SCRIPT`, checa também a reconstrução "basename do pai + '/' +
basename", quando o pai começa com `worktree-`, contra um padrão que admite a barra
no meio.

mutacao:
  arquivo: `scripts/limpar-branches.cjs`
  de: `return \`/tmp/worktree-${nomeBranch.replace(/\//g, '-')}-${Date.now()}\`;`
  para: `return \`/tmp/worktree-${nomeBranch}-${Date.now()}\`;`
  bateria: `bash scripts/testa-limpar-branches.sh`
  fixture: seção "== varredura de worktree temporario vazado ==" (hoje linhas 638-691) ganha um QUARTO caso — um temporário de dois níveis (`$SBV/worktree-codex/fix-malformed-json-1788888888888`, mesmo molde do caso (1) da seção), com as contagens `antes`/`depois`/`removidos` ajustadas de 4/3/1 para 5/3/2 (os dois vazados — de um nível e de dois — removidos, o legítimo e o alheio preservados)

NOTA: `para:` é exatamente a linha de hoje (`scripts/limpar-branches.cjs:159`,
CONFIRMADO, única ocorrência por grep). `de:` é o texto que este conserto cria.

pronto quando:
- entrada real: uma branch chamada `codex/fix-malformed-json` (a mesma da Issue #287) gera, hoje, um caminho de temporário de DOIS níveis — depois do conserto, `node -e "console.log(require('./scripts/limpar-branches.cjs'))"` não exporta `caminhoTemp` hoje (não está em `module.exports`, linha 677, CONFIRMADO — não preciso exportar para provar isto: a fixture nova da seção acima já prova via `git worktree add` real, ponta a ponta) e o worktree resultante fica sob `/tmp/worktree-codex-fix-malformed-json-<13 dígitos>` (um nível), não mais `/tmp/worktree-codex/fix-malformed-json-<13 dígitos>`
- entrada real: os 250 worktrees `/tmp/worktree-codex/*` já vazados neste clone (medidos acima, CONFIRMADO) — depois de uma rodada de `node scripts/limpar-branches.cjs` no clone real, `git worktree list | grep -c "/tmp/worktree-codex/"` cai de 250 para 0 (ou para o número de worktrees desse padrão que estejam genuinamente em uso por outra sessão no momento da rodada, se houver — o piso esperado é 0 numa máquina sem trabalho em andamento nesse padrão)

---

### 9. fechar-issue.cjs sem --confirmo, --saida recusa caminho de arquivo, gate dita a forma certa, e skill fechar fecha cada Issue do plano com o portão do verificar como --saida-arquivo [tipo: implementar]
atende: D1, D2
arquivos: `scripts/fechar-issue.cjs`, `hooks/gate-fechar-issue.cjs`, `skills/fechar/SKILL.md`, `scripts/testa-fechar-issue.sh`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/fechar-issue.cjs`
  de: `if (fs.existsSync(valor) && fs.statSync(valor).isFile()) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-fechar-issue.sh`
  fixture: caso novo (p) — `--saida "<caminho de arquivo existente>"` recusa antes de chamar `gh`
pronto quando: (`de:`/`para:` acima são trecho NOVO — a checagem `fs.existsSync(valor) && fs.statSync(valor).isFile()` para `--saida` não existe em `af836435`, nasce com este conserto.) Quatro fatos, cada um falsificável:
  (1) D1 — `scripts/fechar-issue.cjs` não lê nem exige mais `--confirmo`: a checagem `const fraseEsperada = ...; if (confirmo !== fraseEsperada) { ...; process.exit(2); }` (linhas 130-139 de hoje) sai do arquivo, junto da variável `confirmo` e do branch `--confirmo` no parser de args; `node scripts/fechar-issue.cjs 12 --comando "x" --saida "y"` (SEM `--confirmo`, com o stub de `gh` de `scripts/testa-fechar-issue.sh` e `GH_CORPO_COM_CRITERIO=1`) sai **exit 0**, com `gh issue comment` chamado antes de `gh issue close 12` no log — hoje (CONFIRMADO na leitura do código e no caso (m) existente) esse mesmo comando sai exit 2 com "RECUSADO: --confirmo ausente...". `scripts/limpar-branches.cjs:614` e `scripts/limpar-worktrees.cjs:702` continuam exigindo a frase `CONFIRMO apagar branches ...`/`CONFIRMO apagar worktree sujo ...` — nem uma linha muda nos dois;
  (2) `--saida` recusa caminho de arquivo existente: `if (fs.existsSync(valor) && fs.statSync(valor).isFile())` logo após ler o valor de `--saida`, com mensagem citando `--saida-arquivo <mesmo caminho>` como a forma certa, e `process.exit(2)` ANTES de qualquer chamada a `gh` — hoje `--saida "<caminho-de-arquivo-real>"` cola o caminho verbatim no comentário (`scripts/fechar-issue.cjs:107-108`, sem checagem), reproduzindo o dano relatado na #269 (evidência falsa gravada na Issue);
  (3) `hooks/gate-fechar-issue.cjs:589,630` — hoje ambas as linhas ditam `--saida "<saída-ou-arquivo>"` (`grep -c '<saída-ou-arquivo>' hooks/gate-fechar-issue.cjs` = 2); depois do conserto essa string some (`grep -c` = 0) e as duas linhas passam a citar `--saida "<texto colado>"` e `--saida-arquivo <caminho dentro do repo>` como formas distintas;
  (4) D2/superfície humana — `skills/fechar/SKILL.md` ganha um passo, entre "1. Commitar o pendente" e "2. Limpar o repositório local" de hoje (que não fecha Issue nenhuma), fechando CADA Issue do plano por uma de duas formas, pinadas (nada de "ou" vago): **(a)** se `docs/rainforest/portoes/<slug>.md` existir para o fluxo, `node scripts/portoes.cjs rodar docs/rainforest/portoes/<slug>.md` seguido de `node scripts/fechar-issue.cjs <n> --comando "node scripts/portoes.cjs rodar docs/rainforest/portoes/<slug>.md" --saida-arquivo docs/rainforest/portoes/<slug>.md` — válido porque `rodar` GRAVA o campo `EVIDENCIA:` de volta no próprio arquivo (`scripts/portoes.cjs`, função `gravar`, escreve por `tmp`+`rename` no MESMO caminho recebido), então o arquivo depois de rodar já é command+output, não só a definição do portão (CONFIRMADO por leitura de `scripts/portoes.cjs`); **(b)** sem portões para o fluxo (caso de `zerar-issues-5`, que não tem `docs/rainforest/portoes/zerar-issues-5.md`), o comando do critério de pronto roda com saída redirecionada para um arquivo DENTRO do repo (ex. `docs/rainforest/estado/<slug>-fechar-<n>.txt`, apagado depois de usado — mesma disciplina de "limpar o repositório local" do passo seguinte do próprio SKILL.md) e esse arquivo vai em `--saida-arquivo`; nunca um caminho fora do repo (a recusa de `estaNoRepositorio` em `fechar-issue.cjs:112-115` continua valendo, e o texto do passo cita as DUAS formas para quem segue o passo não cair no mesmo "lugar natural é fora do repo" que a #269 registrou);
  provado por `bash scripts/testa-fechar-issue.sh` exit 0 — casos (m)/(n)/(o) de hoje (todos sobre `--confirmo`) viram: (m) fecha SEM `--confirmo` → exit 0, ordem comment-antes-de-close preservada; (n) e (o) somem (não há mais número certo/errado de confirmação a testar) — e o caso novo (p), do bloco `mutacao:` acima, cobre a recusa de `--saida` com caminho de arquivo — e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 10. conferir-publicacao vê credencial com chave JSON entre aspas [tipo: implementar]
atende: D3
arquivos: `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: `["']?\s*[:=]\s*["']?(\S+)/gi,`
  para: `\s*[:=]\s*["']?(\S+)/gi,`
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: seção nova "6f" — `"token": "..."`, `"password": "..."`, `"api_key": "..."` (chave entre aspas duplas) recusados com exit 2
pronto quando: (`de:` acima é o texto QUE O CONSERTO CRIA; `para:` é a regex de HOJE em `af836435` — `scripts/conferir-publicacao.cjs:239` — texto EXISTENTE, não novo.) A regex da régua `credencial` (`scripts/conferir-publicacao.cjs:239`) aceita aspa opcional entre a palavra-chave e o separador (`["']?\s*[:=]`, em vez de `\s*[:=]`); a extração de `chave` em `chaveComOp.match(/^(.*?)\s*[:=]/i)[1]` (linha ~275) passa por `.replace(/^["']+|["']+$/g, '')` antes do `.toLowerCase()`, para `ehTokenNu` continuar reconhecendo `"token"` (com aspas) como o mesmo caso que `token` (sem aspas) — sem isso a isenção estreita de identificador de código e a régua rigorosa para token nu duplicam critério para a forma citada e não citada. CONFIRMADO ao vivo nesta sessão, contra `HEAD`: `printf '%s' '"token": "8f3a9c2b1e7d4a6f0b5c8e2d9a4f7c1b",' | node scripts/conferir-publicacao.cjs - --json` sai **exit 0** hoje (deveria ser 2); a mesma chave sem aspas (`token = 8f3a9c2b1e7d4a6f0b5c8e2d9a4f7c1b`) já sai exit 2 hoje. Depois do conserto: as três formas JSON do corpo da Issue #262 (`"token": "...", `"password": "...", `"api_key": "..."`) saem exit 2 com achado `credencial`; e as duas isenções que já passam hoje continuam passando — CONFIRMADO ao vivo: `printf '%s' '"token": "${GITHUB_TOKEN}"' | node scripts/conferir-publicacao.cjs - --json` sai exit 0, e `printf '%s' 'const token = toks[i];' | node scripts/conferir-publicacao.cjs - --json` sai exit 0 — provado por `bash scripts/testa-conferir-publicacao.sh` exit 0 e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 11. gate-publicacao-destino: mensagem oferece setup.cjs --desligar, toggle lido pelo --git-common-dir, .rainforest-gate-off no .gitignore [tipo: implementar]
atende: D3, D4
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`, `.gitignore`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (raizPrincipal !== gitTop && fs.existsSync(path.join(raizPrincipal, ".rainforest-gate-off"))) return true;`
  para: `if (false) return true;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: caso novo — `.rainforest-gate-off` criado no checkout principal desliga o gate rodando a partir de um worktree linkado do mesmo repo
pronto quando: (`de:`/`para:` acima são trecho NOVO — `desligadoPorArquivo`/`raizPrincipal` não existem em `af836435`, nascem com este conserto.) Dois fatos.
  (1) `.rainforest-gate-off` herdado por worktree — nova função `desligadoPorArquivo(gitTop)`: `true` se o arquivo existe em `gitTop` (comportamento de hoje, preservado) OU se existe na raiz do checkout PRINCIPAL, deduzida de `git -C gitTop rev-parse --path-format=absolute --git-common-dir` + `path.dirname()` quando o resultado termina em `.git` (mesmo padrão já usado em `scripts/limpar-worktrees.cjs:363-374`); as três checagens hoje idênticas (`fs.existsSync(path.join(gitTop, ".rainforest-gate-off"))`, em `conferirCommit` e no caminho Write/Edit) e a que falta no caminho `MultiEdit` (que hoje não confere gate-off nenhum) passam a chamar esta função, sem trocar o `gitTop` usado para ler conteúdo/visibilidade/gitignore (isso continua sendo o toplevel de onde o comando roda, nunca o principal — trocar quebraria a leitura do conteúdo real do worktree). CONFIRMADO por leitura: hoje um `.rainforest-gate-off` criado na raiz do checkout principal NÃO desliga o gate quando o Write/Edit/Bash roda dentro de um worktree linkado do mesmo repo (`gitTop` ali é a raiz do worktree, arquivo diferente); depois do conserto, desliga;
  (2) mensagem oferece o toggle primeiro — `mensagemBloqueio` troca `"você tem duas saídas:\n  - RAINFOREST_GATE_OFF=1 ...\n  - arquivo .rainforest-gate-off ...\n"` por três linhas, na ordem preço-crescente, começando por `node scripts/setup.cjs --desligar gate-publicacao --escopo projeto (preferida...)`, mesmo padrão de texto já usado em `hooks/gate-staging-total.cjs:448-451`; CONFIRMADO por leitura: a mensagem de hoje (`hooks/gate-publicacao-destino.cjs:352-360`) não cita `setup.cjs` em lugar nenhum (`grep -c "setup.cjs" hooks/gate-publicacao-destino.cjs` = 0 hoje, passa a ≥1);
  e um terceiro fato sem bateria (estático): `.gitignore` ganha a linha `.rainforest-gate-off` (hoje ausente — `grep -c '.rainforest-gate-off' .gitignore` = 0) com comentário dizendo que é o toggle de emergência do gate de publicação, para não virar pegadinha de `git add -A` em quem copia o arquivo para um worktree;
  provado por `bash hooks/testa-gate-publicacao-destino.sh` exit 0 e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 12. titulo-sessao-end e heartbeat saem 0 calados com payload JSON null [tipo: implementar]
atende: D3
arquivos: `hooks/titulo-sessao-end.cjs`, `hooks/heartbeat.cjs`, `hooks/testa-titulo-sessao-end.sh`, `hooks/testa-heartbeat-poda.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/titulo-sessao-end.cjs`
  de: `if (!data || typeof data !== 'object') process.exit(0);`
  para: `if (false) process.exit(0);`
  bateria: `bash hooks/testa-titulo-sessao-end.sh`
  fixture: novo "TESTE 8" no arquivo, stdin literal `null` (não um objeto), afirmando exit 0 e stdout/stderr vazios — hoje a bateria só cobre `reason` inválido e ledger ausente, nunca payload não-objeto.
pronto quando: com o payload `null` (JSON literal válido — CONFIRMADO por reprodução: `printf 'null' | node hooks/titulo-sessao-end.cjs; echo $?` e `printf 'null' | node hooks/heartbeat.cjs end; echo $?` saem hoje `1` com stack trace, contrariando o próprio comentário de cabeçalho dos dois arquivos: "falha em qualquer ponto é silêncio: exit 0, sem stdout, sem stderr") no stdin — a forma que a Issue #272 mediu ser JSON válido que o `JSON.parse` aceita sem lançar, não uma forma observada em produção —, `hooks/titulo-sessao-end.cjs` e as três invocações de `hooks/heartbeat.cjs` (`prompt`, `stop`, `end`) saem `exit 0` com stdout e stderr vazios (stderr capturado em arquivo, nunca `2>/dev/null`, para a asserção de vazio ser real), e nenhum arquivo de estado muda: o `transcript_path` do título permanece byte-a-byte idêntico (mesmo teste `confirmarAppendUnico`/sha256 já usado nos outros 7 casos) e o `sessoes.json` do heartbeat permanece byte-a-byte idêntico — provado por `bash hooks/testa-titulo-sessao-end.sh` e `bash hooks/testa-heartbeat-poda.sh`, ambos saindo 0. Superfície humana: o efeito observável para a pessoa é o TÍTULO da sessão no Claude Code — o critério de "transcript intocado" é exatamente "o título não vira lixo nem crasheia a UI", não um detalhe interno.

### 13. /saude resume despachos.jsonl (contagem de despachos, deny, fora_de_fluxo, escreve_conferido:false) [tipo: implementar]
atende: D8
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `if (linha.decisao === 'deny') deny++;`
  para: `if (false) deny++;`
  bateria: `bash scripts/testa-saude.sh`
  fixture: nova seção do arquivo que grava um `despachos.jsonl` fixture com 1 linha `decisao: "deny"` e afirma que o achado `item: 'despachos'` cita `1 deny` — com a mutação, a contagem impressa vira `0 deny` e a asserção específica de deny falha (o total geral de linhas continua batendo, então só a asserção de deny discrimina).
pronto quando: com um `despachos.jsonl` no formato real que `hooks/portaria.cjs:538` (função `gravarDespacho`) grava — uma linha JSON por despacho com as chaves `ts, repo, agente, estagio, decisao, sessao`, mais `motivo` quando há deny, `escreve_conferido: false` só quando falso (nunca `true`, conforme o próprio comentário do arquivo), e `fora_de_fluxo: true` / `estagio_declarado`/`via`/`declarado: false` só quando presentes (extras da Issue #264) —, contendo por exemplo 5 linhas (2 `allow` limpos, 1 `deny`, 1 `allow` com `fora_de_fluxo: true`, 1 `allow` com `escreve_conferido: false`), rodar `node scripts/saude.cjs --json` (com `RFM_ROOT` apontado para a pasta de teste, isolando de `~/.rainforest` real) traz um achado `item: 'despachos'` cujo `detalhe` cita as 4 contagens corretas (5 despachos, 1 deny, 1 fora de fluxo, 1 escreve não conferido) — provado por `bash scripts/testa-saude.sh`. Superfície humana: a pergunta que a pessoa faz ao rodar `/saude` é "preciso abrir o despachos.jsonl agora, ou está tudo dentro do esperado?" — o `detalhe` responde com números concretos (não com "consulte o log"), e vira `aviso` (não `alerta`, não bloqueia) sempre que deny/fora_de_fluxo/escreve_conferido somarem mais que zero, mesmo que um só — mesmo padrão de sensibilidade que o achado `ideias` já usa para dívida herdada.
Confira antes de escrever: `hooks/portaria.cjs` resolve a raiz do log via `resolverRaiz({ cwd: raiz })`, onde `raiz` é o diretório do repositório que a portaria está protegendo — não necessariamente o `process.cwd()` de quem roda `/saude` depois. Os outros checadores de `scripts/saude.cjs` (`checarEsquema`, `checarMemoria`) resolvem via `resolverRaiz({ plugin: RAIZ_CODIGO })`, que **não** passa `cwd` (cai no default `CLAUDE_PROJECT_DIR || process.cwd()`) — hoje os dois caminhos convergem porque este ambiente só tem raiz GLOBAL (`~/.rainforest`, nível 3, indiferente a cwd), mas num repositório com `.rainforest` PRÓPRIO (nível 2, documentado no comentário de `raizDeDados` em `hooks/portaria.cjs`) os dois podem divergir — é exatamente o defeito que o cabeçalho de `hooks/heartbeat.cjs` (linhas 13-21) documenta já ter acontecido uma vez, em outro arquivo. `checarDespachos` deve resolver com `resolverRaiz({ cwd: process.cwd() })`, casando com a semântica de `raizDeDados` da portaria (raiz do projeto corrente), não copiar o padrão de `checarEsquema`/`checarMemoria` sem checar. Acrescente um caso ao `pronto quando`: rodando `node scripts/saude.cjs --json` de dentro de uma pasta de teste com `.rainforest/` PRÓPRIO (contendo `FOCO.md` e `portaria/despachos.jsonl` locais), o achado usa o `despachos.jsonl` LOCAL, não um global — provado por `bash scripts/testa-saude.sh`.

### 14. /saude acusa captura parada pela pendência mais ANTIGA; antes, confere a hipótese no banco real só lendo [tipo: implementar]
atende: D9
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: 13
paralela: nao
Achado (CONFIRMADO, leitura, nada gravado): a hipótese do design ("`/saude` acusa a pendência mais NOVA, não a mais antiga") **não se confirma** como está escrita. Consultei `C:\Users\Luis\.rainforest\rainforest.db` (real, produção, só leitura via `node:sqlite` `DatabaseSync({readOnly:true})`) com a query exata de `scripts/saude.cjs:1138-1142` (`SELECT processada_em, offset, offset_processado FROM marca_dagua WHERE offset > COALESCE(offset_processado, 0)`, sem `ORDER BY`). `EXPLAIN QUERY PLAN` devolve só `SCAN marca_dagua` (nenhum índice cobre o `WHERE`), e as 27 linhas pendentes voltaram em ordem de `rowid` ASCENDENTE (2052, 2170, 2361, ..., 3572). O `break` no primeiro item do laço (`saude.cjs:1144-1150`) reporta hoje a linha de MENOR `rowid`, que nesta base é `id=2052`, `processada_em=2026-09-03T17:34:40.173Z` — que também é a MENOR `processada_em` do conjunto: ou seja, o código de hoje já acerta por acidente, não erra para o lado da mais nova. A fragilidade é real mesmo assim: `rowid` e `processada_em` NÃO são a mesma coisa — as linhas `id=2515` (`processada_em` 2026-09-07T22:46:58) e `id=2516` (`processada_em` 2026-09-05T16:11:31, MAIS ANTIGA que a anterior apesar do rowid maior) provam que a ordem de `rowid`/scan diverge da ordem cronológica em pelo menos um ponto do dado real. Um `ORDER BY`/índice futuro, um `VACUUM`, ou uma versão diferente do SQLite podem mudar a ordem de scan sem aviso, e aí o `break`-no-primeiro deixa de coincidir com "a mais antiga". Conclusão: a premissa literal da D9 ("hoje acusa a mais nova") caiu; a tarefa não para porque o REMÉDIO que a D9 pede (tornar a seleção da mais antiga EXPLÍCITA, não uma coincidência de ordem de scan) continua correto e necessário — mas isso é decisão que cabe a quem despachou revisar (ver `## Falta decisão`).
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `ORDER BY processada_em ASC`
  para: `ORDER BY processada_em DESC`
  bateria: `bash scripts/testa-saude.sh`
  fixture: nova seção que monta um `rainforest.db` de teste (schema real via `scripts/memoria.cjs`, tabela `marca_dagua` com as colunas reais) com pelo menos 2 pendências cujo `rowid` e `processada_em` estão em ordens DIVERGENTES — reproduzindo o padrão medido (uma linha de `rowid` menor com `processada_em` mais NOVA, e uma de `rowid` maior com `processada_em` mais ANTIGA, tipo ids 2515/2516 acima) — e afirma que o achado cita a `processada_em` mais ANTIGA das duas, não a de menor `rowid` nem a mais nova.
pronto quando: com uma tabela `marca_dagua` no schema real (criada por `criarSchema`/`abrirBanco` de `scripts/memoria.cjs`, não um schema inventado) contendo duas ou mais pendências (`offset > offset_processado`) cujo `rowid` e `processada_em` divergem em ordem — o mesmo padrão medido no banco real do usuário em 2026-09-16 e colado acima —, `node scripts/saude.cjs --json` (com `RFM_ROOT` apontando para a pasta de teste, nunca `~/.rainforest` real) cita no achado `banco de memoria` a `processada_em` cronologicamente MAIS ANTIGA entre as pendências, não a de menor `rowid` — provado por `bash scripts/testa-saude.sh`. Superfície humana: a pergunta que a pessoa lê em `/saude` é "há quanto tempo a captura está realmente parada?" — citar a pendência errada (mais nova, ou uma aleatória por sorte de `rowid`) subestima o atraso real e adia a ação; o achado tem de nomear a data mais antiga porque é ela que decide se passou das 48h.

### 15. foco.cjs avanco "<texto>" [--contexto] [--aplicar]: insere parágrafo no topo de Avanços:, reparseia antes de gravar e roda rotacionar em seguida [tipo: implementar]
atende: D8
arquivos: `scripts/foco.cjs`, `scripts/testa-foco.sh`
depende de: nenhuma
paralela: sim
Achado (CONFIRMADO por reprodução, cópia isolada — nunca o arquivo real): `escolher()` (`scripts/foco.cjs:189-199`, usada por `rotacionar`) decide quem fica e quem sai por POSIÇÃO física no arquivo (`[...entradas].reverse()`, preserva o que está fisicamente no FIM do bloco, descarta o que está fisicamente no INÍCIO), não pela DATA de cada entrada. Isso é seguro só se o arquivo for sempre ascendente (mais antiga no topo, mais nova no fim) — a convenção da fixture de `scripts/testa-foco.sh`. O `FOCO.md` REAL do usuário (`C:\Users\Luis\.rainforest\FOCO.md`) não segue essa convenção: as entradas mais recentes (`2026-09-15`, duas vezes) estão logo abaixo do marcador `Avanços:` (linha 32), e um ponteiro de rotação anterior (linha 215: "histórico: 32 avanços de 2026-08-06 a 2026-08-23") mostra que alguém vem inserindo entradas NOVAS no TOPO desde a última rotação — exatamente o que a Issue #277 pede para o comando novo fazer. Reproduzi contra uma CÓPIA do arquivo real (nunca o original): `node scripts/foco.cjs rotacionar --raiz <cópia> --teto 3000` relata "sairiam 9 entrada(s) [...] ficariam 1", e a lista de movidas começa pelas DUAS entradas de `2026-09-15` (as mais recentes) — a única mantida é a de `2026-09-02` (mais antiga que todas as movidas, exceto uma de `2026-08-23` também descartada). Ou seja: `rotacionar`, hoje, decide pelo lado ERRADO quando o arquivo tem entradas novas no topo — e a Tarefa 15 pede exatamente para escrever novas entradas no topo e encadear `rotacionar` em seguida, o que tornaria esse defeito latente em ativo na primeira vez que o bloco passasse do teto padrão (5000 B) logo depois de um `avanco`. É causa raiz do mesmo arquivo que a tarefa já toca (ver `## Falta decisão` acima para o trade-off de escopo).
mutacao:
  arquivo: `scripts/foco.cjs`
  de: `const porData = [...indexado].sort((a, b) => (a.data < b.data ? 1 : a.data > b.data ? -1 : 0));`
  para: `const porData = [...indexado].reverse();`
  bateria: `bash scripts/testa-foco.sh`
  fixture: nova seção com um bloco `Avanços:` em ordem MISTA replicando o padrão real medido acima — ex.: `[2026-09-15: grande, 2026-09-14: média, 2026-08-23: grande]` nessa ordem física (mais nova no topo, mais antiga no fim) — teto que força uma remoção, e a asserção exige que `2026-08-23` (mais antiga por DATA, mas fisicamente no fim) vá para o histórico, e `2026-09-15` (mais nova por DATA, mas fisicamente no topo) permaneça — o INVERSO do que `escolher()` faz hoje.
pronto quando: (1) com um `FOCO.md` no formato real (bloco `Avanços:` com entradas `- AAAA-MM-DD[ (sessão do \`<slug>\`)]: texto`, o mesmo formato medido no arquivo do usuário) já com pelo menos uma entrada, `node scripts/foco.cjs avanco "<texto>" --contexto "<slug>" --aplicar --raiz <dir-de-teste>` grava uma entrada nova IMEDIATAMENTE APÓS o marcador `Avanços:` e ACIMA de qualquer ponteiro de histórico já existente (mesma posição das entradas novas no arquivo real, linhas 32-215) no formato `- <data de hoje> (sessão do \`<slug>\`): <texto>`, com `<data de hoje>` vindo de `Date.now()` — o comando NÃO aceita `--data` (decisão já fechada: "data vem do relógio, não do texto"); relendo o resultado com `recortarBloco`+`partirCorpo`, aparece exatamente uma entrada nova a mais, byte-a-byte igual ao texto pretendido — provado por `bash scripts/testa-foco.sh`; (2) sem `--aplicar`, o comando imprime DUAS coisas antes de sair 0 sem tocar o arquivo: a entrada que seria escrita, E o que o `rotacionar` encadeado moveria para `AVANCOS.md` se a escrita valesse — é o quadro completo que a pessoa precisa para decidir se aplica (superfície humana: sem o segundo dado, a pessoa aplicaria sem saber que o `avanco` que acabou de pedir seria imediatamente rotacionado para fora); (3) se a releitura pós-escrita não bater (conferência análoga à de `rotacionar`, linhas 256-262: reconstituição byte-a-byte antes de autorizar `gravar`), o comando aborta com exit != 0 e o arquivo fica byte-a-byte idêntico ao de antes (sha256 antes == depois) — provado por `bash scripts/testa-foco.sh`; (4) com o cenário do achado acima (bloco misto, teto abaixo do total), depois de `avanco --aplicar` (que encadeia `rotacionar`), a entrada QUE ACABOU DE SER ESCRITA sobrevive no `FOCO.md` — não é ela quem vai para `AVANCOS.md` — provado por `bash scripts/testa-foco.sh`.
Nota (INFERIDO, formato de `--contexto`): a Issue não define o formato exato de `--contexto "<slug>"`; adotei `(sessão do \`<slug>\`)` por casar com a convenção observada no `FOCO.md` real (`(sessão do \`inovacao\`, STEC-239 [...])`). Se o executor observar, na hora de implementar, um formato diferente no arquivo real corrente, siga o formato observado — é convenção documentada pelo próprio arquivo, não uma escolha estética a preservar por precedência deste plano.

### 16. testa-cli-externo Teste 3: teto sobe de 8000ms para 30000ms [tipo: teste]
atende: D6
arquivos: `scripts/testa-cli-externo.cjs`
depende de: nenhuma
paralela: sim

CONFIRMADO por leitura: `scripts/testa-cli-externo.cjs:123` compara
`duracao >= 8000` para decidir se o Teste 3 ("cli-que-trava-e-cortado") foi
efetivamente cortado por timeout (`timeoutMs: 1500`) contra uma fixture que dorme
60s. A CI de 15/09 (windows-latest, node 24, run 35021402066) mediu **8173ms** —
2% acima do teto — numa execução que FOI cortada corretamente (a fixture dorme 60s;
8,2s prova o corte, não o contrário). O comentário do próprio teste (linhas
118-122) já registra que o custo é o `matarDescendencia` chamando `powershell.exe`
1-2 vezes no Windows (~1-1,5s cada), não o comportamento sob teste. `node 22` do
mesmo commit, e `node 24` de outras branches, passaram — não é regressão de
código, é folga insuficiente do teto.

A fixture continua dormindo 60s (não muda): qualquer teto entre ~10s e ~50s
distingue "cortado" de "dormiu a fixture inteira" com folga de uma ordem de
grandeza. D6 escolhe subir para 30000ms — a correção barata da Issue #273 (a
correção de classe, medir por marcador em disco em vez de relógio, é proposta 2 da
Issue e fica fora de escopo desta rodada).

mutacao:
  arquivo: `scripts/testa-cli-externo.cjs`
  de: `if (duracao >= 30000) {`
  para: `if (duracao >= 1) {`
  bateria: `bash scripts/testa-cli-externo.sh`
  fixture: Teste 3 "cli-que-trava-e-cortado" (linhas 106-126)

NOTA sobre `para:`: não é o valor histórico (8000), de propósito. Reverter para
exatamente 8000 tornaria a prova por mutação ela própria dependente de relógio —
a Issue já registra duração local de ~6412ms, abaixo de 8000, então reverter para
8000 poderia deixar a bateria VERDE mesmo com o conserto desfeito, na máquina
errada, no dia errado (exatamente o defeito que a Issue relata). `para: 1` reprova
de forma determinística em qualquer máquina — a fixture dorme 60s e é sempre
cortada em `timeoutMs: 1500`, então `duracao` é sempre um número positivo bem
maior que 1ms, e o teste sempre acusaria falso corte com esse teto, provando que a
linha 123 é a que decide o veredito (e não outra).

pronto quando:
- entrada real: a duração já registrada em CI para este exato teste, 8173ms (run 35021402066, job 104557685392) — hoje classificada como "não foi cortado" (`8173 >= 8000` é verdadeiro), depois do conserto deixa de ser: `node -e "console.log(8173 >= 30000)"` devolve `false`, e a mesma duração reproduzida hoje (`node -e "console.log(8173 >= 8000)"`) devolve `true` — a inversão de classificação é o efeito
- superfície humana (mensagem de erro que aparece no log de CI, linha 124): o número citado na mensagem (`Não foi cortado: duração ${duracao}ms >= Xms`) precisa citar o MESMO teto reforçado (30000), não deixar um `8000` órfão na mensagem enquanto a comparação já usa 30000 — falsificável por `grep -n '8000' scripts/testa-cli-externo.cjs` devolvendo vazio depois do conserto (hoje devolve as linhas 123 e 124, CONFIRMADO por grep)

### 17. teto medido para cabeçalho+rodapé da injeção do SessionStart, asserido contra a saída real do hook; ORCAMENTO_BYTES só sobe se a medição pedir [tipo: implementar]
atende: D7
arquivos: `hooks/lib/contexto-sessao.cjs`, `hooks/testa-contexto-sessao.sh`, `scripts/testa-orcamento.sh`
depende de: nenhuma
paralela: sim
Achado (CONFIRMADO, ao vivo, hoje — não é só o histórico do design): rodei `node hooks/foco-session-start.cjs` sem payload no stdin (mesma forma de invocação do `SessionStart` real) contra o ambiente REAL do usuário, só leitura (o hook não grava nada — confirmado por grep, sem `writeFileSync`/`appendFileSync` no arquivo). Em 2026-09-16, agora, a injeção sai com **7810 B totais**, e o bloco `## Foco declarado` mostra `⚠️ O foco não coube nesta injeção (356 B livres, piso 700 B)`. Derivando pela fórmula do próprio hook (`sobra = ORCAMENTO_BYTES - fixo`, `tetoFoco = sobra - custoEstrategia`, com `custoEstrategia = 100 B` medido do ponteiro real do `ESTRATEGIA.md`): `fixo` (cabeçalho+rodapé) hoje é **7544 B**, deixando só 456 B de sobra — ABAIXO do piso de 700 B (`FOCO_MIN_BYTES`). Ou seja: o defeito que a Issue #250 descreve não é histórico, está ACONTECENDO nas sessões de hoje. Isso é maior que uma trava de teste: o conserto precisa ser um comportamento de RUNTIME (um teto aplicado e um corte, não só uma asserção de bateria), e `ORCAMENTO_BYTES` precisa subir — a condição "só sobe se a medição pedir" (D7) já foi satisfeita pela própria medição.
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: `if (fixo > TETOS.ORCAMENTO_BYTES - TETOS.FOCO_MIN_BYTES) {`
  para: `if (false) {`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: estender o `driver.cjs` (linha 61 do arquivo, já usado por outras seções desta bateria) com variáveis de ambiente para `veredito`/`sessoes`/`revisao`/`dependencias`/`principalAtrasado`, e uma nova seção que chama `montarContexto` com o SKILL.md real do repositório e um rodapé dimensionado para reproduzir a magnitude medida HOJE no ambiente real (veredito de foco parado, 3 sessões vivas em pastas distintas, revisão vencida, dependências declaradas, principal atrasado — a mesma combinação que o `foco-session-start.cjs` monta de verdade) — sem a mutação, o bloco de foco recebe pelo menos `FOCO_MIN_BYTES` e a mensagem "não coube" não aparece; com a mutação, ela reaparece (mutação de COMPORTAMENTO observável, não de comparação entre dois números).
pronto quando: com `hooks/lib/contexto-sessao.cjs`'s `montarContexto` chamado (via o `driver.cjs` estendido) com o SKILL.md real e um rodapé sintético calibrado para reproduzir a magnitude medida HOJE contra o ambiente real (CONFIRMADO acima: 7544 B de fixo, 456 B de sobra, abaixo do piso) — a injeção resultante NÃO mostra `⚠️ O foco não coube` nem `⚠️ INJEÇÃO ACIMA DO ORÇAMENTO`, e o bloco `## Foco declarado` recebe pelo menos `FOCO_MIN_BYTES` (700 B) — provado por `bash hooks/testa-contexto-sessao.sh`. `ORCAMENTO_BYTES` sobe para `fixo medido no pior caso realista (re-medido pelo executor no momento da execução, não copiado deste plano — o núcleo de regras muda) + FOCO_MIN_BYTES`, arredondado para cima; `scripts/testa-orcamento.sh`, seção "1c. valores congelados (D6)", ganha a checagem do novo literal (uma linha `congelado`, barata, mantendo o padrão já usado para `NUCLEOS_MAX_BYTES`/`ORCAMENTO_BYTES`/`FOCO_MAX_BYTES`/`FOCO_MIN_BYTES`) — provado por `bash scripts/testa-orcamento.sh`. Superfície humana: a pergunta que a sessão faz ao ler a injeção é "o foco declarado está aqui, ou preciso abrir o FOCO.md por fora?" — antes do conserto, a resposta de HOJE é não (medido ao vivo); depois, o corte por prioridade e o orçamento maior garantem a resposta sim POR CONSTRUÇÃO, não por a soma de blocos acontecer de caber num dia calmo.

### 18. gate-worktree resolve cd com caminho MSYS (/c/...) e não chama worktree linkado de principal [tipo: implementar]
atende: D3
arquivos: `hooks/gate-worktree.cjs`, `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `const alvo = path.resolve(estado.atual, normalizarMsys(destino));`
  para: `const alvo = path.resolve(estado.atual, destino);`
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: caso novo — `cd /c/.../scratchpad/<repo> && git commit --allow-empty -m y` (payload PreToolUse com `agent_id`, cwd = worktree linkado) sai 0
pronto quando: (`de:` acima é trecho NOVO — `normalizarMsys` não existe em `af836435`; `para:` reproduz o `path.resolve(estado.atual, destino);` que já está hoje na linha 353 do branch `cd`.) Dois fatos.
  (1) `hooks/lib/cwd-efetivo.cjs` ganha `normalizarMsys(caminho)` — `/^\/([A-Za-z])(\/.*|$)/` vira `<LETRA>:<resto ou "/">`, senão devolve o caminho como veio — chamada SÓ no branch `cd`/`Set-Location` de `resolverMovedor` (linha ~353 de hoje, `const alvo = path.resolve(estado.atual, destino);`), não em `pushd`/`env -C` (fora do escopo medido nesta Issue). CONFIRMADO ao vivo nesta sessão: `path.resolve("C:\\Projetos\\rainforest-mind\\.claude\\worktrees\\zerar-issues-5", "/c/Users/Luis/AppData/Local/Temp/.../scratchpad/gw18")` devolve `C:\c\Users\Luis\...\scratchpad\gw18` (caminho que NÃO existe), e por isso `estado.incerto` vira `true` (o `!fs.existsSync(alvo)` da linha seguinte). Payload real testado por stdin em `node hooks/gate-worktree.cjs`: `{"cwd":"<worktree-linkado>","tool_name":"Bash","tool_input":{"command":"cd /c/Users/Luis/AppData/Local/Temp/claude/.../scratchpad/gw18 && git commit --allow-empty -m y"},"agent_id":"a1","agent_type":"x"}` sai **HOJE exit 2**, "Repo: <worktree-linkado>", "Este e o diretorio de trabalho principal, nao um worktree isolado" — embora `<worktree-linkado>` seja de fato um worktree isolado E o alvo real (`.../scratchpad/gw18`) seja scratchpad isento; o mesmo comando com `git -C /c/.../scratchpad/gw18 commit ...` já sai exit 0 hoje (controle, CONFIRMADO), e a mesma forma com caminho Windows (`cd C:/Users/.../scratchpad/gw18 && git commit ...`) também já sai exit 0 hoje (controle, CONFIRMADO). Depois do conserto, o comando com `cd /c/...` sai exit 0 (a mesma normalização faz `estado.incerto` continuar `false`, `ehScratchpad` reconhece o destino e a linha de `alvos` extra em `cwdInicial` deixa de ser empilhada); `cd /c/<caminho-msys-de-um-repo-comum-nao-scratchpad-nem-worktree> && git commit ...` continua saindo exit 2 (não regressão — CONFIRMADO ao vivo com um segundo repo fora do scratchpad);
  (2) a mensagem de `bloqueia()` (`hooks/gate-worktree.cjs`) para de chamar de "diretorio de trabalho principal" um alvo que `estadoDoRepo` classificou como `ehWorktree: true` — `bloqueia(motivo, toplevel, agente, apenasRestauracao, ehWorktreeAlvo=false)` ganha o 5º parâmetro, passado como `estado.ehWorktree` na chamada do laço principal (`hooks/gate-worktree.cjs:858`, o único call site alcançado pelo ramo `incerto` desta Issue); quando `ehWorktreeAlvo` é `true` o texto passa a dizer que o alvo É um worktree isolado mas foi bloqueado por não dar para confirmar o cwd real (em vez do parágrafo de "regra 11" que descreve o caso oposto). Este fato usa um payload DIFERENTE do fato (1) — um em que `incerto` vem de `cd` com VARIÁVEL, não de caminho MSYS, para isolar a mensagem do mecanismo do fato (1) (que depois do conserto passa a sair exit 0, sem mensagem nenhuma para conferir): CONFIRMADO ao vivo nesta sessão, payload `{"cwd":"<worktree-linkado>","tool_name":"Bash","tool_input":{"command":"cd \"$D\" && git commit -m x"},"agent_id":"a1","agent_type":"x"}` sai **HOJE exit 2** com o texto "Este e o diretorio de trabalho principal, nao um worktree isolado" mesmo `<worktree-linkado>` sendo, de fato, um worktree isolado (`estadoDoRepo` classificaria `ehWorktree: true` se chegasse a ser consultado para a mensagem). Depois do conserto o MESMO payload continua saindo **exit 2** (não regressão — `cd` com variável continua incerto, continua bloqueando por precaução), mas o stderr NÃO contém mais a frase "Este e o diretorio de trabalho principal" — contém, em vez disso, o texto que reconhece `<worktree-linkado>` como worktree isolado bloqueado por incerteza de cwd;
  provado por `bash hooks/testa-gate-worktree.sh` exit 0 e `node scripts/conferir-mutacao.cjs --arquivo hooks/lib/cwd-efetivo.cjs --de "const alvo = path.resolve(estado.atual, normalizarMsys(destino));" --para "const alvo = path.resolve(estado.atual, destino);" --bateria "bash hooks/testa-gate-worktree.sh"` saindo 0 (`vermelho`).

### 19. principal-atrasado lista no máximo 2 worktrees já mesclados e resume o resto numa linha [tipo: implementar]
atende: D7
arquivos: `hooks/lib/principal-atrasado.cjs`, `hooks/testa-principal-atrasado.sh`
depende de: 17
paralela: nao
Achado da integração da tarefa 17 (2026-09-16): o corte por prioridade da 17 não alcança o aviso de worktrees `já em origin/main`, que cresce uma linha por worktree e, numa rodada com muitos agentes, sozinho empurrou o foco para baixo do piso na injeção real. O bloco não tem teto; o de sessões já tem (`(+N janela(s) ...)`). Esta tarefa dá ao aviso o mesmo formato, na origem.
mutacao:
  arquivo: `hooks/lib/principal-atrasado.cjs`
  de: `const MAX_WORKTREES_LISTADOS = 2;`
  para: `const MAX_WORKTREES_LISTADOS = 1000;`
  bateria: `bash hooks/testa-principal-atrasado.sh`
  fixture: caso novo "5 worktrees ja mesclados: 2 listados + 1 linha de resumo"
pronto quando: com um repo de caixa de areia no temp do sistema que tem `origin/main` e 5 worktrees linkados cujas branches já estão mescladas, `require('./hooks/lib/principal-atrasado.cjs').linhas({cwd: <repo>})` devolve exatamente 2 linhas terminando em `já em origin/main` e 1 linha de resumo `(+3 worktree(s) já em origin/main — rode o limpar)`; com 2 worktrees mesclados, devolve as 2 linhas e nenhuma de resumo; a linha do checkout principal atrasado (quando houver) continua vindo antes e não conta no limite — provado por `bash hooks/testa-principal-atrasado.sh` com os casos novos. Superfície humana: quem lê a injeção precisa saber **quantos** worktrees sobram e **o que fazer** — a linha de resumo tem o número e o comando, e o caso de teste falha se qualquer um dos dois sumir.

### 20. conferir-mutacao: a cópia da árvore continua sendo repositório git [tipo: implementar]
atende: D5
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: 7
paralela: nao
Achado da integração da tarefa 6 (2026-09-16): a cópia que a tarefa 7 criou exclui o `.git` de topo, e bateria que consulta git dentro da árvore deixa de ser verde no fonte íntegro. Medido: `bash hooks/testa-contexto-sessao.sh` sai `ok: 293 falhou: 0` na árvore real e `ok: 292 falhou: 1` dentro da cópia; a catraca nova recusa com exit 4 (`baseline NAO-VERDE`) o que a catraca anterior mede com exit 0. Falha segura (não dá falso verde), mas deixa sem medição toda bateria que depende de git — e o `verificar` deste fluxo roda justamente essa catraca.
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `materializarGit(raiz, raizExecucao);`
  para: `if (false) materializarGit(raiz, raizExecucao);`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: caso novo "bateria que exige git rev-parse dentro da arvore mede verde no baseline da copia"
pronto quando: com a árvore deste fluxo (`hooks/testa-contexto-sessao.sh`, bateria real que consulta git), `node scripts/conferir-mutacao.cjs --raiz <worktree> --arquivo hooks/testa-contexto-sessao.sh --de <trecho existente de uma linha> --para <neutro> --bateria "bash hooks/testa-contexto-sessao.sh"` passa do baseline (não sai 4 por `baseline NAO-VERDE`); a garantia da tarefa 7 continua de pé — durante a bateria mutada o arquivo alvo na árvore real mantém o conteúdo original (seção 22 de `scripts/testa-conferir-mutacao.sh` verde), e a cópia não compartilha índice nem HEAD com a árvore real (`git -C <arvore real> status --porcelain` igual antes e depois da catraca); a cópia temporária some ao fim, inclusive em erro — provado por `bash scripts/testa-conferir-mutacao.sh` com o caso novo. Superfície humana: se ainda assim o baseline da cópia falhar por ambiente, a mensagem diz que a falha foi **na cópia** e cita o diretório, para quem lê não confundir com bateria quebrada no fonte.
