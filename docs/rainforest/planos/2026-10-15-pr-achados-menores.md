# Plano: Painel de PR e plugins-em-dia: achados menores (#466)

Design: docs/rainforest/design/2026-10-15-pr-achados-menores.md

## O que não pode quebrar
- `node hooks/testa-mod-pr.cjs` e `node hooks/testa-mod-plugins-em-dia.cjs` seguem verdes.
- Merge que a própria sessão pediu (`mergePedido`) continua sem nota nem despertar.
- PR de outro autor ou de fork continua sem acordar a sessão.

## Tarefas

### 1. Decisões do painel de PR em funções puras testadas [tipo: implementar]
atende: D1, D3, D4, D5
arquivos: `hooks/pr-puro.mjs`, `hooks/pr.tsx`, `hooks/testa-mod-pr.cjs`, `hooks/mod-pr.test.tsx`
depende de: nenhuma
prova-na-base: verde — as funções puras novas só passam a existir nesta tarefa
mutacao:
  arquivo: `hooks/pr-puro.mjs`
  de: if (eu === '') return 'adiar';
  para: if (false) return 'adiar';
  bateria: `node hooks/testa-mod-pr.cjs`
  fixture: testa-mod-pr.cjs, caso "dono: login desconhecido adia, nao rebaixa"
pronto quando: com a fixture `REAL_PR` (saída real do `gh pr view` com os `CAMPOS` do mod), (a) `pendenteDaVirada({ virada: 'merged', mergePedido: false, daSessao: true, resumo, agoraMs })` devolve `{ virada: 'merged', nota, ultimaMudancaMs: agoraMs }` com a nota de merge de PR da sessão, e com `mergePedido: true` devolve `null`; virada `null` devolve `null`; (b) `planoDoDespertar({ pendente, acompanhado, agoraMs })` devolve `{ limpar: true, enviar: <nota> }` quando o PR é da sessão e está quieto, e `{ limpar: false, enviar: null }` quando não deve acordar — o `pr.tsx` limpa o `prPendente` antes de enviar, na ordem que a função devolve; (c) `consultaVelha(alvoConsultado, acompanhadoAgora)` é `true` para `acompanhadoAgora` `null` ou com outro `alvo`, e `false` para o mesmo alvo; no `pr.tsx`, depois do `gh pr view`, consulta velha sai sem gravar `prAcompanhado`, `prResumo` nem eventos, checado depois do `gh pr view`, no rebaixamento e na troca do `alvo` e depois da leitura das threads (emenda D3) — e `claude plugin test .` passa o caso "troca de PR durante a leitura das threads descarta a consulta velha", que fica vermelho sem a checagem depois das threads; (d) `decidirDono({ autor, eu, cruzado })` devolve `'adiar'` com `eu === ''` (nem rebaixa nem acorda nesta consulta), `'rebaixar'` com login conhecido e dono que não confere ou fork, e `'manter'` quando confere; no `pr.tsx`, só `'rebaixar'` grava `origem: 'manual'`, e `'adiar'` impede o despertar só nesta consulta; (e) `REAL_PR` do `testa-mod-pr.cjs` e a fixture do `mod-pr.test.tsx` têm os mesmos nomes de campo de topo — provado por `node hooks/testa-mod-pr.cjs` com zero falha, com casos novos para (a)–(e), entre eles "dono: login desconhecido adia, nao rebaixa", e nenhum caso lendo o texto do fonte.

Forma do código: as quatro funções em `hooks/pr-puro.mjs`, cada uma sem efeito colateral; `decidirDono` começa pela linha exata `if (eu === '') return 'adiar';` e usa o `donoConfere` existente para o resto. O `pr.tsx` troca a lógica inline pelas chamadas, sem mudar o resto do fluxo de consulta.

### 2. Risco aceito, design antigo emendado, CHANGELOG e versão [tipo: docs]
atende: D2, D6
arquivos: `docs/rainforest/design/2026-10-09-mods-pr-e-plugins.md`, `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: documentação, nota de emenda e número de versão; não há comportamento a inverter
pronto quando: com a tarefa 1 no repo, (a) a D9 e a D10 de `docs/rainforest/design/2026-10-09-mods-pr-e-plugins.md` ganham uma nota de emenda datada 2026-10-15 que diz o entregue (padrão só `rainforest-mind`; versão 1.55.0), sem apagar o texto original; (b) a entrada nova do CHANGELOG (PATCH sobre a versão da `origin/main` no despacho) descreve D1, D3, D4 e D5 sem prometer mais do que o código faz, e diz que a corrida do `plugins-em-dia` (D2) ficou aceita; (c) as duas `plugin.json` e o selo do README batem; (d) o comentário de aceitação do D2 na #466 é postado no `fechar`, junto da evidência — provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando o texto com D1–D6.
