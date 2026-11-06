# Plano: Régua LGPD no auditor e duplicata semântica no enxugar

Design: docs/rainforest/design/lgpd-e-duplicata.md

## O que não pode quebrar
- O `hooks/aviso-duplicata.cjs` continua avisando definição de mesmo nome em JS/TS, Python e ADVPL como hoje: `bash hooks/testa-aviso-duplicata.sh` verde depois de as regras irem para `hooks/lib/definicoes.cjs`.
- As réguas 1, 2 e 3 do auditor ficam intactas: toda checagem que já existe em `scripts/testa-auditor-de-seguranca.sh` segue verde.
- `skills/enxugar/SKILL.md` fica abaixo de 500 linhas e 16 384 bytes (`bash scripts/testa-teto-skills.sh`); o detalhe da passada nova mora em `skills/enxugar/references/`.
- O conjunto de peças do `conferir-categoria` não muda (66): o script novo não se chama `conferir-*` e `hooks/lib/` não é varrido.
- Nenhum nome de empregador, cliente ou projeto de trabalho entra no repositório público: os caminhos dos dois repos-alvo do D13 vivem só no briefing da sessão.

## Tarefas

### 1. Catálogo de funções com Dart, conferência e maiores arquivos [tipo: implementar]
atende: D7, D9, D10, D11
arquivos: `hooks/lib/definicoes.cjs`, `hooks/aviso-duplicata.cjs`, `hooks/testa-aviso-duplicata.sh`, `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`
depende de: nenhuma
busca:
- repo | rg "REGRAS|EXTENSOES|nomeDaLinha" hooks scripts | só hooks/aviso-duplicata.cjs tem a tabela de definição (JS/TS, Python, ADVPL, só topo de arquivo); nada lê Dart nem método de classe
- livro | vigias/livro-de-repos.md "superpowers-lab" | sem linha: repo novo, trilha enxertar (D12)
- web | obra/superpowers-lab skills/finding-duplicate-functions/scripts/extract-functions.sh | bash + rg + jq, só TS/JS; lido em 2026-11-06
desfecho: estender
mutacao:
  arquivo: `hooks/lib/definicoes.cjs`
  de: `'.dart': 'dart',`
  para: `'.dartx': 'dart',`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso "dart: função de topo e método de classe entram no catálogo"`
prova: `bash scripts/testa-catalogo-funcoes.sh`
pronto quando: com o próprio repositório do plugin como entrada real, `node scripts/catalogo-funcoes.cjs listar --raiz .` devolve um JSON (array de `{arquivo, linha, nome, assinatura, contexto, linguagem}`) em que a entrada `cmdPlantar` aponta para `scripts/ideias.cjs` na mesma linha que `grep -n "^function cmdPlantar" scripts/ideias.cjs` devolve; `node scripts/catalogo-funcoes.cjs maiores --raiz . --top 5` imprime 5 linhas `<n> linhas  <caminho>` em ordem decrescente cujo primeiro número casa com `wc -l` do primeiro caminho; `node scripts/catalogo-funcoes.cjs conferir --catalogo <c> --grupos <g>` sai 1 e nomeia a função quando `<g>` cita `cmdPlantar` numa linha errada, e sai 0 quando a linha é a real — provado por `bash scripts/testa-catalogo-funcoes.sh`, que monta essas três entradas sobre o repo real e uma fixture com JS, Dart (`*.g.dart` e pasta `.dart_tool/` presentes e ausentes da saída) e Python, e por `bash hooks/testa-aviso-duplicata.sh` seguindo verde

Forma prescrita para o código novo (o `de:` acima é a única linha ditada): `hooks/lib/definicoes.cjs` exporta a tabela de extensões (com `'.dart': 'dart',` como entrada própria, numa linha só) e as regras por linguagem em dois conjuntos, `topo` (o que o `aviso-duplicata` já usa) e `metodo` (método de classe recuado: JS/TS com visibilidade/async/static/get/set, Dart com tipo de retorno); o `aviso-duplicata` passa a importar `topo` e a tabela, sem mudar o que avisa. `scripts/catalogo-funcoes.cjs` tem marca `// @categoria: sensor` na linha 2, subcomandos `listar`, `maiores`, `separar` (lê o catálogo categorizado e grava um JSON por categoria com 3+ funções, `--minimo` muda o piso) e `conferir`; lista arquivos por `git ls-files` quando há git (respeita `.gitignore`) e por varredura de pasta quando não há; pula testes (`*.test.*`, `*.spec.*`, `__tests__/`, `test/`, `tests/`, `*_test.dart`) salvo `--incluir-testes`, e gerados (`node_modules/`, `build/`, `dist/`, `.dart_tool/`, `*.g.dart`, `*.freezed.dart`). Nenhum caso da bateria afirma sobre o texto do fonte: todos afirmam sobre a saída dos subcomandos.

### 2. Passada de duplicata semântica no modo 2 do enxugar [tipo: docs]
atende: D6, D8, D9, D10, D11
arquivos: `skills/enxugar/SKILL.md`, `skills/enxugar/references/duplicata-semantica.md`, `scripts/testa-enxugar-estrutura.sh`
depende de: 1
mutacao:
  arquivo: `skills/enxugar/SKILL.md`
  de: `### Passada de duplicata semântica`
  para: `### Passada removida`
  bateria: `bash scripts/testa-enxugar-estrutura.sh`
  fixture: `testa-enxugar-estrutura.sh, caso "modo 2 tem a passada de duplicata semântica com as cinco fases"`
pronto quando: com o `skills/enxugar/SKILL.md` real, o modo 2 tem a seção `### Passada de duplicata semântica` que prescreve as fases do D8/D9 na ordem — `catalogo-funcoes.cjs listar`, agente **haiku** que categoriza, `separar` com piso 3, um agente **sonnet** por categoria, `conferir` antes de qualquer achado — e diz que só HIGH/MEDIUM com CONSOLIDATE vira `duplicar:`, INVESTIGATE vai para "investigar" e KEEP_SEPARATE não aparece; o modo 2 abre com `maiores` como contexto fora do `líquido:` (D10); a seção nomeia o `aviso-duplicata` como a cobertura de mesmo nome (D6); `references/duplicata-semantica.md` traz o prompt de categorização com a lista de categorias e o prompt de comparação com o formato JSON `{intent, confidence, functions:[{file,name,line,notes}], differences, recommendation:{action,survivor,reason}}` — provado por `bash scripts/testa-enxugar-estrutura.sh` (que confere cada um desses itens contra o D6, D8, D9 e D10, e que `haiku` aparece na fase de categorizar e `sonnet` na de comparar, não o contrário) e por `bash scripts/testa-teto-skills.sh`

### 3. Régua 4 — LGPD no auditor de segurança [tipo: docs]
atende: D1, D2, D3, D4, D5, D11
arquivos: `agents/auditor-de-seguranca.md`, `scripts/testa-auditor-de-seguranca.sh`
depende de: nenhuma
mutacao:
  arquivo: `agents/auditor-de-seguranca.md`
  de: `## Régua 4 — LGPD`
  para: `## Régua 4 — removida`
  bateria: `bash scripts/testa-auditor-de-seguranca.sh`
  fixture: `testa-auditor-de-seguranca.sh, bloco "Régua 4 — LGPD: gatilho, nove categorias, tabela normativa"`
pronto quando: com o `agents/auditor-de-seguranca.md` real, o passo (a) do método declara a Régua 4 com o gatilho do D1 (inventário acha dado pessoal) e a obrigação de dizer por que foi pulada; o bloco `## Régua 4 — LGPD` tem as nove categorias L1 a L9 do D2, cada uma com "onde procurar" que não depende de framework e um exemplo de Dart/Flutter ou de TypeScript; a tabela normativa do D3 traz cada artigo listado no D3 (LGPD 5º II, 6º III, 6º X, 7º, 8º § 4º, 8º § 5º, 8º § 6º, 11, 12, 14, 15, 16, 18, 19 II, 20, 33, 46; Res. ANPD 15/2024 Arts. 6º e 10; Res. 2/2022 Art. 14; Marco Civil Arts. 13 e 15; Lei 15.211/2025 Arts. 9º § 1º, 22, 24, 26), com a fonte `goul4rt/lgpd-skills` no commit `d85d79abee`, a data e a frase de que o texto oficial prevalece; a régua manda escrever "sem citação na tabela" em vez de citar artigo fora dela; os documentos do D4 aparecem como fora da régua e o veredito diz "indício técnico, não parecer jurídico"; os três cruzamentos do D5 (L1–A09, L7–A04, L3/L4–A01) estão escritos; o formato do relatório ganha a seção `## Achados — LGPD` — provado por `bash scripts/testa-auditor-de-seguranca.sh`, cujo bloco novo confere cada item acima restrito ao trecho entre `## Régua 4 — LGPD` e a seção seguinte (como as réguas 1 e 2 já fazem), e cujas checagens antigas seguem verdes

### 4. README, livro de repos e versão 2.4.0 [tipo: docs]
atende: D12
arquivos: `README.md`, `vigias/livro-de-repos.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`
depende de: 1, 2, 3
mutacao: n/a
  motivo: tarefa só de texto e número de versão; não há comportamento a inverter — a falsificação é a coerência com o que as tarefas 1 a 3 entregaram, conferida no critério
pronto quando: com o repositório real, o README descreve a Régua 4 junto da frase que hoje lista as réguas do `auditor-de-seguranca` (linha que começa com "O `auditor-de-seguranca` roda") e a passada de duplicata semântica do `enxugar` citando `scripts/catalogo-funcoes.cjs`, sem seção de crédito nova para os dois repos (D12); o livro tem uma linha `| \`goul4rt/lgpd-skills\` |` e uma `| \`obra/superpowers-lab\` |`, ambas com data 2026-11-06 e veredito na trilha enxertar; `.claude-plugin/plugin.json` diz `"version": "2.4.0"` e o `CHANGELOG.md` abre com 2.4.0 — provado por `grep -c "Régua 4" README.md` ≥ 1, `grep -c "catalogo-funcoes" README.md` ≥ 1, `grep -cE "^\| \`(goul4rt/lgpd-skills|obra/superpowers-lab)\` \| 2026-11-06" vigias/livro-de-repos.md` = 2, `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` = `2.4.0`, e `bash scripts/testa-plugin-codex.sh` e `bash hooks/testa-abertura-mod-config.sh` verdes

### 5. Prova nos dois repos reais do Luís [tipo: pesquisar]
atende: D13
arquivos: `docs/rainforest/estado/lgpd-e-duplicata.json`
depende de: 1, 2, 3
mutacao: n/a
  motivo: é execução de leitura em repositório externo, sem código deste repo a inverter; a mutação das tarefas 1 a 3 já cobre o comportamento
pronto quando: com o repo do site como entrada real (caminho no briefing da sessão, nunca neste repo), um agente que segue o `agents/auditor-de-seguranca.md` **deste worktree** entrega relatório no scratchpad da sessão que declara a Régua 4 aplicada (o inventário achou dado pessoal) e traz ao menos um achado `L1`–`L9` com `arquivo:linha`; com o repo do app como entrada real, `node scripts/catalogo-funcoes.cjs listar --raiz <app>` devolve ao menos uma entrada com `"linguagem":"dart"`, e a passada da tarefa 2 entrega ao menos uma linha `duplicar:` que passou pelo `conferir`, ou declara zero colando o número de funções e de categorias com 3+; cada `arquivo:linha` dos dois relatórios é conferido por `sed -n '<linha>p' <arquivo>` mostrando o trecho citado; `git -C <repo> status --short` antes e depois é idêntico nos dois repos — provado pela saída colada desses comandos no `verificar`
