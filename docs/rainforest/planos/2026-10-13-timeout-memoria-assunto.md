# Plano: memoria-assunto-prompt dentro do timeout (#509, #507)

Design: docs/rainforest/design/2026-10-13-timeout-memoria-assunto.md

## O que não pode quebrar
- `acharAlvo` devolve o mesmo alvo (origem, id, conteudo) com e sem cache, para as três formas de linha que ela casa hoje (com apelido, projeto cru com teto do assunto, projeto cru) e para resumos.
- Chamada de `acharAlvo` sem o 4º argumento se comporta exatamente como hoje.
- O hook `memoria-assunto-prompt.cjs` continua síncrono, saindo 0 e calado em qualquer falha (D6 do design 2026-10-08-memoria-por-assunto).
- `pontuarSessao` grava as mesmas linhas de `uso_memoria` que grava hoje.

## Tarefas

### 1. Cache por laço em acharAlvo, com bateria de contagem [tipo: implementar]
atende: D1, D5
arquivos: `scripts/lib/utilidade.cjs`, `hooks/memoria-assunto-prompt.cjs`, `scripts/testa-utilidade-cache.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-utilidade-cache.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (cache && cache.has(chave)) return cache.get(chave);`
  para: `if (false) return cache.get(chave);`
  bateria: `node scripts/testa-utilidade-cache.cjs`
  fixture: `testa-utilidade-cache.cjs, caso "14 linhas do mesmo dia com cache fazem no maximo 3 consultas LIKE em observacoes"`
pronto quando: com um banco criado pelo `criarSchema` REAL, 14 observações do mesmo dia e as 14 linhas que `formatarObservacao` real produz para elas (misturando as três formas de linha e ao menos um resumo), `acharAlvo` chamado nas 14 com um mesmo `new Map()` como 4º argumento faz no máximo 3 `prepare` de SQL que contenha `FROM observacoes WHERE criada_em LIKE` (contados por wrapper em `conexao.prepare`; sem cache são 42), e devolve para cada linha alvo idêntico (deepStrictEqual) ao da chamada sem cache — provado por `node scripts/testa-utilidade-cache.cjs` saindo 0 com `0 falha(s)`; e com o banco real do host (`~/.rainforest/rainforest.db`, só leitura) e o transcrito real mais recente do projeto, a semeadura do hook (`memoria-assunto-prompt.cjs` com `RFM_ROOT` numa cópia temporária, 1º pedido da sessão) cai de ~1500 ms para menos de 600 ms, medição antes/depois colada no relato.

Forma prescrita (código a nascer): a busca das candidatas de um dia vira uma função própria; o cache é um `Map` criado por quem chama e chaveado pelo `like` do dia (e pela tabela), e o reaproveitamento é a linha exata `if (cache && cache.has(chave)) return cache.get(chave);`. Os dois chamadores (`memoriaDoPedido` no hook e `pontuarSessao` em `utilidade.cjs`) criam um `Map` antes do laço e o passam. Nenhum caso de teste lê o texto do fonte.

### 2. Timeout 10 s e bateria do hook com teto do hooks.json [tipo: implementar]
atende: D2, D3, D4
arquivos: `hooks/hooks.json`, `hooks/testa-memoria-assunto-prompt.cjs`
depende de: nenhuma
paralela: sim
prova-na-base: verde — o caso de #507 só fica vermelho em runner lento; na máquina local a base passa, e o teto lido do hooks.json não existe antes da tarefa
mutacao: n/a
  motivo: troca de limite de tempo; inverter (voltar a 1500 ms) só fica vermelho em runner lento, não de forma reproduzível. A falsificação é o critério abaixo, que confere o valor lido do hooks.json real e a ausência de `async` na entrada.
pronto quando: com o `hooks/hooks.json` real, a entrada de `UserPromptSubmit` cujo `command` cita `memoria-assunto-prompt.cjs` tem `timeout` 10 e não tem `async` — provado por `node -e "const h=require('./hooks/hooks.json');const e=h.hooks.UserPromptSubmit.flatMap(x=>x.hooks).find(x=>x.command.includes('memoria-assunto-prompt.cjs'));console.log(e.timeout,e.async===undefined)"` devolvendo `10 true`; e o caso "pedido sem acerto grava o arquivo da sessao e o segundo nao rele o transcrito" de `hooks/testa-memoria-assunto-prompt.cjs` compara `d1` com esse timeout lido do hooks.json (em ms), não com 1500 — provado por `node hooks/testa-memoria-assunto-prompt.cjs` saindo 0 com `0 falha(s)`, e por essa bateria ficar VERMELHA quando o `timeout` do hook no hooks.json é trocado à mão para `0.001`.

### 3. Versão PATCH, CHANGELOG e README [tipo: docs]
atende: D1, D2, D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto e número de versão; não há comportamento a inverter
pronto quando: com o diff real das tarefas 1 e 2, a versão sobe de 1.64.0 para 1.64.1 nos dois `plugin.json`, a entrada do CHANGELOG cita #509 e #507 com os números medidos (1º pedido ~1500 ms antes, valor medido depois; 42 → no máximo 3 consultas; timeout 5 → 10 s) coerentes com o design, e o README só muda onde ele cita o timeout ou o custo do hook — provado por `node scripts/conferir-versao.cjs` saindo 0.
