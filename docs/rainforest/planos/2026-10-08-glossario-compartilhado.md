# Plano: Glossário de domínio compartilhado por repo (GLOSSARIO.md)

Design: docs/rainforest/design/2026-10-08-glossario-compartilhado.md

## O que não pode quebrar
- A abertura não muda: `git diff origin/main -- hooks/memoria-session-start.cjs hooks/lib/memoria-sessao.cjs hooks/abertura-mod-puro.mjs` vazio no fim do fluxo. D1 e D9 não tocam o SessionStart.
- Nenhum hook novo: `git diff origin/main -- hooks/hooks.json` vazio no fim do fluxo (D9). Por isso `hooks/testa-titulo-sessao-registro.sh` não muda; a contagem que muda é a de `scripts/testa-conferir-categoria.sh` (um `conferir-*.cjs` novo, sensor).
- Repositório sem `GLOSSARIO.md`: os dois hooks de memória por assunto produzem exatamente a saída de hoje, e `ponte.cjs` gera exatamente o bloco de hoje. As baterias existentes `hooks/testa-memoria-assunto.cjs`, `hooks/testa-memoria-assunto-prompt.cjs`, `hooks/testa-memoria-assunto-agente.cjs`, `scripts/testa-ponte.sh` e `scripts/testa-conferir-ponte.sh` seguem verdes **sem edição**.
- D6 do design de memória por assunto vale também para o glossário: qualquer falha nos hooks sai com exit 0 e stdout vazio; o pedido do usuário e o despacho do agente nunca esperam nem quebram por causa dele.
- O glossário nunca depende do banco: `GLOSSARIO.md` é arquivo do repo, e os hooks injetam o glossário mesmo com `rainforest.db` ausente, travado ou sem FTS.
- `hooks/lib/ponte-corpo.cjs` não ganha `require` de módulo novo: `scripts/testa-ponte.sh` e o cenário 6 de `scripts/testa-conferir-ponte.sh` copiam para a caixa só uma lista fixa de libs, e uma dependência nova quebraria os dois em silêncio.
- Nenhum texto de sessão vai para disco (mesma regra D10 da memória por assunto): o arquivo de deduplicação do glossário guarda só chaves de verbete, que vêm do `GLOSSARIO.md`, nunca do pedido.
- Nada grava `GLOSSARIO.md` sozinho (D8): só a tarefa 9 (a semente, por commit) e, depois dela, quem o Luís aprovar. Nenhum script e nenhum hook escreve nele.
- Orçamentos congelados (D6 de `scripts/testa-orcamento.sh`): agregado 15600 B, núcleos 6000 B, hook 8100 B. Nenhuma tarefa sobe teto; se não couber, vira a decisão do usuário abaixo.
- Escopo (D2, D5): nenhum arquivo de repositório de trabalho da squad é tocado e nenhum `/setup` do RatosOS entra.

## Fatos apurados antes de planejar
- CONFIRMADO: `GLOSSARIO.md` não existe no repo e nenhum código o cita (`grep -rn GLOSSAR` só acha o design e o estado do fluxo).
- CONFIRMADO: a branch do fluxo está 6 commits atrás de `origin/main` (`git rev-list --left-right --count origin/main...HEAD` devolve `6 2`). `origin/main` já está na 1.50.2; esta branch está na 1.50.0. Agente de `executar` nasce na ponta de `origin/main` (regra 11), então as tarefas veem a 1.50.2. Dos 12 arquivos que mudaram lá, só `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md` e `README.md` cruzam com este plano, e todos só na tarefa 13.
- CONFIRMADO: `corpo(agente, nucleo, dados, alvo = null)` em `hooks/lib/ponte-corpo.cjs` já recebe `alvo` e não o usa no corpo da função; `scripts/ponte.cjs:531` já o passa; `scripts/conferir-ponte.cjs:391` chama `corpo(agente, nucleoEsperado, dados)` sem ele. Sem tratar isso, uma ponte gerada com glossário seria acusada de "editada à mão" pelo conferidor.
- CONFIRMADO: `hooks/memoria-assunto-prompt.cjs` sai cedo quando o pedido começa por `/` ou tem menos de 3 termos úteis e lança quando o banco falta; `hooks/memoria-assunto-agente.cjs` lança quando o banco falta. As duas coisas derrubariam o glossário junto, então as tarefas 4 e 5 reordenam: o glossário é calculado antes e isolado.
- CONFIRMADO: `node scripts/orcamento.cjs` devolve Total 15416 B contra o teto de 15600 B (folga de 184 B); o núcleo mede 5922 B contra `NUCLEOS_MAX_BYTES: 6000` (folga de 78 B); o hook mede 8018 B contra 8100 B. A descrição da skill nova e o acréscimo no núcleo da regra 13 saem os dois dessa folga de 184 B (o hook cresce junto com o núcleo, dentro dos 8100 B).
- CONFIRMADO: `scripts/conferir-categoria.cjs` conta `hooks/hooks.json` + `scripts/conferir-*.cjs` + `vigias/*.md`; hoje 55 peças, distribuição 23 guia / 29 sensor / 3 dado (`scripts/testa-conferir-categoria.sh:70-80`). Um `scripts/conferir-glossario.cjs` entra como sensor e leva a 56 peças, 23/30/3.
- CONFIRMADO: `scripts/testa-versao.sh` exige que o badge e todo semver do `README.md` sejam a versão corrente; a versão sobe junto com README, CHANGELOG e os dois `plugin.json`.
- CONFIRMADO: o repo é público e `scripts/conferir-publicacao.cjs` recusa caminho de home em texto versionado; skill, glossário e este plano não levam caminho absoluto de máquina.
- INFERIDO: a memória pessoal a migrar (D4, D12) são os dois arquivos `dizer-fluxo-nao-esteira.md` e `vocabulario-enxertar-nao-roubar.md` da pasta `memory/` do projeto, na conta pessoal; `vocabulario-do-luis.md` fica (pode aprovar = merge e atividade = PSA são vocabulário pessoal, D12).
- LACUNA: se a conta de trabalho tem cópia desses dois arquivos. O `ls` da pasta equivalente só achou `esteira-e-o-default-nao-a-excecao.md`, que é outro assunto. A tarefa 10 pergunta antes de tocar em qualquer coisa.

## Formato do verbete (D7) e regras do arquivo — fixados aqui para as tarefas 1, 3, 4, 5 e 9
```
## fluxo
Definição: uma a duas frases.
Onde mora: arquivo, rotina, tabela ou campo.
Cenário: um caso real, concreto.
Evite: esteira; pipeline
```
- Verbete = cabeçalho `## <termo>` (fora de cerca de código) + linhas de campo `Rótulo: texto` no começo da linha. Rótulos: `Definição`, `Onde mora`, `Cenário`, `Evite`, comparados sem acento e sem diferença de caixa. O texto de um campo continua nas linhas seguintes até o próximo rótulo ou cabeçalho. Obrigatórios: Definição, Onde mora, Cenário (D13). `Evite` é opcional; é lista separada por `;`.
- Casamento da injeção (D9): termo do cabeçalho e cada item do `Evite`, sem acento, sem diferença de caixa, com fronteira de palavra dos dois lados e tolerância de um `s` final. O `Evite` casa porque o pedido que diz "esteira" é exatamente o que precisa receber o verbete `fluxo`.
- Bloco injetado: cabeçalho `## Glossário do repo`, no máximo 3 verbetes, no máximo 1.800 B, um verbete por linha no formato `- **<termo>**: <Definição> | onde mora: <Onde mora> | cenário: <Cenário> | evite: <itens>` (o `evite` só quando houver). Verbete cuja linha passa de 900 B nunca é injetado e o `conferir-glossario` o recusa.
- Onde o hook procura o arquivo: sobe de `cwd` até o primeiro diretório com `.git` (arquivo ou pasta, para valer em worktree) e lê o `GLOSSARIO.md` dele. Sem `.git` até a raiz do disco, não há glossário (não pega arquivo solto de pasta pai).

## Decisões
- Técnicas, assumidas aqui (sem impacto de produto): o `Evite` também casa (acima); pedido que começa por `/` não recebe glossário, a mesma regra da memória por assunto, e a consequência é que `/brainstorm quero uma esteira...` não injeta (alternativa descartada: casar também slash; reabra se doer); plural só com `s`; subagente recebe o glossário sem deduplicação (contexto novo), o pedido do usuário deduplica por sessão em `<raiz de dados>/memoria-assunto/<sessão>.glossario.json`; `conferir-glossario.cjs --caminhos` confere se os caminhos em crase de "Onde mora" e "Cenário" existem no repo e roda na CI deste repo (nos repos de trabalho fica desligado por padrão, porque nome de tabela não é caminho); `/glossario` é skill, sem command, porque a folga de 184 B do orçamento não comporta uma segunda descrição.
- Decisão do usuário, só se o orçamento não couber: a tarefa 8 mede o núcleo e a tarefa 7 mede a descrição da skill; juntos precisam de no máximo 160 B de 184 B livres. Se a medição real estourar, o executor para e devolve, sem subir teto. Opções: (a) encurtar texto de outra skill ou regra, recomendada por ser a mesma regra de subtração que vale no resto do repo; (b) subir `NUCLEOS_MAX_BYTES` ou o teto agregado, com a conta escrita (cada byte a mais é um byte a menos de FOCO.md em toda sessão).
- Decisão do usuário, na tarefa 10: a migração da memória pessoal só roda com a palavra dele (D8), arquivo por arquivo.

## Tarefas

### 1. Biblioteca do glossário: ler verbetes, achar o arquivo, casar termos, montar o bloco [tipo: implementar]
atende: D3, D7, D9
arquivos: `hooks/lib/glossario.cjs`, `hooks/testa-glossario.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-glossario.cjs`
mutacao:
  arquivo: `hooks/lib/glossario.cjs`
  de: const ANTES = '(^|[^\\p{L}\\p{N}])';
  para: const ANTES = '';
  bateria: `node hooks/testa-glossario.cjs`
  fixture: `testa-glossario.cjs, caso "termo no fim de palavra maior nao casa (contrafluxo)"`
pronto quando: com o texto de um `GLOSSARIO.md` no formato D7 (o que o Luís commitaria: cabeçalho `# Glossário`, parágrafo de introdução, depois verbetes `## fluxo`, `## território`, `## worktree de agente` com os campos), `hooks/lib/glossario.cjs` exporta `lerVerbetes(texto)`, `verbeteValido(v)`, `acharGlossario(cwd)`, `casarVerbetes(verbetes, texto)`, `montarBlocoGlossario(verbetes)`, `chaveDe(termo)`, `CABECALHO` (`## Glossário do repo`), `VERBETES_MAX` (3), `TETO_BYTES_GLOSSARIO` (1800) e `BYTES_MAX_VERBETE` (900), e a bateria prova, com `ok` por caso e `0 falha(s)`: o texto acima devolve 3 verbetes com termo, campos e itens do `Evite`; o mesmo texto em CRLF devolve o mesmo; rótulo sem acento (`Definicao:`) e em outra caixa (`ONDE MORA:`) valem; `###` dentro de um verbete não abre outro; cabeçalho `## x` e rótulos dentro de cerca de código (três crases ou três tis) não contam; texto antes do primeiro `##` é ignorado; campo de várias linhas junta as linhas; `Evite:` vazio equivale a ausente; `verbeteValido` é falso para verbete sem Cenário, com Definição vazia e com valor-placeholder (`TBD`, `a definir`, `n/a`, `-`, `...`) e verdadeiro sem `Evite`; `chaveDe("Território")`, `chaveDe("territorio")` e `chaveDe("Territórios")` são iguais; `casarVerbetes` devolve, na ordem da primeira aparição no pedido, só verbetes válidos, e casa `fluxos`, `FLUXO`, `território` escrito `TERRITORIO`, `worktree   de\nagente` com espaços e quebra, e o `Evite` `esteira` devolvendo o verbete `fluxo`; NÃO casa `fluxograma`, `contrafluxo`, `superfluxos` nem termo só dentro de palavra maior; `acharGlossario` num diretório sem `.git` acima devolve `null` mesmo com `GLOSSARIO.md` na pasta, num subdiretório de repo com `.git` (pasta) e de worktree com `.git` (arquivo) devolve o caminho da raiz; `montarBlocoGlossario` começa por `## Glossário do repo`, tem no máximo 3 linhas `- **termo**: ...`, no máximo 1.800 B, devolve `''` para lista vazia e para verbete único acima de 900 B — provado por `node hooks/testa-glossario.cjs` imprimindo `0 falha(s)`. Parada declarada: o parser só entende cerca de código (três crases ou três tis na coluna 0), cabeçalho `## ` e linha `Rótulo:`; comentário HTML, tabela, cabeçalho sublinhado, código indentado e front matter ficam FORA, e um caso fora dessa lista que morda volta para o `brainstorm` em vez de somar gramática ao parser. Forma do alvo de mutação (código a nascer): a fronteira esquerda do casamento é uma constante de uma linha só, exatamente `const ANTES = '(^|[^\\p{L}\\p{N}])';`, usada para montar a expressão regular do termo; nenhum caso de teste lê o texto do fonte.

### 2. Ponte aponta para o GLOSSARIO.md quando o repo-alvo o tem [tipo: implementar]
atende: D9
arquivos: `hooks/lib/ponte-corpo.cjs`, `scripts/testa-ponte-glossario.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-ponte-glossario.sh`
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: const r = escrever(destino, corpo(agente, nucleo, dados, alvo), aplicar, hash, alvo);
  para: const r = escrever(destino, corpo(agente, nucleo, dados, null), aplicar, hash, alvo);
  bateria: `bash scripts/testa-ponte-glossario.sh`
  fixture: `testa-ponte-glossario.sh, caso "alvo com GLOSSARIO.md recebe a linha nos tres agentes"`
pronto quando: com um repositório-alvo de caixa de teste que tem `GLOSSARIO.md` na raiz, `node scripts/ponte.cjs --alvo <dir> --agente codex --aplicar` grava um `AGENTS.md` cujo bloco gerado contém, uma única vez e antes do cabeçalho `## As regras`, a linha que começa por `termos de domínio: leia \`GLOSSARIO.md\`` (a frase de D9), e o mesmo vale para `--agente claude` (`CLAUDE.md`) e `--agente gemini` (`GEMINI.md`); num alvo sem `GLOSSARIO.md` o arquivo gerado NÃO contém a palavra `GLOSSARIO`, e `corpo(agente, nucleo, dados, alvo)` devolve exatamente o mesmo texto que `corpo(agente, nucleo, dados)` (chamada em processo, comparando as duas strings); gerar duas vezes seguidas não duplica a linha; com `GLOSSARIO.md` sendo uma pasta, não conta como glossário; o ensaio (sem `--aplicar`) não grava nada e imprime o tamanho já com a linha — provado por `bash scripts/testa-ponte-glossario.sh` imprimindo `ok` por caso e `0 falha(s)`, e por `bash scripts/testa-ponte.sh` e `bash scripts/testa-conferir-ponte.sh` seguindo verdes sem edição. A linha mora em `hooks/lib/ponte-corpo.cjs` como constante exportada e é decidida por `fs.existsSync` + `statSync().isFile()` sobre `alvo`, sem `require` novo. O alvo de mutação é a chamada existente que passa `alvo` a `corpo`; nenhum caso de teste lê o texto do fonte.

### 3. conferir-glossario.cjs: recusa verbete fora do formato, termo duplicado e caminho que não existe [tipo: implementar]
atende: D7, D13
arquivos: `scripts/conferir-glossario.cjs`, `scripts/testa-conferir-glossario.sh`, `scripts/testa-conferir-categoria.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-conferir-glossario.sh`
mutacao:
  arquivo: `scripts/conferir-glossario.cjs`
  de: const duplicado = vistos.has(v.chave);
  para: const duplicado = false;
  bateria: `bash scripts/testa-conferir-glossario.sh`
  fixture: `testa-conferir-glossario.sh, caso "Territorio e territorio sao o mesmo termo (duplicado recusa)"`
pronto quando: com um `GLOSSARIO.md` real de caixa de teste (o formato D7, em LF e em CRLF), `node scripts/conferir-glossario.cjs --raiz <dir>` sai 0 e imprime `GLOSSARIO.md: N verbete(s) conforme(s)`; com cada defeito abaixo sai 1 e a mensagem diz `GLOSSARIO.md:<linha>`, o termo e o que falta, com o formato esperado em uma linha (a pessoa que vê a recusa precisa saber qual verbete, qual campo e como escrever) — verbete sem Definição, sem Onde mora, sem Cenário, campo com rótulo mas texto vazio, campo com placeholder (`TBD`, `a definir`, `n/a`, `...`), rótulo digitado errado (`Defininição:`), rótulo em negrito (`**Definição:**`, que o parser não lê e a mensagem explica), termo duplicado (`Território` e `territorio`, `worktree` e `Worktrees`), `Evite` igual ao termo do próprio verbete ou ao termo de OUTRO verbete, verbete cuja linha renderizada passa de 900 B, arquivo que existe sem nenhum verbete, e verbete só dentro de cerca de código; `--exigir` sai 1 quando o arquivo não existe e sem `--exigir` sai 0 dizendo `sem GLOSSARIO.md`; `--listar` imprime uma linha por verbete válido (`termo` e, se houver, `evite: a, b`) e sai 0 mesmo com verbete inválido, avisando em stderr quantos ignorou; `--caminhos` recusa caminho em crase de "Onde mora" ou "Cenário" que não existe sob a raiz e NÃO verifica placeholder com `<`, glob com `*`, caminho com `~`, URL, nem texto em crase sem extensão de arquivo (nome de tabela, campo, comando sem caminho). Casos legítimos vizinhos que NÃO podem ser recusados, cada um com caso próprio: verbete sem `Evite`; `Evite:` vazio; Cenário de várias linhas; campos em outra ordem; rótulo sem acento e em outra caixa; texto de introdução antes do primeiro `##`; a palavra `Definição:` no meio de uma frase; `###` dentro do verbete; dois termos parecidos que não são duplicata (`estágio` e `estágio zero`); `~/.rainforest/ideias.jsonl` em crase com `--caminhos`; arquivo ausente sem `--exigir`. Parada declarada: este conferidor usa o mesmo parser da tarefa 1 (um só parser, para a injeção e a CI nunca discordarem do que é verbete) e não ganha gramática própria; caso fora do que a tarefa 1 declara volta para o `brainstorm`. A peça nova leva `// @categoria: sensor` na linha 2, e `scripts/testa-conferir-categoria.sh` passa a esperar 56 peças e distribuição 23 guia / 30 sensor / 3 dado (os três números, o título da seção 1 e o comentário-histórico do cabeçalho) — provado por `bash scripts/testa-conferir-glossario.sh` imprimindo `ok` por caso e `0 falha(s)`, e `bash scripts/testa-conferir-categoria.sh` imprimindo `0 falha(s)`. Forma do alvo de mutação (código a nascer): a detecção de duplicata é uma única atribuição `const duplicado = vistos.has(v.chave);` onde `v.chave` vem de `chaveDe` da tarefa 1 e `vistos` é o conjunto das chaves já lidas; nenhum caso de teste lê o texto do fonte.

### 4. Hook do pedido: injeta os verbetes casados, com ou sem banco [tipo: implementar]
atende: D1, D9
arquivos: `hooks/memoria-assunto-prompt.cjs`, `hooks/testa-glossario-prompt.cjs`
depende de: 1
paralela: nao
prova: `node hooks/testa-glossario-prompt.cjs`
mutacao:
  arquivo: `hooks/memoria-assunto-prompt.cjs`
  de: const blocoGlossario = montarBlocoGlossario(casarVerbetes(verbetes, prompt).filter((v) => !jaGlossario.has(v.chave)));
  para: const blocoGlossario = '';
  bateria: `node hooks/testa-glossario-prompt.cjs`
  fixture: `testa-glossario-prompt.cjs, caso "prompt com termo do glossario injeta so o verbete casado"`
pronto quando: com o payload real de `UserPromptSubmit` no stdin (`{"session_id":"s1","transcript_path":"<arquivo>","cwd":"<subpasta de um repo de caixa de teste com .git e GLOSSARIO.md>","hook_event_name":"UserPromptSubmit","prompt":"o que significa esteira aqui?"}`, o mesmo formato que `hooks/testa-memoria-assunto-prompt.cjs` usa) e `RFM_ROOT` apontando para uma raiz **sem `rainforest.db`**, o hook sai 0 com `hookSpecificOutput.hookEventName` `UserPromptSubmit` e `additionalContext` começando por `## Glossário do repo` e contendo `**fluxo**` e nenhum outro verbete; a segunda chamada na mesma sessão com o mesmo pedido sai 0 com stdout vazio e uma sessão diferente recebe de novo; o arquivo `<raiz>/memoria-assunto/s1.glossario.json` existe e só contém chaves de verbete (nenhuma palavra do pedido); pedido com 4 verbetes casados injeta 3, ≤ 1.800 B, na ordem da aparição; pedido curto (`esteira?`, menos de 3 termos úteis) injeta o glossário e não a memória; `fluxograma` não injeta; `Esteiras` e `TERRITORIO` injetam; pedido que começa por `/` não injeta; repo sem `GLOSSARIO.md`, diretório sem `.git`, `GLOSSARIO.md` com um verbete inválido (os válidos injetam, o inválido é ignorado), stdin inválido e `session_id` inválido saem 0 com stdout vazio; com banco criado pelo `criarSchema` real e um pedido que casa verbete E memória, `additionalContext` traz o glossário primeiro, uma linha em branco e `## Memória do assunto` depois, e com o banco travado traz só o glossário; a mensagem do hook para quem lê o contexto é o próprio verbete (nome, definição, onde mora e cenário), que é o que o agente precisa para usar o termo certo — provado por `node hooks/testa-glossario-prompt.cjs` imprimindo `ok` por caso e `0 falha(s)`, e por `node hooks/testa-memoria-assunto-prompt.cjs` e `node hooks/testa-memoria-assunto.cjs` continuando com `0 falha(s)` sem edição. A abertura fica intacta (`git diff origin/main -- hooks/memoria-session-start.cjs hooks/lib/memoria-sessao.cjs` vazio) e `hooks/hooks.json` não muda. Forma do alvo de mutação (código a nascer): o bloco do glossário sai de uma única atribuição `const blocoGlossario = montarBlocoGlossario(casarVerbetes(verbetes, prompt).filter((v) => !jaGlossario.has(v.chave)));`, calculada antes de qualquer acesso ao banco e dentro de um `try` próprio, de modo que falha de glossário não derruba a memória e falha de banco não derruba o glossário; nenhum caso de teste lê o texto do fonte.

### 5. Hook do subagente: verbetes casados entram no briefing [tipo: implementar]
atende: D1, D9
arquivos: `hooks/memoria-assunto-agente.cjs`, `hooks/testa-glossario-agente.cjs`
depende de: 1
paralela: nao
prova: `node hooks/testa-glossario-agente.cjs`
mutacao:
  arquivo: `hooks/memoria-assunto-agente.cjs`
  de: const blocoGlossario = montarBlocoGlossario(casarVerbetes(verbetes, original.prompt));
  para: const blocoGlossario = '';
  bateria: `node hooks/testa-glossario-agente.cjs`
  fixture: `testa-glossario-agente.cjs, caso "briefing com termo do glossario ganha o verbete no fim do prompt"`
pronto quando: com o payload real de `PreToolUse` da ferramenta `Agent` no stdin (`tool_name` `Agent`, `tool_input` com `description`, `subagent_type`, `model`, `run_in_background` e `prompt` contendo `esteira`, `session_id`, `cwd` de um repo de caixa de teste com `.git` e `GLOSSARIO.md`, `hook_event_name` `PreToolUse`) e uma raiz sem banco, o hook sai 0 com `hookSpecificOutput.updatedInput` igual ao `tool_input` original em todo campo exceto `prompt`, e `prompt` = original + `\n\n` + bloco que começa por `## Glossário do repo` e contém `**fluxo**`; duas chamadas na mesma sessão recebem as duas o bloco (contexto novo, sem deduplicação) e o hook não cria nem lê `<raiz>/memoria-assunto/*.glossario.json`; com banco e briefing que casa memória também, o prompt termina com o glossário, linha em branco e `## Memória do assunto`; briefing sem termo, repo sem glossário, `tool_name` outro, stdin inválido e `session_id` inválido saem 0 com stdout vazio; a `portaria.cjs` alimentada com o `prompt` resultante decide igual à alimentada com o original (mesmo exit e mesmo stdout) — provado por `node hooks/testa-glossario-agente.cjs` imprimindo `ok` por caso e `0 falha(s)`, e por `node hooks/testa-memoria-assunto-agente.cjs` continuando com `0 falha(s)` sem edição. Forma do alvo de mutação (código a nascer): uma única atribuição `const blocoGlossario = montarBlocoGlossario(casarVerbetes(verbetes, original.prompt));`, antes de qualquer acesso ao banco, em `try` próprio; nenhum caso de teste lê o texto do fonte.

### 6. conferir-ponte conhece a linha do glossário e não acusa edição à mão [tipo: implementar]
atende: D9
arquivos: `scripts/conferir-ponte.cjs`, `scripts/testa-conferir-ponte-glossario.sh`
depende de: 2
paralela: nao
prova: `bash scripts/testa-conferir-ponte-glossario.sh`
mutacao:
  arquivo: `scripts/conferir-ponte.cjs`
  de: const dirDoAlvo = alvo === '-' ? null : path.dirname(path.resolve(alvo));
  para: const dirDoAlvo = null;
  bateria: `bash scripts/testa-conferir-ponte-glossario.sh`
  fixture: `testa-conferir-ponte-glossario.sh, caso "ponte gerada com GLOSSARIO.md confere verde"`
pronto quando: com um repo de caixa de teste que tem `GLOSSARIO.md`, depois de `node scripts/ponte.cjs --alvo <dir> --agente codex --aplicar`, `node scripts/conferir-ponte.cjs <dir>/AGENTS.md` sai 0 e imprime `CONFERIDO`; num repo sem `GLOSSARIO.md` também sai 0; se o `GLOSSARIO.md` surge DEPOIS da geração, o conferidor sai 2 e a mensagem diz que o `GLOSSARIO.md` existe e a ponte não aponta para ele, com o comando de regeração, e NÃO diz "editado à mão" (o hash do SKILL.md bate, e é exatamente aí que a acusação falsa nasceria); se o `GLOSSARIO.md` sai depois da geração, a mensagem diz o inverso (a ponte aponta para arquivo que não existe mais) e também sai 2; edição à mão de outra linha do bloco continua sendo `RECUSADO — bloco foi editado à mão` com exit 2, mesmo com glossário presente; leitura por `-` (stdin) segue sem glossário — provado por `bash scripts/testa-conferir-ponte-glossario.sh` imprimindo `ok` por caso e `0 falha(s)`, e por `bash scripts/testa-conferir-ponte.sh` e `bash scripts/testa-ponte.sh` seguindo verdes sem edição. Forma do alvo de mutação (código a nascer): o diretório do alvo sai de uma única atribuição `const dirDoAlvo = alvo === '-' ? null : path.dirname(path.resolve(alvo));`, passada como quarto argumento de `corpo`; nenhum caso de teste lê o texto do fonte.

### 7. Skill /glossario: propor, migrar, listar [tipo: docs]
atende: D4, D8, D10
arquivos: `skills/glossario/SKILL.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: documento de skill; não há comportamento a inverter, e a falsificação é o exemplo do próprio documento passar no conferidor real e o orçamento de bytes fechar.
pronto quando: a skill tem três seções, `## propor`, `## migrar` e `## listar`, e uma só linha `description:` sem aspas, sem `: ` dentro (YAML) e com no máximo 90 B; `propor` parte da conversa e escreve o rascunho do verbete no formato D7 com "onde mora" e cenário **conferidos no repo** (grep ou ls, nunca de memória), mostra a pessoa e PARA; só depois da aprovação do Luís edita o `GLOSSARIO.md` em worktree e roda `node <plugin>/scripts/conferir-glossario.cjs --caminhos`, sem commit próprio (o commit e o PR são do `fechar`, D8); `migrar` parte de uma memória pessoal de domínio, recusa a que é pegadinha de ferramenta ou vocabulário pessoal (D3, D12), propõe o verbete e, com aprovação, grava o verbete e troca o corpo da memória por um ponteiro de uma linha que cita o termo e o repo, sem cópia (D4); `listar` roda `node <plugin>/scripts/conferir-glossario.cjs --listar`; a skill contém um bloco de código com a marca `verbete-exemplo` com um verbete completo, e esse mesmo bloco, gravado como `GLOSSARIO.md` de uma caixa de teste, passa em `node scripts/conferir-glossario.cjs --raiz <caixa> --exigir` com exit 0 — provado por `node -e "const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process');const s=fs.readFileSync('skills/glossario/SKILL.md','utf8');const m=s.match(/verbete-exemplo\n([\s\S]*?)\n[\x60]{3}/);const d=fs.mkdtempSync(path.join(os.tmpdir(),'rfm-sk-'));fs.writeFileSync(path.join(d,'GLOSSARIO.md'),m[1]+'\n');const r=cp.spawnSync(process.execPath,['scripts/conferir-glossario.cjs','--raiz',d,'--exigir'],{encoding:'utf8'});const desc=(s.match(/^description:\s*(.*)$/m)||[])[1]||'';console.log(r.status,Buffer.byteLength(desc)<=90,['propor','migrar','listar'].every(x=>s.includes('## '+x)))"` imprimindo `0 true true`, e `node scripts/conferir-publicacao.cjs skills/glossario/SKILL.md` e `node scripts/conferir-encoding.cjs skills/glossario/SKILL.md` saindo 0; `bash scripts/testa-teto-skills.sh` sem falha; `node scripts/orcamento.cjs` com Total ≤ 15600 B e exit 0. A coerência com D4, D8 e D10 é lida pelo `revisar` contra o texto do design, uma decisão por vez.

### 8. Regra 13: correção de vocabulário de domínio propõe verbete [tipo: docs]
atende: D11
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-13.md`
depende de: 7
paralela: nao
mutacao: n/a
  motivo: texto de regra; não há comportamento a inverter, a falsificação são os tetos de bytes do núcleo e do orçamento, e a coerência com D11 lida contra o design.
pronto quando: o núcleo da regra 13 em `skills/rainforest-mind/SKILL.md` (antes de `<!-- detalhe -->`) ganha uma frase de no máximo 70 B que diz que a correção de **vocabulário de domínio** propõe verbete via `/glossario` em vez de gravar memória pessoal, sem perder a frase `pelo \`ideias.cjs plantar\``; `skills/rainforest-mind/references/regra-13.md` ganha um parágrafo que separa três destinos pelo teste de uma frase que a regra já usa (método vira observação; fato do ambiente vai para a memória ou o `CLAUDE.md`; **termo de domínio, com "o que é, onde mora, cenário", vira proposta de verbete em `/glossario propor`, que o Luís aprova e entra por commit/PR**) e deixa explícito que vocabulário pessoal dele (`pode aprovar = merge`, `atividade = PSA`) e pegadinha de ferramenta continuam na memória (D3, D12) — provado por `node -e "const l=require('./hooks/lib/contexto-sessao.cjs');const s=require('fs').readFileSync('skills/rainforest-mind/SKILL.md','utf8');const n=l.extrairNucleo(l.filtrarRegras(s));const i=n.indexOf('**13.');const r13=n.slice(i,n.indexOf('**14.'));console.log(Buffer.byteLength(n,'utf8')<=6000,r13.includes('/glossario'),r13.includes('ideias.cjs plantar'))"` imprimindo `true true true`; `node scripts/orcamento.cjs` com Total ≤ 15600 B e exit 0 (a soma dos acréscimos das tarefas 7 e 8 não passa de 160 B); `bash hooks/testa-contexto-sessao.sh`, `bash scripts/testa-conferir-invariantes.sh` e `bash scripts/testa-orcamento.sh` com `0 falha(s)`; `node scripts/conferir-encoding.cjs skills/rainforest-mind/SKILL.md skills/rainforest-mind/references/regra-13.md` saindo 0. Se qualquer teto estourar, o executor para e devolve (decisão do usuário acima), sem subir teto.

### 9. Semente do GLOSSARIO.md do rainforest-mind [tipo: docs]
atende: D2, D3, D5, D6, D7, D12
arquivos: `GLOSSARIO.md`
depende de: 3, 4, 5
paralela: nao
mutacao: n/a
  motivo: documento de domínio; a falsificação é o conferidor real e o hook real lerem o arquivo, não um comportamento a inverter.
pronto quando: `GLOSSARIO.md` na raiz do repo (D6) tem os verbetes `fluxo`, `estágio`, `plantar`, `colher`, `acervo`, `território`, `enxertar`, `worktree de agente` e `portaria` (D12), cada um no formato D7, sem pegadinha de ferramenta e sem vocabulário pessoal (D3), com o "onde mora" e o cenário verdadeiros apurados no repo assim: `fluxo` — mora em `scripts/estado.cjs` (tabela de pré-requisitos design → plano → executar → revisar → verificar → fechar) e em `docs/rainforest/estado/2026-10-08-glossario-compartilhado.json`, cenário o `plano` só abrir com o `design` aprovado (`estado.cjs exigir`, exit 2), `Evite: esteira`; `estágio` — um passo do fluxo, mora em `skills/plano/SKILL.md` e nas outras skills de estágio, cenário a `arqueologia` ser estágio zero que fecha `dispensada` e o `limpar` não ser estágio (nunca bloqueia), conforme a tabela de `scripts/estado.cjs`; `plantar` — `scripts/ideias.cjs plantar`, `ideias.jsonl` na pasta de dados, cenário a ideia `glossario-compartilhado-por-repo` (descrever só o estado que `node scripts/ideias.cjs listar` mostra no dia: aberta ou colhida); `colher` — `scripts/ideias.cjs colher`, mesmo cenário; `acervo` — o conjunto de registros reais já acumulados (`ideias.jsonl`, observações, `skills/rainforest-mind/references/regra-12-acervo.md`), mora também em `CONTRIBUTING.md` na seção "Campo obrigatório novo vem com o passado resolvido", cenário o `gancho` obrigatório de 2026-08-11 que deixou o `conferir` com 35 problemas em linhas que nenhuma sessão causou, e a definição delimita o uso (a skill `montar-corpus` usa a palavra para o markdown gerado de uma wiki, outro sentido, que o verbete não cobre); `território` — conjunto de ferramentas e agentes de uma linguagem ou domínio, em plugin próprio com `territorio.json`, mora em `scripts/territorio.cjs`, cenário o repositório sem território em que `node scripts/territorio.cjs estagio plano` imprime `sem territorio` e sai 0; `enxertar` — adotar o mecanismo de um repo de terceiro por compressão, sem instalar o repo, mora em `vigias/livro-de-repos.md` (trilha `instalar | enxertar | ler`) e `vigias/batedor-repos.md`, cenário o `trailhq/Graft` em 2026-09-01 (linha "Instalar → Enxertar: enxerta" do livro), `Evite: roubar`; `worktree de agente` — checkout isolado onde o subagente que escreve roda, mora em `.claude/worktrees/` e em `hooks/gate-worktree.cjs` (exit 2 para escrita fora de worktree), nasce na ponta de `origin/main` e não na branch de quem despachou (regra 11, `skills/rainforest-mind/references/regra-11.md`), cenário este próprio plano sendo executado por agentes; `portaria` — a decisão que admite ou barra o despacho de subagente pelo manifesto e pelo estágio ativo, mora em `hooks/portaria.cjs` e `.rainforest/agentes.padrao.json`, cenário despacho de agente fora do manifesto sair com exit 2 e motivo no stderr — e o que for dito de cada um confere com o arquivo citado lido na hora, não de memória. Provado por `node scripts/conferir-glossario.cjs --exigir --caminhos` saindo 0 e imprimindo `GLOSSARIO.md: 9 verbete(s) conforme(s)`; por `node scripts/conferir-glossario.cjs --listar` imprimindo as 9 linhas (a de `fluxo` com `evite: esteira` e a de `enxertar` com `evite: roubar`); por `node scripts/conferir-publicacao.cjs GLOSSARIO.md` e `node scripts/conferir-encoding.cjs GLOSSARIO.md` saindo 0; e pelo hook real com o payload de `UserPromptSubmit` desta sessão — `node -e "const {spawnSync}=require('child_process');const os=require('os'),fs=require('fs'),path=require('path');const raiz=fs.mkdtempSync(path.join(os.tmpdir(),'rfm-glos-'));const p=JSON.stringify({session_id:'s-glos',transcript_path:path.join(raiz,'t.jsonl'),cwd:process.cwd(),hook_event_name:'UserPromptSubmit',prompt:'o que significa a esteira de agentes e o acervo aqui?'});const r=spawnSync(process.execPath,['hooks/memoria-assunto-prompt.cjs'],{input:p,encoding:'utf8',env:{...process.env,RFM_ROOT:raiz}});const j=JSON.parse(r.stdout).hookSpecificOutput.additionalContext;console.log(r.status,j.startsWith('## Glossário do repo'),j.includes('**fluxo**'),j.includes('**acervo**'),j.includes('**plantar**'))"` imprimindo `0 true true true false` (o pedido diz `esteira` e `acervo`, e nenhum outro termo). O `revisar` relê cada "onde mora" e cada cenário contra o arquivo citado.

### 10. Memória pessoal vira ponteiro dos verbetes migrados [tipo: configurar]
atende: D4, D12
arquivos: nenhum arquivo do repo (a pasta `memory/` do projeto na conta pessoal)
depende de: 9
paralela: nao
mutacao: n/a
  motivo: edição de memória pessoal feita pela janela principal com a palavra do Luís; nenhum código do repo muda e a falsificação é a leitura dos arquivos depois.
pronto quando: com a palavra do Luís (D8: a skill propõe, ele aprova, arquivo por arquivo) e feita pela janela principal, nunca por subagente, `dizer-fluxo-nao-esteira.md` e `vocabulario-enxertar-nao-roubar.md` (pasta `memory/` do projeto, conta pessoal) têm o corpo trocado por um ponteiro de uma linha para o verbete `fluxo` e para o verbete `enxertar` do `GLOSSARIO.md` do rainforest-mind, mantendo o cabeçalho (`name`, `description`) e o índice `MEMORY.md` apontando para eles; `vocabulario-do-luis.md` fica intacto; nenhum texto do verbete é copiado para a memória (D4) — provado por `grep -c "GLOSSARIO.md" <os dois arquivos>` devolvendo `1` em cada um, `grep -c "esteira" dizer-fluxo-nao-esteira.md` não passando de 1 (só no nome e no ponteiro), e `git diff --stat` do repo vazio para esta tarefa. Se o Luís não aprovar, a tarefa fecha `pulada` com o motivo e as demais seguem; o glossário já vale sem ela.

### 11. Conferidor do glossário na CI [tipo: configurar]
atende: D13
arquivos: `.github/workflows/baterias.yml`
depende de: 9
paralela: nao
mutacao: n/a
  motivo: configuração de CI; não há comportamento do repo a inverter, e a falsificação é rodar o comando do passo contra o arquivo real e contra um arquivo quebrado.
pronto quando: o workflow ganha, logo depois do passo "Versao do manifesto sobe em relacao a origin/main", um passo só do shard 1 (`if: matrix.shard == 1`, como o do `conferir-versao`) com a linha `run: node scripts/conferir-glossario.cjs --exigir --caminhos` e um comentário curto dizendo por que a CI lê o arquivo (a injeção por máquina deixaria de casar verbete fora do formato em silêncio, D13) — provado por `node -e "const fs=require('fs'),os=require('os'),path=require('path'),cp=require('child_process');const y=fs.readFileSync('.github/workflows/baterias.yml','utf8');const m=y.match(/if: matrix\.shard == 1\n\s+run: (node scripts\/conferir-glossario\.cjs[^\n]*)/);const cmd=m[1].split(' ').slice(1);const bom=cp.spawnSync(process.execPath,cmd,{encoding:'utf8'});const d=fs.mkdtempSync(path.join(os.tmpdir(),'rfm-ci-'));cp.spawnSync('git',['init','-q',d]);fs.writeFileSync(path.join(d,'GLOSSARIO.md'),'## fluxo\nDefinição: x\n');const mau=cp.spawnSync(process.execPath,[path.resolve(cmd[0]),...cmd.slice(1)],{cwd:d,encoding:'utf8'});console.log(bom.status,mau.status)"` imprimindo `0 1` (o comando do passo, extraído do YAML, passa no repo real e reprova um glossário sem Onde mora e sem Cenário).

### 12. Documentação: README, pontes, orçamento e skill da ponte [tipo: docs]
atende: D1, D9, D10, D13
arquivos: `README.md`, `docs/pontes.md`, `docs/runtime-e-orcamento.md`, `skills/ponte/SKILL.md`, `commands/ponte.md`
depende de: 2, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: documentação; a falsificação é a coerência dos números e dos canais com o design e com o código entregue, não um comportamento a inverter.
pronto quando: `README.md` ganha a linha `glossario` na tabela "Do dia a dia" e a linha de `scripts/conferir-glossario.cjs` na tabela de scripts, sem numeral de versão novo (o badge e os semver do README seguem os da tarefa 13); `docs/runtime-e-orcamento.md` ganha, junto da seção da memória por assunto, a descrição do glossário com os mesmos números do código — 3 verbetes, 1.800 B, 900 B por verbete, o arquivo de deduplicação `<sessão>.glossario.json` só com chaves, e que o glossário vale sem banco, no pedido (`UserPromptSubmit`) e no briefing do subagente (`PreToolUse`, matcher `Agent`); `docs/pontes.md`, `skills/ponte/SKILL.md` e `commands/ponte.md` dizem que, quando o repo-alvo tem `GLOSSARIO.md`, a ponte acrescenta a linha `termos de domínio: leia \`GLOSSARIO.md\``, e que o `conferir-ponte` acusa o glossário que surgiu ou sumiu depois da geração — provado por `node -e "const fs=require('fs');const c=require('./hooks/lib/glossario.cjs');const t=fs.readFileSync('docs/runtime-e-orcamento.md','utf8');console.log(t.includes(String(c.VERBETES_MAX)),t.includes('1.800'),t.includes(String(c.BYTES_MAX_VERBETE)),t.includes('glossario.json'))"` imprimindo `true true true true`, conferido à mão que cada frase diz o mesmo que a decisão do design e não só contém o número; `bash scripts/testa-versao.sh`, `bash scripts/testa-pastas-docs.sh` e `node scripts/conferir-encoding.cjs README.md docs/pontes.md docs/runtime-e-orcamento.md skills/ponte/SKILL.md commands/ponte.md` sem falha.

### 13. Versão 1.51.0, CHANGELOG e README [tipo: docs]
atende: D1, D9, D10, D13
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 8, 11, 12
paralela: nao
mutacao: n/a
  motivo: bump de versão e nota de atualização; a falsificação é a versão superar a de `origin/main` e o badge e a nota concordarem com ela.
pronto quando: depois de `git fetch origin main` e de integrar `origin/main` na branch do fluxo por merge (a branch está 6 commits atrás e `origin/main` já tem a 1.50.2, com conflito certo em CHANGELOG, README e nos dois `plugin.json`), os dois `plugin.json` vão a `1.51.0` (ou à menor versão minor acima da que `origin/main` tiver na hora, se ela tiver andado) em commit próprio, o badge do `README.md` aponta para essa versão, e o `CHANGELOG.md` ganha a seção `## 1.51.0 — <data>` dizendo para quem usa: o `GLOSSARIO.md` por repo, a injeção pelo assunto no pedido e no briefing do subagente (vale a partir da sessão seguinte à atualização), a linha que a `ponte` acrescenta, a skill `/glossario` (propor, migrar, listar), o conferidor na CI e a regra 13 — e o que fica de fora: nenhum repo de trabalho da squad foi tocado — provado por `node -p "require('./.claude-plugin/plugin.json').version+' '+require('./.codex-plugin/plugin.json').version"` imprimindo `1.51.0 1.51.0`, `node scripts/conferir-versao.cjs` com exit 0 e `bash scripts/testa-versao.sh` com `0 falha(s)`.

### 14. Laço inteiro de baterias, como a CI [tipo: teste]
atende: D2, D5, D13
arquivos: nenhum arquivo novo (roda a suíte que já existe)
depende de: 13
paralela: nao
prova: `node scripts/conferir-glossario.cjs --exigir --caminhos`
mutacao: n/a
  motivo: tarefa de integração; roda a suíte inteira sobre a árvore pronta e não entrega comportamento próprio a inverter.
pronto quando: com a árvore das tarefas 1 a 13 integrada na branch do fluxo, rodado pela janela principal (o hook `gate-bateria-sem-timeout.cjs` nega varredura completa a subagente), na ordem e do jeito que a CI roda: `bash scripts/varrer-baterias.sh --shard 1/2` e `bash scripts/varrer-baterias.sh --shard 2/2`, cada um em segundo plano (cerca de 17 min cada, acima do teto de 10 min do Bash em primeiro plano) e cada um terminando com a linha `as N baterias passaram`, onde N é a contagem de `bash scripts/varrer-baterias.sh --listar` e inclui as seis baterias novas (`hooks/testa-glossario.cjs`, `hooks/testa-glossario-prompt.cjs`, `hooks/testa-glossario-agente.cjs`, `scripts/testa-conferir-glossario.sh`, `scripts/testa-ponte-glossario.sh`, `scripts/testa-conferir-ponte-glossario.sh`); `node scripts/conferir-versao.cjs` e `node scripts/conferir-glossario.cjs --exigir --caminhos` com exit 0 (os dois passos do shard 1); `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` com exit 0 (o passo do gêmeo em Python); e as verificações de não-regressão do topo do plano, coladas com comando e saída — `git diff origin/main -- hooks/memoria-session-start.cjs hooks/lib/memoria-sessao.cjs hooks/abertura-mod-puro.mjs hooks/hooks.json` vazio; `node scripts/conferir-categoria.cjs` com `Total de peças varridas: 56`; `bash hooks/testa-titulo-sessao-registro.sh` com `0 falha(s)` e a contagem de hooks inalterada (`{"SessionStart":7,"PreToolUse":16,"Stop":5,"UserPromptSubmit":2}`); e `git diff origin/main --stat` sem nenhum arquivo fora das listas de `arquivos:` deste plano (escopo D2/D5). Nenhuma bateria `skipped`: bateria que pula por infraestrutura ausente é vermelho.

## Premissas aceitas sem conferir
- O `origin/main` = 1.50.2 é o do ref local no momento desta apuração (não fiz `git fetch`, por ser somente leitura); outra sessão pode ter publicado versão acima antes da tarefa 13, e é por isso que ela relê `origin/main` na hora.
- O payload de `UserPromptSubmit` e o de `PreToolUse` do `Agent` têm `cwd` (o hook de memória por assunto já o lê e o documento `docs/rainforest/referencia/2026-10-08-harness-prompt-e-agent.md` registra o formato); o `cwd` do `Agent` é o da sessão pai, não o do worktree do filho.
- Que `/glossario` funciona como atalho da skill `rainforest-mind:glossario` sem command; skills do plugin sem command existem (`plano`, `executar`), mas nenhuma delas é chamada por barra neste repo. Se o harness exigir command, a tarefa 7 devolve e vira decisão de orçamento.
- Que o `varrer-baterias.sh` acha as baterias novas por nome (`hooks/testa-*.cjs`, `scripts/testa-*.sh`) sem lista manual; a leitura das linhas 75-90 do script indica que sim, mas não o rodei.
- A conta de trabalho (`~/.claude`) não tem cópia dos dois arquivos de memória a migrar (lacuna acima).
- O tempo de 5 s do hook comporta ler e analisar um `GLOSSARIO.md` de dezenas de verbetes; nenhuma medição de tamanho real foi feita, e arquivo de centenas de KB não é tratado.
- O diretório de dados por sessão `memoria-assunto/` não tem poda hoje (nenhum `poda` o cita) e os arquivos `.glossario.json` herdam essa lacuna; fica fora do escopo.
