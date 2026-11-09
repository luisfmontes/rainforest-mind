# Plano: aviso de contexto alto na fronteira de estágio

Design: docs/rainforest/design/2026-11-09-aviso-contexto-alto.md

## O que não pode quebrar
- `exigir` mantém o exit e o stdout de hoje em todo caso, inclusive nas recusas.
- Toda bateria que copia `scripts/estado.cjs` para uma caixa sem listar a lib nova segue verde.
- Nenhuma falha de leitura do transcript ou da config aparece como erro.

## Tarefas

### 1. Ler o uso de contexto da cauda do transcript [tipo: implementar]
atende: D1, D2, D6
arquivos: `scripts/lib/uso-contexto.cjs`, `scripts/testa-uso-contexto.sh`
depende de: nenhuma
busca:
- repo | rg "cache_read_input_tokens" scripts hooks | só scripts/poda.cjs e relatorio-poda.cjs, que somam stream SSE do proxy, não transcript
- repo | rg "function acharTranscrito" scripts | calibrar-limiar-assunto.cjs:51 não exporta, e varre as duas pastas de conta em vez de seguir CLAUDE_CONFIG_DIR
- ideias | ideias.jsonl "aviso-de-contexto-alto-pelo-uso-real" | aponta o ECC, que lê a cauda e soma os mesmos campos; a tabela de janela dele ficou de fora (D3)
desfecho: construir
mutacao:
  arquivo: `scripts/lib/uso-contexto.cjs`
  de: `const total = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);`
  para: `const total = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0);`
  bateria: `bash scripts/testa-uso-contexto.sh`
  fixture: `testa-uso-contexto.sh, caso "uso acima do limiar avisa com tokens, limiar e estagio"`
prova: `bash scripts/testa-uso-contexto.sh`
pronto quando: com um transcript no formato real (`type: assistant`, `message.usage` com os três campos) cuja última mensagem soma 712000 tokens, sendo a maior parte em `cache_read_input_tokens`, `avisoDeContexto(700000, 'plano')` devolve o texto da D6 com `712 mil`, `700 mil` e `'plano'`; com linha final truncada, mensagem `<synthetic>` zerada ou `isSidechain` no fim, vale a mensagem anterior; depois de uma compactação (última mensagem baixa), não devolve nada; id com `../`, sessão sem transcript e sessão sem variável não devolvem nada — provado por `bash scripts/testa-uso-contexto.sh` devolvendo `falhou: 0`.

Forma prescrita: `scripts/lib/uso-contexto.cjs` exporta `usoDoTranscrito(env)`, que devolve o número ou `null`, e `avisoDeContexto(limiar, estagio, env = process.env)`, que devolve a linha ou `null`. Nenhum caso de teste afirma sobre o texto do fonte.

### 2. Chave `contexto-alto-tokens` e aviso no `exigir` [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/lib/config.cjs`, `scripts/estado.cjs`, `scripts/testa-uso-contexto.sh`, `hooks/testa-config.sh`
depende de: 1
busca:
- repo | rg "aviso: checkout principal" scripts/estado.cjs | é o aviso em stderr que já abre o exigir; o novo fica ao lado dele
- livro | pulado: mudança local num subcomando que já existe
desfecho: estender
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const aviso = avisoDeContexto(valores['contexto-alto-tokens'], estagio);`
  para: `const aviso = avisoDeContexto(700000, estagio);`
  bateria: `bash scripts/testa-uso-contexto.sh`
  fixture: `testa-uso-contexto.sh, caso "limiar do projeto vale no exigir"`
prova: `bash scripts/testa-uso-contexto.sh`
pronto quando: com uma sessão cujo transcript soma 712000 tokens, `node scripts/estado.cjs exigir --slug caixa --estagio limpar` sai 0, imprime o aviso em stderr e o stdout é igual ao de uma sessão sem transcript; com `{"contexto-alto-tokens":100000}` no `.rainforest/config.json` do projeto e 120000 tokens o aviso sai; com `0` não sai mesmo em 900000; com valor inválido vale 700000; um `exigir` recusado segue saindo 2 e avisa; com `scripts/lib/uso-contexto.cjs` apagado da caixa o `exigir` sai 0 sem aviso e sem erro — provado por `bash scripts/testa-uso-contexto.sh` devolvendo `falhou: 0`.

Forma prescrita: função `avisarContextoAlto(estagio)` em `scripts/estado.cjs`, chamada depois da validação do estágio e antes das recusas, com os dois `require` dentro do `try`. O tipo `tokens` em `validarTipo` aceita inteiro maior ou igual a zero. `hooks/testa-config.sh` ganha o padrão, o valor do projeto e o inválido.

### 3. Documentar a chave e subir a versão [tipo: docs]
atende: D3, D6
arquivos: `skills/setup/SKILL.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2
mutacao: n/a
  motivo: tarefa só descreve a chave e sobe a versão; o comportamento está nas tarefas 1 e 2
pronto quando: com a chave nova em `CHAVES`, a tabela de `skills/setup/SKILL.md` traz `contexto-alto-tokens` com o padrão 700000 e o `0` que desliga, coerentes com a D3, e o CHANGELOG 2.11.0 descreve o aviso com o limiar e o local da D4 — provado por `bash scripts/testa-conferir-setup.sh` devolvendo `0 falha(s)` e por `node scripts/conferir-versao.cjs` saindo 0.
