# Plano: Reuso antes de criar

Design: docs/rainforest/design/2026-11-13-reuso-antes-de-criar.md

## O que não pode quebrar
- `aviso-duplicata` continua só com o conjunto `topo` e não passa a avisar `Method` de classes diferentes com o mesmo nome (D6).
- `listar`, `complexas`, `variacao`, `separar` e `conferir` mantêm a saída de hoje para JS, Dart e Python. A única mudança é a entrada nova de método ADVPL.
- Tarefa que cria arquivo novo continua recusada sem a linha `repo`. O canal `catalogo` se soma ao `repo`, não o substitui.
- `skills/plano/SKILL.md` e `skills/revisar/SKILL.md` ficam abaixo de 16384 bytes (`scripts/testa-teto-skills.sh`). Hoje estão em 16008 e 16086. Detalhe novo vai para `references/`.
- `node scripts/catalogo-funcoes.cjs <sub>` continua funcionando como CLI depois de virar módulo (`require`).

## Tarefas

### 1. Catálogo lê `Method x() Class Y` de ADVPL/TLPP [tipo: implementar]
atende: D6
arquivos: `hooks/lib/definicoes.cjs`, `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`
depende de: nenhuma
busca:
- repo | rg -n "metodo|advpl" hooks/lib/definicoes.cjs scripts/catalogo-funcoes.cjs | o mapa `metodo` já existe para js e dart, e `definicoesDoTexto` só o consulta para js e dart
- catalogo | listar --raiz hooks/lib | estendo a função casar de hooks/lib/definicoes.cjs, sem função nova
desfecho: estender
mutacao:
  arquivo: `scripts/catalogo-funcoes.cjs`
  de: `const conjuntos = ['dart', 'js', 'advpl'].includes(linguagem) ? ['topo', 'metodo'] : ['topo'];`
  para: `const conjuntos = ['dart', 'js'].includes(linguagem) ? ['topo', 'metodo'] : ['topo'];`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso novo "advpl: Method ... Class entra como Classe:metodo"`
prova: `bash scripts/testa-catalogo-funcoes.sh`
pronto quando: com um fonte `.tlpp` de fixture que tem `Class SaldoProjeto`, a declaração recuada `Method calcular()` dentro do corpo da classe e, mais abaixo, a implementação `Method calcular(cProj as character) as logical Class SaldoProjeto`, `node scripts/catalogo-funcoes.cjs listar --raiz <fixture>` devolve uma entrada `nome: "SaldoProjeto:calcular"` na linha da implementação e nenhuma na linha da declaração. A entrada `Class SaldoProjeto` continua saindo como hoje. Provado por `bash scripts/testa-catalogo-funcoes.sh` com o caso novo, terminando em exit 0.

Passos:
1. Em `hooks/lib/definicoes.cjs`, no objeto `REGRAS.metodo`, acrescentar a chave `advpl` com um regex só. Ele casa a linha de implementação: `^\s*method\s+(\w+)\s*\(` com qualquer coisa até o `)`, depois um `as <tipo>` opcional e, obrigatório, `\s+class\s+(\w+)`, com a flag `i`. O **grupo 1 é o nome do método e o grupo 2 é a classe**. A declaração dentro do corpo da classe não tem `class <Nome>` depois, então não casa.
2. Em `casar`, quando o regex que casou tem o grupo 2 preenchido (`m[2]`), devolver `` `${m[2]}:${m[1]}` ``. Senão devolver `m[1]` como hoje.
3. Em `scripts/catalogo-funcoes.cjs`, na função `definicoesDoTexto`, trocar a linha `const conjuntos = linguagem === 'dart' || linguagem === 'js' ? ['topo', 'metodo'] : ['topo'];` exatamente por `const conjuntos = ['dart', 'js', 'advpl'].includes(linguagem) ? ['topo', 'metodo'] : ['topo'];`.
4. `hooks/aviso-duplicata.cjs` não muda. Ele só chama `casar` com o conjunto `topo`. Não escrever teste para ele aqui: o caso passaria sem a mudança.

Nenhum caso de teste afirma sobre o texto do fonte. Os casos rodam o `listar` e conferem o JSON.

### 2. Subcomando `novas`: funções que o diff cria [tipo: implementar]
atende: D5
arquivos: `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`
depende de: 1
busca:
- repo | rg -n "function arquivosDoDiff|function baseDoDiff|function definicoesDoTexto|gitSaida" scripts/catalogo-funcoes.cjs | arquivosDoDiff, baseDoDiff, gitSaida e definicoesDoTexto já leem os dois lados do diff para o variacao
- catalogo | listar --raiz scripts | componho as funções arquivosDoDiff, baseDoDiff e definicoesDoTexto de scripts/catalogo-funcoes.cjs; a função variacao não serve inteira porque mede só js e dart
desfecho: compor
mutacao:
  arquivo: `scripts/catalogo-funcoes.cjs`
  de: `if (!naBase.has(chave)) novas.push({ arquivo: rel, ...d });`
  para: `novas.push({ arquivo: rel, ...d });`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso novo "novas: lista só a definição criada pelo diff"`
prova: `bash scripts/testa-catalogo-funcoes.sh`
pronto quando: num repo git de fixture cuja base tem `a.js` com `function velha()` e cujo commit seguinte acrescenta `function nova()` em `a.js` e cria `b.tlpp` com `Static Function outra()`, `node scripts/catalogo-funcoes.cjs novas --raiz <fixture> --base <sha da base>` imprime um array JSON com exatamente duas entradas, `nova` (arquivo `a.js`) e `outra` (arquivo `b.tlpp`), cada uma com `arquivo`, `linha`, `nome`, `assinatura` e `linguagem`, ordenadas por arquivo e linha, sem `velha`. Com `--base naoexiste`, sai com exit 1 e o stderr começa com `novas: base não resolvida: naoexiste`. Provado por `bash scripts/testa-catalogo-funcoes.sh` terminando em exit 0.

Passos:
1. Nova função `novas(raiz, base)`. Para cada `rel` de `arquivosDoDiff(raiz, base)` com extensão em `EXTENSOES`:
   - lê o lado atual do **disco**, como o `variacao` faz;
   - lê o lado da base com `gitSaida(raiz, ['show', `${base}:${rel}`])`, e saída `null` vale texto vazio, ou seja, arquivo novo;
   - calcula as definições dos dois lados com `definicoesDoTexto(texto, linguagem, 0)`;
   - monta `naBase` como `Set` das chaves `` `${rel}\u0000${d.nome}` `` da base;
   - para cada definição atual, faz `const chave = `${rel}\u0000${d.nome}`;` e, na linha exata do `de:` acima, `if (!naBase.has(chave)) novas.push({ arquivo: rel, ...d });`.
   Ordena por arquivo e linha, e devolve o array. O campo `contexto` sai vazio, porque o `contextoN` é 0.
2. Acrescentar `'novas'` na lista `subs` de `principal`, e o ramo `if (sub === 'novas')` com o mesmo tratamento de raiz e base do ramo `variacao`. As mensagens de erro trocam o prefixo `variacao:` por `novas:`. A saída é `JSON.stringify(array)` mais uma quebra de linha.
3. Acrescentar a linha `novas --raiz <dir> [--base <ref>]` no texto `USO`.

### 3. Canal `catalogo` no `busca:`, obrigatório em tarefa de código, com `arquivo:linha` conferido [tipo: implementar]
atende: D2, D3, D4
arquivos: `scripts/conferir-busca.cjs`, `scripts/catalogo-funcoes.cjs`, `scripts/testa-conferir-busca.sh`
depende de: 2
busca:
- repo | rg -n "temRepo|existeNoHead|tarefaCobrada|caminhosNovos" scripts/conferir-busca.cjs | o laço de cmdPlano só cobra tarefa com caminho novo
- catalogo | listar --raiz scripts | estendo a função cmdPlano de scripts/conferir-busca.cjs e leio definições com definicoesDoArquivo de scripts/catalogo-funcoes.cjs, que passa a ser exportada
desfecho: estender
mutacao:
  arquivo: `scripts/conferir-busca.cjs`
  de: `const exige = candidatos.length > 0;`
  para: `const exige = caminhosNovos.length > 0;`
  bateria: `bash scripts/testa-conferir-busca.sh`
  fixture: `testa-conferir-busca.sh, caso novo "catalogo (a): tarefa que só edita arquivo existente sem busca é recusada"`
prova: `bash scripts/testa-conferir-busca.sh`
pronto quando: com um plano de fixture num repo git onde `src/x.js` existe no HEAD com `function soma()` na linha 3, `node scripts/conferir-busca.cjs plano --slug s --plano <arq>` responde assim:
(a) tarefa `implementar` com `arquivos: src/x.js` e sem `busca:` → exit 2, recusa citando a tarefa e o canal `catalogo`;
(b) mesma tarefa com `busca:` contendo só `- catalogo | listar --raiz src | reaproveito soma de src/x.js:3` e `desfecho: adotar` → exit 0;
(c) idem com `src/x.js:4` → exit 2, recusa citando `src/x.js:4`;
(d) idem com `src/nao-existe.js:1` → exit 2; idem com `../fora.js:1` → exit 2; idem com `README.md:1` → exit 2, "extensão que o catálogo não lê";
(e) `- catalogo | pulado: só corrige condição dentro de soma` com `desfecho: estender` → exit 0;
(f) tarefa que cria `src/novo.js` com só a linha `catalogo` e sem `repo` → exit 2, como já é hoje;
(g) tarefa `teste` ou `docs` sem `busca:` → exit 0;
(h) linha `- catalogo | listar --raiz src | isolado de propósito (D4 do design), não reaproveito soma de src/x.js:3` com `desfecho: construir` → exit 0;
(i) `- catalogo | listar --raiz src | nada equivalente`, sem referência, com `desfecho: construir` → exit 0;
(j) mesma tarefa com `busca:` e linha `catalogo` mas sem `desfecho:` → exit 2.
Provado por `bash scripts/testa-conferir-busca.sh` terminando em `vermelhas:[]` e exit 0. Também `node scripts/catalogo-funcoes.cjs listar --raiz scripts` continua imprimindo JSON, o que mostra que a CLI segue viva depois do `require`.

Regras que o executor implementa, sem decidir nada além delas:
1. **Exportar sem disparar a CLI.** Em `scripts/catalogo-funcoes.cjs`, o bloco `try { principal(process.argv.slice(2)); } catch ...` no fim do arquivo passa a ficar dentro de `if (require.main === module) { ... }`. Logo antes dele, acrescentar `module.exports = { definicoesDoArquivo, definicoesDoTexto, EXTENSOES };`, com `EXTENSOES` vindo do mesmo `require` de `hooks/lib/definicoes.cjs` que o arquivo já faz.
2. **Quem é cobrado.** Em `cmdPlano`, no laço `for (const tarefa of cobradas)`, trocar `const exige = caminhosNovos.length > 0;` por `const exige = candidatos.length > 0;`. `candidatos` já exclui teste, `.md` e glob. O `quem` da recusa cita o primeiro candidato, e diz "cria" quando ele é novo e "edita" quando existe.
3. **O que se exige de quem é cobrado.** Bloco `busca:` presente; uma linha de canal `catalogo`, com resultado ou com `pulado: <motivo>`; `desfecho:` válido, como hoje; e a linha `repo` **só quando `caminhosNovos.length > 0`**, como hoje. Recusa sem `catalogo`: `` `${quem}; \`busca:\` sem o canal \`catalogo\`. Falta uma linha \`- catalogo | listar --raiz <pasta> | <reaproveito X de arquivo:linha | nada equivalente>\` ou \`- catalogo | pulado: <motivo>\`.` ``.
4. **Referências conferidas.** Só no último campo (o resultado) da linha `catalogo` sem `pulado:`, extrair todas as ocorrências de `/([\w.\/-]+\.[A-Za-z0-9]+):L?(\d+)/g`. Para cada `arquivo:linha`:
   - caminho absoluto, com `\` ou com `..` → recusa `referência fora do repositório`;
   - extensão fora de `EXTENSOES` → recusa `extensão que o catálogo não lê`;
   - arquivo inexistente em `path.join(repo, arquivo)` → recusa `arquivo não existe`;
   - nenhuma entrada de `definicoesDoArquivo(repo, arquivo, 0)` com `linha` igual ao número → recusa `não começa definição em <arquivo>:<linha>`.
   Toda recusa cita `<arquivo>:<linha>`. Resultado sem referência (`nada equivalente`, ou texto livre como o de (h)) passa sem conferência. O texto do resultado não é julgado (D7a).
5. **Isolamento declarado (D4).** `desfecho:` continua sendo uma palavra só. O motivo do isolamento vai no resultado da linha `catalogo`, como em (h), e o checador não o interpreta.

### 4. `campo-busca.md` e `skills/plano/SKILL.md` descrevem o canal `catalogo` [tipo: docs]
atende: D1, D2, D3, D4, D7
arquivos: `skills/plano/references/campo-busca.md`, `skills/plano/SKILL.md`
depende de: 3
mutacao: n/a
  motivo: texto de referência; o comportamento está na tarefa 3 e na bateria dela
pronto quando: com o `campo-busca.md` novo, o texto diz o mesmo que D2, D3, D4 e D7 do design, e o checador concorda com ele sobre este próprio plano. Conferido assim:
- `node scripts/conferir-busca.cjs plano --slug 2026-11-13-reuso-antes-de-criar` sai 0 sobre este plano. As linhas `catalogo` das tarefas 1 a 3 citam funções por nome, sem `arquivo:linha`, então não deslocam com as edições;
- `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` saem com exit 0.

Passos:
1. Em `skills/plano/SKILL.md`, a seção `### Campo \`busca:\` — procurar antes de construir` tem a frase que começa "Tarefa `implementar` (ou sem tipo) que cria caminho novo de código declara a busca antes de escrever". Reescrevê-la para dizer que tarefa `implementar` (ou sem tipo) que **toca** código declara o bloco com o canal `catalogo`; que a que **cria** arquivo também leva o `repo`; e que vale `desfecho:`. Manter o ponteiro para `references/campo-busca.md`. O arquivo final fica abaixo de 16384 bytes. Se faltar espaço, encurtar a própria seção, sem mexer nas outras.
2. Em `skills/plano/references/campo-busca.md`:
   - acrescentar `- Canal catalogo` no índice, entre `Canal repo` e `Canal doc`;
   - criar a seção `## Canal \`catalogo\`` com as regras 3, 4 e 5 da tarefa 3 em prosa: forma da linha, `pulado:` com motivo, a regex de `arquivo:linha` no resultado, as quatro recusas, o isolamento no resultado com `desfecho: construir`, e o que o checador não julga (D7a);
   - incluir um exemplo de bloco com `repo` e `catalogo`;
   - reescrever `## Canal \`repo\`` para dizer que ele é obrigatório só quando a tarefa cria arquivo;
   - reescrever `## Quando conta`, porque `busca:` passa a valer para toda tarefa `implementar` ou sem tipo com caminho de código, novo ou existente;
   - acrescentar no `## Origem` uma linha citando o design `2026-11-13-reuso-antes-de-criar`.

### 5. `revisar` confere duplicata das funções novas [tipo: docs]
atende: D1, D5, D7
arquivos: `skills/revisar/SKILL.md`, `skills/revisar/references/duplicata-das-novas.md`, `agents/revisor.md`
depende de: 2
mutacao: n/a
  motivo: instrução ao revisor; o mecanismo mecânico (`novas`) é a tarefa 2
pronto quando: com os três arquivos novos ou editados, o passo do revisor diz o mesmo que D5 e D7 do design. Conferido por leitura contra o design, e por `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` com exit 0.

Passos:
1. Criar `skills/revisar/references/duplicata-das-novas.md` com:
   - (a) o porquê, citando o design;
   - (b) o passo: `node <plugin>/scripts/catalogo-funcoes.cjs novas --raiz <repo> --base <base do briefing>` lista as funções que o diff cria; `listar --raiz <repo> --contexto 3` dá o catálogo do repo; cada função nova é comparada com as do catálogo de nome parecido ou de mesma pasta e com as que o próprio diff toca, abrindo a implementação das candidatas;
   - (c) a escala de confiança copiada de `skills/enxugar/references/duplicata-semantica.md` (HIGH: mesma entrada dá a mesma saída; MEDIUM; LOW);
   - (d) a consequência: HIGH é achado de severidade "comportamento errado", com `arquivo:linha` da nova e da existente, e leva a `VEREDITO: reprovado`; MEDIUM e LOW vão para observações, sem reprovar;
   - (e) o que não é achado: artefato isolado que o design declara (D4), cópia que o design decidiu, wrapper que só chama a existente (pela trava de wrapper do `enxugar`), e `ModelDef`/`ViewDef`/`MenuDef` e entradas de convenção do framework;
   - (f) a lista de linguagens: as que o catálogo lê, e fora delas a checagem é declarada pulada.
2. Em `skills/revisar/SKILL.md`, no fim da seção `## Escopo fixado por diff`, acrescentar exatamente esta linha: `Funções que o diff cria são comparadas com o catálogo do repo; duplicata HIGH reprova: \`references/duplicata-das-novas.md\`.` Se o arquivo passar de 16384 bytes, encurtar a mesma seção até caber.
3. Em `agents/revisor.md`, logo depois do passo (b) "Evidência primária", acrescentar o passo `(b2) **Duplicata do que o diff cria**`, com duas frases que remetem a `skills/revisar/references/duplicata-das-novas.md` e dizem que HIGH reprova e o resto é observação.

### 6. Versão 2.14.0, CHANGELOG e README [tipo: docs]
atende: D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4, 5
mutacao: n/a
  motivo: metadado de versão e texto
pronto quando: `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` dizem `2.14.0`, e essa versão está acima da maior entre a `origin/main` e os worktrees ativos no momento. Conferido com `git fetch` e `grep '"version"'` em cada worktree de `git worktree list`. Também `bash scripts/testa-plugin-codex.sh` sai com exit 0.

Passos:
1. Nos dois `plugin.json`, trocar o `version` para `2.14.0`.
2. No `CHANGELOG.md`, acrescentar `## 2.14.0 — 2026-11-13` acima de `## 2.13.2`, no mesmo formato das entradas vizinhas, com quatro itens do ponto de vista de quem usa:
   - o catálogo passa a ler `Method ... Class` de TLPP;
   - o subcomando `novas`;
   - o plano cobra o canal `catalogo` em toda tarefa de código;
   - o revisar reprova duplicata HIGH do que o diff cria.
3. No `README.md`, na linha da tabela que descreve o estágio `plano` (`rg -n "busca:" README.md` acha a linha), acrescentar o canal `catalogo`. Na linha que descreve o `enxugar` ou o `revisar`, acrescentar a checagem de duplicata das funções novas. Uma frase em cada, sem seção nova.
