# Plano: Painel Deixado oferece virar pendência do fluxo (#470)

Design: docs/rainforest/design/2026-10-15-deixado-vira-pendencia.md

## O que não pode quebrar
- `bash scripts/testa-estado.sh`, `node hooks/testa-mod-deixado.cjs` e `node hooks/testa-mod-painel.cjs` seguem verdes.
- O mod continua sem escrita em disco: `grep -cE '\$\.fs|\$\.store' hooks/mod.tsx` devolve 0.
- A trava da #449 não muda: `marcar ... ok` de um estágio com pendência sem destino recusa, e `destinar` tira a pendência.

## Tarefas

### 1. Subcomando `estado.cjs pendencia` [tipo: implementar]
atende: D2, D3
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-pendencia.sh`, `scripts/baterias-obrigatorias.txt`
depende de: nenhuma
prova: `bash scripts/testa-estado-pendencia.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: if (!lista.includes(texto)) lista.push(texto);
  para: lista.push(texto);
  bateria: `bash scripts/testa-estado-pendencia.sh`
  fixture: testa-estado-pendencia.sh, caso "texto repetido nao duplica"
pronto quando: com um estado real numa caixa (`RFM_ESTADO_ROOT` em mktemp; `iniciar`, design aprovado, plano ok, `executar` parcial), (a) `node scripts/estado.cjs pendencia --slug <s> --texto "rodar a bateria X"` sai 0 e o bloco `executar` ganha `pendentes: ["rodar a bateria X"]` com `status` ainda `parcial` e os demais campos iguais; (b) repetir o mesmo comando sai 0 e a lista continua com um item; (c) `--texto ""` (ou sem `--texto`) sai 1 e o arquivo de estado fica com o mesmo hash; (d) `marcar --estagio executar --status ok` (com o resto do `--json` válido) recusa com exit 2 citando a pendência, e depois de `destinar` com destino `descartada` + motivo ele passa a não recusar por ela; (e) num fluxo completo (todos os estágios fechados) `pendencia` sai 2 sem escrever; (f) com o estágio aberto sendo `design` (fluxo recém-iniciado), a pendência entra no bloco `design` — provado por `bash scripts/testa-estado-pendencia.sh` com zero falha e listada uma vez em `scripts/baterias-obrigatorias.txt`.

Forma do código: um bloco `if (cmd === 'pendencia')` ao lado do `destinar`, com `pendencia` no mapa de argumentos obrigatórios (`slug`, `texto`); o estágio é o que `proximo(estado)` devolve (sem estágio: exit 2); grava pela mesma escrita atômica que os outros comandos usam, só mexendo em `pendentes` do bloco, com a linha exata `if (!lista.includes(texto)) lista.push(texto);`. Uso (`uso:` do fim do arquivo) cita o subcomando. Nenhum caso de teste lê o texto do fonte.

### 2. Botão "Vira pendência de <fluxo>" no painel [tipo: implementar]
atende: D4
arquivos: `hooks/deixado-puro.mjs`, `hooks/mod.tsx`, `hooks/testa-mod-deixado.cjs`
depende de: 1
prova-na-base: verde — a função pura nova só passa a existir nesta tarefa
mutacao:
  arquivo: `hooks/deixado-puro.mjs`
  de: --texto ${aspas(texto)}
  para: --texto ${texto}
  bateria: `node hooks/testa-mod-deixado.cjs`
  fixture: testa-mod-deixado.cjs, caso "rascunhoViraPendencia: texto com aspas e espaco chega literal ao bash"
pronto quando: (a) `rascunhoViraPendencia(slug, texto)` em `hooks/deixado-puro.mjs` devolve um rascunho que contém o comando `node scripts/estado.cjs pendencia --slug <slug> --texto <texto entre aspas simples>`; com o texto `rodar "a" bateria de $HOME e it's`, extrair o argumento e rodá-lo por `bash -c 'printf %s <arg>'` devolve o texto literal (sem expansão de `$HOME`, com as aspas); (b) no `hooks/mod.tsx`, cada item aberto do painel "Deixado para depois" ganha um `Button` com rótulo `Vira pendência de <slug sem data>` por fluxo de `dados.fluxos`, cujo `onPress` faz `$.prompt.fill` em modo `append` com `rascunhoViraPendencia` e, preenchido, marca o item `enviado`; sem fluxo (lista vazia ou `dados === null`) não há botão; (c) `grep -cE '\$\.fs|\$\.store' hooks/mod.tsx` devolve 0 — provado por `node hooks/testa-mod-deixado.cjs` e `node hooks/testa-mod-painel.cjs` com zero falha e pela leitura do revisor no `mod.tsx`.

Forma do código: em `deixado-puro.mjs`, `aspas` envolve em aspas simples e troca cada `'` interna por `'\''` (uma expressão, sem ramo); `rascunhoViraPendencia` monta uma frase curta que pede para rodar o comando, com a linha exata contendo `--texto ${aspas(texto)}`, e o texto cortado em 500 caracteres. Nenhum caso lê o texto do fonte.

### 3. Docs e versão [tipo: docs]
atende: D1, D2, D3, D4
arquivos: `README.md`, `docs/travas-mecanicas.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2
mutacao: n/a
  motivo: documentação e número de versão; não há comportamento a inverter
pronto quando: com as tarefas 1 e 2 no repo, o README descreve o subcomando `pendencia` (onde lista os subcomandos do `estado.cjs`) e o botão novo do painel "Deixado para depois", dizendo que ele só preenche o prompt; a entrada nova do CHANGELOG (PATCH sobre a versão da `origin/main` no despacho) descreve D1–D4 sem prometer mais do que o código faz; as duas `plugin.json` e o selo do README batem — provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando o texto com D1–D4.
