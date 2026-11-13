# Plano: Reuso antes de criar

Design: docs/rainforest/design/2026-11-13-reuso-antes-de-criar.md

## O que não pode quebrar
- `aviso-duplicata` continua só com o conjunto `topo` e não passa a avisar `Method` de classes diferentes com o mesmo nome (D6).
- `listar`, `complexas` e `variacao` seguem com a saída de hoje para JS, Dart e Python. A única mudança é a entrada nova de método ADVPL.
- Plano antigo cuja tarefa cria arquivo novo continua recusado sem `repo`. O canal `catalogo` se soma ao `repo`, não o substitui.
- `skills/plano/SKILL.md` e `skills/revisar/SKILL.md` ficam abaixo de 16384 bytes (`scripts/testa-teto-skills.sh`). Hoje estão em 16008 e 16086. Detalhe novo vai para `references/`, e cada SKILL ganha só um ponteiro de uma linha.

## Tarefas

### 1. Catálogo lê `Method x() Class Y` de ADVPL/TLPP [tipo: implementar]
atende: D6
arquivos: `hooks/lib/definicoes.cjs`, `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`, `hooks/testa-aviso-duplicata.sh`
depende de: nenhuma
busca:
- repo | rg -n "metodo|advpl" hooks/lib/definicoes.cjs scripts/catalogo-funcoes.cjs | o mapa `metodo` já existe para js e dart, e `definicoesDoTexto` só o consulta para js e dart (linha 171)
- catalogo | listar --raiz hooks/lib | estendo `casar` de hooks/lib/definicoes.cjs:66, sem função nova
desfecho: estender
mutacao:
  arquivo: `scripts/catalogo-funcoes.cjs`
  de: `const conjuntos = linguagem === 'dart' || linguagem === 'js' ? ['topo', 'metodo'] : ['topo'];`
  para: `const conjuntos = linguagem === 'dart' || linguagem === 'js' ? ['topo', 'metodo'] : ['topo'];//`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso novo "advpl: Method ... Class entra como Classe:metodo"`
prova: `bash scripts/testa-catalogo-funcoes.sh`
pronto quando: com um fonte `.tlpp` de fixture que tem `Class SaldoProjeto`, a declaração `Method calcular()` dentro do corpo da classe e a implementação `Method calcular(cProj as character) as logical Class SaldoProjeto` mais abaixo, `node scripts/catalogo-funcoes.cjs listar --raiz <fixture>` devolve uma entrada `nome: "SaldoProjeto:calcular"` na linha da implementação e nenhuma na linha da declaração — provado por `bash scripts/testa-catalogo-funcoes.sh` com o caso novo; e o `aviso-duplicata`, dado um Edit que acrescenta `Method New() Class B` a um repo onde já existe `Method New() Class A`, não avisa — provado por `bash hooks/testa-aviso-duplicata.sh` com caso novo.

Forma: o padrão ADVPL entra em `REGRAS.metodo.advpl`. Ele casa a linha de implementação (`^\s*method\s+<nome>\s*\(...\)` seguido de tipo opcional `as <tipo>` e de `class\s+<Classe>`), sem diferenciar maiúscula de minúscula. `casar` passa a montar `<Classe>:<nome>` quando o regex captura dois grupos. A forma da regra é livre, mas a ordem dos grupos tem de ser clara. Nenhum caso de teste afirma sobre o texto do fonte: os casos rodam o `listar` e o hook.

### 2. Subcomando `novas`: funções que o diff cria [tipo: implementar]
atende: D5
arquivos: `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`
depende de: 1
busca:
- repo | rg -n "function arquivosDoDiff|function baseDoDiff|definicoesDoTexto" scripts/catalogo-funcoes.cjs | `arquivosDoDiff`, `baseDoDiff` e `definicoesDoTexto` já leem os dois lados do diff para o `variacao`
- catalogo | listar --raiz scripts | compor scripts/catalogo-funcoes.cjs:393 (variacao) não serve inteiro, porque mede só js e dart; reaproveito arquivosDoDiff e definicoesDoTexto
desfecho: compor
mutacao:
  arquivo: `scripts/catalogo-funcoes.cjs`
  de: `const subs = ['listar', 'maiores', 'complexas', 'variacao', 'separar', 'conferir'];`
  para: `const subs = ['listar', 'maiores', 'complexas', 'variacao', 'separar', 'conferir', 'novas_'];`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso novo "novas: lista só a definição criada pelo diff"`
prova: `bash scripts/testa-catalogo-funcoes.sh`
pronto quando: num repo git de fixture cuja base tem `a.js` com `function velha()` e cujo HEAD acrescenta `function nova()` em `a.js` e cria `b.tlpp` com `Static Function outra()`, `node scripts/catalogo-funcoes.cjs novas --raiz <fixture> --base <base>` devolve JSON com exatamente `nova` (a.js) e `outra` (b.tlpp), cada um com arquivo, linha, nome e assinatura, e sem `velha`. Com `--base` inexistente, sai 1 e uma mensagem de uso. Provado por `bash scripts/testa-catalogo-funcoes.sh`.

Forma: "nova" é a definição (arquivo, nome) presente no HEAD e ausente na base, em todas as linguagens do catálogo. A base padrão é a mesma do `variacao` (`baseDoDiff`).

### 3. Canal `catalogo` no `busca:`, obrigatório em tarefa de código, com `arquivo:linha` conferido [tipo: implementar]
atende: D2, D3, D4
arquivos: `scripts/conferir-busca.cjs`, `scripts/catalogo-funcoes.cjs`, `scripts/testa-conferir-busca.sh`
depende de: 2
busca:
- repo | rg -n "temRepo|existeNoHead|tarefaCobrada" scripts/conferir-busca.cjs | o laço de cmdPlano só cobra tarefa com caminho novo (`exige = caminhosNovos.length > 0`)
- catalogo | listar --raiz scripts | estendo cmdPlano de scripts/conferir-busca.cjs:175; leio definições com definicoesDoArquivo de scripts/catalogo-funcoes.cjs:157, que passa a ser exportada
desfecho: estender
mutacao:
  arquivo: `scripts/conferir-busca.cjs`
  de: `const exige = caminhosNovos.length > 0;`
  para: `const exige = caminhosNovos.length > 0 && false;`
  bateria: `bash scripts/testa-conferir-busca.sh`
  fixture: `testa-conferir-busca.sh, caso novo "tarefa que só edita arquivo existente sem linha catalogo é recusada"`
prova: `bash scripts/testa-conferir-busca.sh`
pronto quando: com um plano de fixture num repo git onde `src/x.js` existe no HEAD com `function soma()` na linha 3, `node scripts/conferir-busca.cjs plano --slug s --plano <arq>` dá estas saídas:
(a) tarefa `implementar` com `arquivos: src/x.js` e sem `busca:` → exit 2, recusa nomeando a tarefa e o canal `catalogo`;
(b) a mesma tarefa com `- catalogo | listar --raiz src | reaproveito soma de src/x.js:3` e `desfecho: adotar` → exit 0;
(c) com `src/x.js:4`, onde não começa definição → exit 2, recusa citando `src/x.js:4`;
(d) com `src/nao-existe.js:1` → exit 2;
(e) com `- catalogo | pulado: só corrige condição dentro de soma` → exit 0;
(f) tarefa que cria `src/novo.js` só com a linha `catalogo` e sem `repo` → exit 2, porque a regra antiga continua;
(g) tarefa `teste` ou `docs` sem `busca:` → exit 0;
(h) `desfecho: construir` com motivo que cita `D4` → exit 0, porque o motivo é livre.
Provado por `bash scripts/testa-conferir-busca.sh`, que cobre (a) a (h) e roda com zero `skipped`.

Critério de trava: os contornos são citar uma linha que não é definição (c), citar um arquivo fora do repo (d) e omitir o canal (a). Os casos legítimos vizinhos são o `pulado:` com motivo (e), o tipo isento (g) e o isolamento declarado (h). A parada é D7(a): o checador não julga se "nada equivalente" é verdade.

### 4. `campo-busca.md` e `skills/plano/SKILL.md` descrevem o canal `catalogo` [tipo: docs]
atende: D1, D2, D3, D4, D7
arquivos: `skills/plano/references/campo-busca.md`, `skills/plano/SKILL.md`
depende de: 3
mutacao: n/a
  motivo: texto de referência; o comportamento está na tarefa 3 e na bateria dela
pronto quando: com o `campo-busca.md` novo, as seções `Canal catalogo` e `Quando conta` dizem o mesmo que D2 e D3 do design: obrigatório em tarefa `implementar` com código existente ou novo; `pulado:` aceito com motivo; cada `arquivo:linha` conferido contra a definição; artefato isolado como `desfecho: construir` citando a decisão do design (D4); e o checador não julga a verdade do "nada equivalente" (D7). Conferido por leitura contra o design e por `node scripts/conferir-busca.cjs plano --slug 2026-11-13-reuso-antes-de-criar`, que tem de sair 0 sobre este próprio plano. O `SKILL.md` cresce no máximo uma linha, e `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` saem verdes.

### 5. `revisar` confere duplicata das funções novas [tipo: docs]
atende: D1, D5, D7
arquivos: `skills/revisar/SKILL.md`, `skills/revisar/references/duplicata-das-novas.md`, `agents/revisor.md`
depende de: 2
mutacao: n/a
  motivo: instrução ao revisor; o mecanismo mecânico (`novas`) é a tarefa 2
pronto quando: com o `references/duplicata-das-novas.md` novo, o passo dado ao revisor é este: rodar `catalogo-funcoes.cjs novas` contra a base do diff e `listar` no repo; comparar cada função nova com o catálogo; reprovar só quando houver duplicata HIGH (mesma entrada, mesma saída), com `arquivo:linha` das duas; deixar MEDIUM e LOW como observação; e não apontar artefato isolado que o design declara (D4), nem cópia que o próprio design decidiu (D7b). O texto diz o mesmo que D5 e D7 do design. O `skills/revisar/SKILL.md` ganha só um ponteiro de uma linha no molde do briefing, e `agents/revisor.md` ganha o passo no método. `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` saem verdes.

### 6. Versão 2.14.0, CHANGELOG e README [tipo: docs]
atende: D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4, 5
mutacao: n/a
  motivo: metadado de versão e texto
pronto quando: `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` dizem `2.14.0`, acima da maior versão que a `origin/main` e os outros worktrees ativos tiverem no momento (conferido com `git fetch` e `grep '"version"'` em cada um). O CHANGELOG tem a entrada 2.14.0 com as quatro mudanças (Method TLPP, `novas`, canal `catalogo`, duplicata no revisar). O README descreve o canal `catalogo` e a checagem do revisar onde hoje descreve `busca:` e `enxugar`. Conferido por leitura e por `bash scripts/testa-plugin-codex.sh` verde.
