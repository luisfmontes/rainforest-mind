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
  de: `(x.cache_creation_input_tokens || 0) + (x.cache_read_input_tokens || 0);`
  para: `(x.cache_creation_input_tokens || 0);`
  bateria: `bash scripts/testa-uso-contexto.sh`
  fixture: `testa-uso-contexto.sh, caso "uso acima do limiar avisa com tokens, limiar e estagio"`
prova: `bash scripts/testa-uso-contexto.sh`
pronto quando: com um transcript no formato real (`type: assistant`, `message.usage` com os três campos) cuja última mensagem soma 320000 tokens, sendo a maior parte em `cache_read_input_tokens`, o aviso traz o texto da D6 com `320 mil`, `310 mil` e o estágio; com `usage.iterations` de uma resposta que consultou o advisor (topo em 620 mil, última iteração `message` em 320 mil), o aviso diz `320 mil`, e com a última iteração em 200 mil não sai; iteração `advisor_message` no fim da lista é ignorada; uma mensagem alta antes de 1,2 MB de outro conteúdo não conta, e uma 200 KB antes do fim ainda conta; sem `CLAUDE_CONFIG_DIR`, o transcript se acha em `~/.claude`; com linha final truncada, mensagem `<synthetic>` zerada ou `isSidechain` no fim, vale a mensagem anterior; depois de uma compactação (última mensagem baixa), não devolve nada; id com `../`, sessão sem transcript e sessão sem variável não devolvem nada — provado por `bash scripts/testa-uso-contexto.sh` devolvendo `falhou: 0`.

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
  para: `const aviso = avisoDeContexto(310000, estagio);`
  bateria: `bash scripts/testa-uso-contexto.sh`
  fixture: `testa-uso-contexto.sh, caso "limiar do projeto vale no exigir"`
prova: `bash scripts/testa-uso-contexto.sh`
pronto quando: com uma sessão cujo transcript soma 320000 tokens, `node scripts/estado.cjs exigir --slug caixa --estagio limpar` sai 0, imprime o aviso em stderr e o stdout é igual ao de uma sessão sem transcript; com `{"contexto-alto-tokens":100000}` no `.rainforest/config.json` do projeto e 120000 tokens o aviso sai; com `0` não sai mesmo em 900000; com valor inválido vale 310000; um `exigir` recusado segue saindo 2 e avisa; com `scripts/lib/uso-contexto.cjs` apagado da caixa o `exigir` sai 0 sem aviso e sem erro — provado por `bash scripts/testa-uso-contexto.sh` devolvendo `falhou: 0`.

Forma prescrita: função `avisarContextoAlto(estagio)` em `scripts/estado.cjs`, chamada depois da validação do estágio e antes das recusas, com os dois `require` dentro do `try`. O tipo `tokens` em `validarTipo` aceita inteiro maior ou igual a zero. `hooks/testa-config.sh` ganha o padrão, o valor do projeto e o inválido.

### 3. Documentar a chave e subir a versão [tipo: docs]
atende: D3, D6
arquivos: `skills/setup/SKILL.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2
mutacao: n/a
  motivo: tarefa só descreve a chave e sobe a versão; o comportamento está nas tarefas 1 e 2
pronto quando: com a chave nova em `CHAVES`, a tabela de `skills/setup/SKILL.md` traz `contexto-alto-tokens` com o padrão 310000 e o `0` que desliga, coerentes com a D3, e o CHANGELOG 2.11.0 descreve o aviso com o limiar e o local da D4 — provado por `bash scripts/testa-conferir-setup.sh` devolvendo `0 falha(s)` e por `node scripts/conferir-versao.cjs` saindo 0.

### 4. Trava espera EPERM passageiro ao nascer no Windows [tipo: implementar]
atende: D5
arquivos: `hooks/lib/trava-jsonl.cjs`, `scripts/testa-estado-trava.cjs`, `hooks/testa-gate-teto-despachos.cjs`, `CHANGELOG.md`
depende de: nenhuma
busca:
- repo | rg "EPERM" hooks/lib scripts/lib | só contexto-sessao.cjs e trava-jsonl.cjs:57 (processoVivo), nenhum trata EPERM ao abrir arquivo
desfecho: estender
mutacao:
  arquivo: `hooks/lib/trava-jsonl.cjs`
  de: `if ((e.code === "EPERM" || e.code === "EACCES") && Date.now() <= limite) {`
  para: `if (false) {`
  bateria: `node scripts/testa-estado-trava.cjs`
  fixture: `testa-estado-trava.cjs, caso "N1: EPERM passageiro ao criar a trava espera e entra"`
prova: `node scripts/testa-estado-trava.cjs`
pronto quando: com o `fs.openSync(<lock>, "wx")` da trava lançando `EPERM` nas duas primeiras tentativas, como o Windows faz quando outro processo acabou de apagar a trava, `comTrava` entra na terceira e devolve o resultado da função; com `EPERM` permanente e limite de 0,3 s, propaga `EPERM` entre 0,25 s e 5 s — provado por `node scripts/testa-estado-trava.cjs` devolvendo `0 falha(s)`.

Emenda de 2026-11-10: o CI do PR #676 negou 1 de 12 despachos simultâneos em `hooks/testa-gate-teto-despachos.cjs` com `EPERM: operation not permitted, open '...fluxos/...'`. A falha existia antes desta mudança e o PR não fecha sem ela (D5: o aviso entra no `exigir`, que já depende da mesma trava).
