# Plano: Pendência do fluxo só sai com destino (#449)

Design: docs/rainforest/design/2026-10-09-pendente-destino.md
Base: 8053ad4e (branch `fluxo/pendente-destino`). O working tree tem `docs/rainforest/estado/2026-10-09-pendente-destino.json` modificado e não commitado (o design passou a `aprovado`). É o estado deste fluxo e não conflita com nada do plano. `origin/main` está em 230ba888, versão 1.54.3, e a branch está um commit atrás (merge-base 6b67b096, os dois `plugin.json` do HEAD dizem 1.54.2). Versão alvo: 1.55.0 (MINOR: o contrato do `marcar` muda e nasce o verbo `deixado`). A tarefa 8 traz `origin/main` para a branch antes de subir o número.

Rótulos: CONFIRMADO = li o arquivo ou rodei o comando. INFERIDO = dedução minha, dita como tal. LACUNA = não sei, e digo o que falta.

## Achados que mudam o desenho

- **A1. A bateria `scripts/testa-estado.sh`, seções 13 e 14, codifica o contrário do D3.** CONFIRMADO por leitura (`scripts/testa-estado.sh:672-702`, `:727-750`) e por baseline: `bash scripts/testa-estado.sh` termina com `321 ok, 0 falhas`.
  - `t-pend` deixa `parcial` com `["tarefa-6: falta rodar"]` e fecha `ok` sem repetir `pendentes` nem trazer `destinos`. Sob D3 isso é exit 2. As asserções seguintes (`:676-686`) passariam a ler um arquivo ainda `parcial`.
  - `t-pend2` fecha `ok` com `"pendentes":["nota: revisado depois"]` e afirma que o campo **sobrevive** (`:700-702`, "intenção, não vazamento"). O D3 diz o contrário: com todas as pendências destinadas, `pendentes` some. Esse caso é a regra velha e precisa ser reescrito, não adaptado.
  - A seção 14 muta a linha de `baseParaFundir` (`sed` em `if (!(campo in extra)) delete base[campo];`) e espera que o `ok` grave. Sem `destinos` o `ok` passa a ser recusado, o bloco fica `parcial` com `pendentes` e a leitura devolve "sobreviveu" **pelo motivo errado**: o teste ficaria verde sem medir o conserto.
  - Decisão técnica: a tarefa 2 reescreve as seções 13 e 14. O `ok` delas ganha `destinos`, o caso `t-pend2` vira "recusa sem destino" mais "some com destino", e o placar sobe de 321 para 324 (+1 em `t-pend`, +2 em `t-pend2`).

- **A2. O D3 diz "`pendentes` some como hoje", mas hoje `pendentes` repetido no `--json` do `ok` sobrevive.** CONFIRMADO: `baseParaFundir` só apaga o campo que o `--json` novo **não** repete (`scripts/estado.cjs:208-210`), e o comentário de `CAMPOS_EFEMEROS` (`:176-190`) fala do bloco anterior, não do `extra`.
  - Decisão técnica: com todas as pendências destinadas, `pendentes` sai do bloco **mesmo quando veio no `--json` do `ok`**. O mecanismo é a conciliação apagar `extra.pendentes` antes da fusão (ver A4). Assim `baseParaFundir` e a mutação da seção 14 continuam valendo para o que já cobriam, e o D3 não precisa de segundo caminho de apagamento.

- **A3. "Terminal-positivo" tem dois predicados no arquivo, e eles divergem só em `arqueologia`.** CONFIRMADO: o fechamento por `status === (FECHADO[estagio] || 'ok')` (`:2296`, `:2314`) e `estaFechado` (`:163-170`), que `baseParaFundir` usa e que aceita também `dispensada` (`FECHA_TAMBEM`, `:155`).
  - Decisão técnica: o D3 usa `estaFechado(estagio, { status })`. É o predicado que decide hoje se `pendentes` é apagado em silêncio, e a trava tem de cobrir exatamente o que apagava. Consequência: `arqueologia dispensada` com pendência sem destino também é recusada (caso próprio na tarefa 2).

- **A4. A fusão do `marcar` é rasa e o D4 se resolve nela, sem segundo caminho.** CONFIRMADO: `blocoNovo = { ...baseAnterior, ...extra, status, em: hoje() }` (`scripts/estado.cjs:2459-2460`). `extra.destinos` substituiria `anterior.destinos`.
  - Decisão técnica: uma função pura `reconciliarPendencias(estagio, anterior, extra, status)` roda depois do bloco de carimbos (`:2263-2271`) e antes de qualquer gate que dispara processo. Ela devolve a recusa ou o aviso e **reescreve `extra.destinos` e `extra.pendentes`** com o resultado acumulado. A linha da fusão fica como está.
  - `destinos` **não** entra em `CAMPOS_EFEMEROS` (D4). O comentário de `:176-190` ganha duas linhas dizendo isso, para o próximo leitor não "completar" a lista.
  - `veredito` e `liberar` espalham o bloco inteiro (`:1991`, `:2154`, `:2162`), então preservam `destinos` sem mudança. CONFIRMADO por leitura.

- **A5. Como `parcial` mantém a pendência omitida (D5).** Decisão técnica, já no sentido do design:
  - Universo de pendências do bloco = `anterior.pendentes` (na ordem em que estavam) seguido das novas que ainda não estavam, sem duplicata. Comparação por **texto exato**.
  - `pendentes` gravado em status não terminal = universo menos as que têm destino (nos `destinos` acumulados). Só um destino tira da lista.
  - O aviso em stderr sai quando o `--json` **traz** a chave `pendentes` e deixa de fora uma pendência anterior sem destino. `--json` sem a chave `pendentes` mantém o bloco e não avisa, porque nada foi "omitido".
  - Vale para todo status não terminal: `parcial`, `reprovado` e `pendente`. `reprovado` não exige destino (só o terminal exige).
  - Consequência assumida (INFERIDO, reversível): como o casamento é por texto exato, **reescrever** o texto de uma pendência deixa a antiga órfã até alguém destiná-la (por exemplo `descartada`, motivo "reescrita"). É o preço de manter `pendentes` como strings (D1).

- **A6. Universo de casamento do `pendente` de um destino (D2).** Decisão técnica: o `pendente` tem de ser igual a uma pendência do universo da A5 **ou** a um `pendente` que já tenha destino gravado. Sem a segunda metade, o D4 ("o destino mais novo substitui o antigo") seria impossível: a pendência já destinada saiu da lista `pendentes` e o novo destino dela seria recusado como "não casa".

- **A7. Regex do `ref` de `plantada` (D2).** Três formas, todas ancoradas (`^...$`), sem espaço nas pontas:
  - `#<n>` com `n` inteiro positivo: `/^#[1-9][0-9]*$/`.
  - URL: `/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/[1-9][0-9]*$/`. Sem fragmento, sem barra final, sem `/pull/`: o design pede URL **de issue**.
  - `ideia:<id>` com a forma de `RE_ID` de `scripts/ideias.cjs:101` (`^[a-z0-9]+(?:-[a-z0-9]+)*$`). CONFIRMADO que `ideias.cjs` não exporta nada, então o padrão é copiado com um comentário apontando a linha, em vez de `require` (que executaria o módulo).
  - Se um dia a URL precisar aceitar `#issuecomment-...`, é uma linha na segunda regex. Hoje a trava prefere recusar a mais.

- **A8. Ponto natural da checagem do `exigir --estagio fechar` (D6).** CONFIRMADO: dentro do ramo `if (!falta.length) {` (`scripts/estado.cjs:2080`), antes do `console.log('ok: pre-requisitos ...')` (`:2081`).
  - Só chega ali quem já passou pela recusa por pré-requisito aberto, então as duas mensagens não se misturam.
  - A varredura percorre uma lista fixa dos sete estágios (`arqueologia, design, plano, executar, revisar, verificar, fechar`), **não** toda chave com `pendentes`. Motivo CONFIRMADO: `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json` tem a chave `revisar_historico_1_23_0` com status `reprovado` e `pendentes`, que não é estágio.
  - `pendentes: []` não bloqueia.

- **A9. Os 12 arquivos de estado antigos com `pendentes` não migram (D1) e nenhum está aberto.** CONFIRMADO por varredura somente-leitura: todos têm `fechar: ok`. Seis têm pendência não vazia num bloco `ok` (cinco arquivos com um bloco, e `vigias.json` com dois: `executar` e `verificar`). Os outros seis têm `[]` ou só a chave histórica. Efeito: `deixado` neles mostra `(sem destino)` e `exigir --estagio fechar` neles recusaria, mas fluxo fechado não passa por `exigir fechar` de novo.

- **A10. Quem mais grava `pendentes` (a pergunta do briefing).** CONFIRMADO por `grep` em `skills/`, `agents/`, `commands/`, `hooks/`, `scripts/`: nenhuma skill, agente ou hook grava `pendentes` por código. O único que **instrui** a gravar é `skills/executar/SKILL.md:305` (o orquestrador escreve `pendentes` no `--json` do `parcial`), e o único código que grava é `scripts/testa-estado.sh`. Logo só o `executar` precisa passar a falar de `destinos`, e a tarefa 6 cuida disso. `revisar`, `verificar` e `plano` não mencionam `pendentes`.

- **A11. Entrada fora de forma é fronteira de confiança e não pode virar desvio.** Decisão técnica: `pendentes` que não é lista de textos, e `destinos` que não é lista de objetos, são recusados com exit 2 em qualquer status. Sem isso, `"pendentes":"texto"` escaparia da conciliação inteira e fecharia `ok` como hoje. Hoje nenhum chamador conhecido passa outra coisa (A10).

- **A12. A bateria nova é um `.cjs` próprio, `scripts/testa-pendente-destino.cjs`.** Decisão técnica, por três razões:
  - `testa-estado.sh` já tem 321 casos e monta a caixa copiando as libs. A nova roda o `estado.cjs` **do repositório** numa caixa `mkdtemp`.
  - O `--json` com aspas e acento atravessa o `bash` com risco (nota "contrabarra some em heredoc"). Com `spawnSync` e vetor de argumentos o texto chega intacto.
  - A mutação é feita pela catraca (`conferir-mutacao.cjs`, no fonte de produção dentro do clone), não por `sed` dentro do caso.
  - CONFIRMADO por experimento numa pasta do scratchpad: com `RFM_ESTADO_ROOT` e `RFM_ROOT` apontando para a caixa, `CI=1` (pula a trava de checkout), `CLAUDE_PROJECT_DIR` e `CLAUDE_CODE_SESSION_ID` limpos e cwd na caixa (não é repositório), a sequência `iniciar`, `marcar design aprovado`, `marcar plano ok`, `exigir executar`, `marcar executar parcial --json '{"pendentes":["a","b"]}'`, `marcar executar ok --json '{"comando":"c","saida":"s","mutacao":[{"tarefa":1,"resultado":"n/a","motivo":"m"}]}'` sai 0 em todos os passos. **Baseline do defeito:** o `ok` final sai 0 e o bloco `executar` fica sem `pendentes`: a pendência `["a","b"]` sumiu sem destino. A caixa só ganhou `FOCO.md` e `docs/`.

- **A13. Registro da bateria.** CONFIRMADO: `bash scripts/varrer-baterias.sh --listar` lista 216 baterias hoje. A nova será a 217ª, descoberta pelo glob `scripts/testa-*.cjs`. `scripts/baterias-obrigatorias.txt` tem a seção "Conferencias" com `scripts/testa-estado.sh`, e a nova entra ao lado porque é trava de contrato. `scripts/tempos-baterias.json` é opcional (bateria sem peso entra com a mediana, `scripts/repartir-baterias.cjs`), mas o plano adiciona o tempo medido para o shard ficar equilibrado.

- **A14. A versão do HEAD já está atrás da `origin/main`.** CONFIRMADO: `node scripts/conferir-versao.cjs` sai 2 com "versao declarada 1.54.2 nao e' maior que a de origin/main (1.54.3)". Depois de `git fetch origin`, `git show origin/main:.claude-plugin/plugin.json` e o `.codex-plugin` dizem 1.54.3. 1.55.0 está livre.

## Decisões do usuário

Nenhuma pendente: o design fechou Q1 e Q2. Há duas escolhas de borda que assumi por serem reversíveis em uma linha, e que ele pode inverter:

- **U1. A URL de issue não aceita fragmento nem `/pull/` (A7).** Recomendado: manter estrito. Alternativa: aceitar `#issuecomment-<n>` na segunda regex.
- **U2. `deixado` mostra pendência órfã como `(sem destino)` e sai 0 (tarefa 5).** Recomendado: o gate é o `exigir`, o `deixado` só informa. Alternativa: sair 2 quando houver órfã.

## Fatos apurados

- HEAD 8053ad4e. Placares da base, todos `0 falha(s)`, rodados por mim:
  - `bash scripts/testa-estado.sh`: 321 ok.
  - `bash scripts/testa-estado-leve.sh`: `ok: 74`.
  - `bash scripts/testa-estado-principal.sh`: 26 ok.
  - `bash scripts/testa-estado-territorio.sh`: `total=9 vermelhas:[]`.
  - `bash scripts/testa-conferir-invariantes.sh`: `ok: 32`.
  - `bash scripts/testa-fechar-destino.sh`: `ok: 32`.
  - `bash scripts/testa-versao.sh`: `ok: 5   falhou: 0`.
  - `node hooks/testa-portaria-manifesto.cjs`: 62 ok (lê `skills/executar/SKILL.md`).
  - `node scripts/conferir-invariantes.cjs`: `ok: conferidas 19 invariantes`.
  - `node scripts/conferir-categoria.cjs`: "CONFERIDO".
- `scripts/estado.cjs`:
  - `CAMPOS_EFEMEROS` `:190`; `baseParaFundir` `:204-212`; `estaFechado` `:163`; `FECHA_TAMBEM` `:155`.
  - `FLAGS_POR_SUBCOMANDO` `:1599-1610`; despacho de `ler` `:2003`, `proximo` `:2008`; `exigir` `:2021`, ramo `!falta.length` `:2080`.
  - `marcar`: parse do `--json` `:2225-2262`; carimbos `:2263-2271`; D28 `:2273`; fusão `:2459-2460`; gravação `:2498`; linha `uso:` `:2507`; cabeçalho de uso `:27-36`.
  - O `iniciar` é recusado fora de `CI` quando o checkout principal não está na branch padrão (`checkoutPrincipalForaDaPadrao`, `:1365`). `CI=1` o desliga (`:1373`).
- `skills/fechar/SKILL.md`:
  - "três seções, nesta ordem" em `:98`; o modelo do corpo do PR em `:101-112`.
  - `testa-fechar-destino.sh` extrai os exemplos da região entre "O GitHub reconhece" e a primeira linha em branco (`:98` do script) e exige exatamente 3. O texto novo fica **fora** dessa região.
- `skills/executar/SKILL.md`, "Condição de parada" em `:302-307`.
- Repositório público: nada de nome real de cliente ou pessoa em fixture, texto ou exemplo. Os exemplos usam `alfa`, `beta`, `omega`.

## O que não pode quebrar

- **`veredito`, `liberar`, `exigir` e `proximo` não mudam de comportamento para fluxo sem pendência.**
- **Fluxo sem nenhuma pendência não ganha campo novo.** O bloco não recebe `pendentes: []` nem `destinos: []` quando nenhum dos dois existia.
- **`--json` continua aceitando metadado arbitrário** (invariante do plano `decisao-que-evapora-na-esteira`, citado em `scripts/estado.cjs:182-186`). Só `pendentes` e `destinos` têm forma validada.
- **Recusa não grava.** Todo exit 2 novo acontece antes de `gravar`: o arquivo de estado fica byte a byte igual.
- **Nenhuma bateria toca `~/.rainforest`.** A nova usa `mkdtemp`, `RFM_ESTADO_ROOT` e `RFM_ROOT` na caixa.
- **Sem regressão de placar**, salvo o que a tarefa 2 reescreve de propósito: `testa-estado-leve.sh` 74, `testa-estado-principal.sh` 26, `testa-estado-territorio.sh` 9, `testa-conferir-invariantes.sh` 32, `testa-fechar-destino.sh` 32, `testa-portaria-manifesto.cjs` 62.
- **`node scripts/conferir-categoria.cjs` segue "CONFERIDO"** (a bateria nova é `testa-*`, isenta de `@categoria`).

## Tarefas

### 1. Validar `destinos` no `marcar` [tipo: implementar]
atende: D1, D2
arquivos: `scripts/estado.cjs`, `scripts/testa-pendente-destino.cjs`
depende de: nenhuma
paralela: nao
prova: `node scripts/testa-pendente-destino.cjs`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const valido = d.destino === 'plantada' ? REF_PLANTADA.some((re) => re.test(valor)) : valor !== '';`
  para: `const valido = valor !== '';`
  bateria: `node scripts/testa-pendente-destino.cjs`
  fixture: `testa-pendente-destino.cjs, caso "plantada com ref que nao e issue nem ideia e recusada"`
pronto quando: com o `estado.cjs` real numa caixa `mkdtemp` (A12), um `marcar` cujo `--json` traz `destinos` mal formados sai com exit 2 sem gravar, e os bem formados saem 0 e ficam no bloco — provado por `node scripts/testa-pendente-destino.cjs` imprimindo `25 ok, 0 falha(s)`.
  - **Bateria nova.** Auxiliares:
    - `caixa()` cria o `mkdtemp` (com `realpath`), grava `FOCO.md` e devolve o ambiente (`RFM_ESTADO_ROOT`, `RFM_ROOT`, `HOME` e `USERPROFILE` na caixa, `CI=1`, sem `CLAUDE_PROJECT_DIR` nem `CLAUDE_CODE_SESSION_ID`).
    - `estado(caixa, args)` roda `process.execPath scripts/estado.cjs` com `spawnSync`, `cwd` na caixa, e devolve `{status, stdout, stderr}`.
    - `abrir(caixa, slug)` faz `iniciar`, `design aprovado`, `plano ok` e `exigir --estagio executar` (arma a catraca).
    - Cada `caso` tem nome, e a bateria sai com o placar `N ok, M falha(s)` no fim, como `scripts/testa-esquema-ocupado.cjs`. A caixa é apagada no fim.
  - **Pendências de teste** (texto fixo, sem nome real): `A = "tarefa-3: worktree nao respondeu"`, `B = "tarefa-6: falta rodar"`.
  - **Recusas (19 casos, todos via `marcar --estagio executar --status parcial --json '{"pendentes":[A,B],"destinos":[...]}'`, exit 2, estado byte a byte igual ao de antes, stderr nomeando o campo que falta):**
    1. `resolvida` sem `evidencia`.
    2. `resolvida` com `evidencia` só de espaços.
    3. `descartada` sem `motivo`.
    4. `plantada` sem `ref`.
    5. `plantada` com `ref` `qualquer coisa` (o caso da mutação).
    6. a 13. `plantada` com cada um destes `ref`, um caso por valor: `#0`, `#abc`, `#12 x`, `https://github.com/alfa/beta/pull/3`, `https://github.com/alfa/beta/issues/`, `http://github.com/alfa/beta/issues/3`, `ideia:Maiusculo`, `ideia:a--b`.
    14. `destino` fora dos três (`adiada`); o stderr cita `adiada`.
    15. item sem o campo `destino`.
    16. `pendente` que não casa com nenhuma pendência (stderr cita o texto recebido).
    17. `destinos` é objeto, não lista.
    18. `pendentes` é texto, não lista (A11).
    19. `pendentes` com um item que é número (A11).
  - **Aceitos (6 casos, exit 0):**
    20. `plantada` com `#449`.
    21. `plantada` com `https://github.com/alfa/beta/issues/449`.
    22. `plantada` com `ideia:regua-d7-memoria-por-assunto`.
    23. `resolvida` com `evidencia` não vazia.
    24. `descartada` com `motivo` não vazio.
    25. depois do 23, o bloco `executar` do arquivo tem `destinos` com 1 item igual ao enviado. Não se afirma nada sobre `pendentes`: a tarefa 3 muda o que `parcial` grava nesse campo.
  - **Na base:** por leitura (INFERIDO), os 19 casos de recusa saem 0, porque `destinos` é metadado arbitrário e `--json` é fundido cru. Os 6 aceitos passam.
  - **Também nesta tarefa** (casos 17 a 19): a forma de `pendentes` (lista de textos) e de `destinos` (lista de objetos) é conferida antes do resto, em qualquer status (A11).
  - Forma do alvo de mutação (código a nascer):
    - `reconciliarPendencias(estagio, anterior, extra, status)` é função pura de `scripts/estado.cjs`, chamada em `marcar` logo depois do bloco de carimbos (`:2263-2271`). Nesta tarefa ela só valida e devolve `{ recusa }`; o `marcar` imprime a recusa e sai 2.
    - Dentro dela, `validarDestino(d, universo)` calcula `valor` (o campo certo de cada `destino`: `evidencia`, `ref` ou `motivo`, aparado, vazio se não for texto). A linha do `de:` é a única que decide a validade.
    - `REF_PLANTADA` é uma lista de três regex (A7), e o texto `const valido = ...` aparece uma vez no arquivo.
    - `universo` = pendências do bloco anterior, as novas do `--json` e os `pendente` dos destinos já gravados (A6).
    - Nenhum caso lê o texto do fonte.

### 2. `ok` só fecha com destino, e `destinos` acumula [tipo: implementar]
atende: D3, D4
arquivos: `scripts/estado.cjs`, `scripts/testa-pendente-destino.cjs`, `scripts/testa-estado.sh`
depende de: 1
paralela: nao
prova: `node scripts/testa-pendente-destino.cjs`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const faltam = terminal ? semDestino(uniao, acum) : [];`
  para: `const faltam = [];`
  bateria: `node scripts/testa-pendente-destino.cjs`
  fixture: `testa-pendente-destino.cjs, caso "ok com pendencia sem destino e recusado em vez de apagar em silencio"`
pronto quando: um `marcar` terminal-positivo com pendência sem destino sai 2 listando as que faltam, com todas destinadas sai 0 e o bloco fica sem `pendentes` e com `destinos`, e o `destinos` acumula entre chamadas — provado por `node scripts/testa-pendente-destino.cjs` com `34 ok, 0 falha(s)` e por `bash scripts/testa-estado.sh` com `324 ok, 0 falhas`.
  - **9 casos novos na bateria.** A base é o mesmo `abrir` da tarefa 1. Salvo onde dito, A e B vêm de um `parcial` anterior e o `ok` **não** repete `pendentes`. O `ok` leva `{"comando":"c","saida":"s","mutacao":[{"tarefa":1,"resultado":"n/a","motivo":"m"}]}` mais o que o caso pede.
    1. `ok` depois de um `parcial` com [A,B], sem `destinos`: exit 2, stderr lista A e B, estado byte a byte igual (continua `parcial`). **É o caso da mutação.**
    2. `ok` depois de um `parcial` com [A,B], com destino só para A: exit 2, stderr lista B e **não** cita A.
    3. `ok` com `pendentes` [A,B] e `destinos` para os dois no mesmo `--json`: exit 0. O bloco `executar` não tem `pendentes`, tem `destinos` com 2 itens e mantém `catraca_mutacao`.
    4. `parcial` com [A,B], depois `ok` sem repetir `pendentes` e com `destinos` para os dois: exit 0, sem `pendentes`, 2 `destinos`.
    5. dois `parcial` seguidos, o primeiro com [A,B] e destino de A, o segundo só com destino de B: o bloco tem 2 `destinos` (a fusão rasa não perdeu o de A). O `ok` seguinte sai 0.
    6. o destino mais novo substitui o antigo: A `descartada` e, em outro `parcial`, A `resolvida`. O bloco tem 1 destino para A e é o `resolvida`.
    7. `ok` sem pendência nenhuma: exit 0, o bloco não ganha `pendentes` nem `destinos`.
    8. `marcar design aprovado --json '{"pendentes":[A]}'` sem destino: exit 2 (a regra vale em qualquer estágio).
    9. `marcar arqueologia dispensada --json '{"pendentes":[A]}'` sem destino: exit 2 (A3).
  - **Na base** (CONFIRMADO por experimento na caixa do A12): os casos 8 e 9 saem **0** e gravam o bloco com a pendência. O caso 1 sai 0 e o `ok` apaga A e B sem rastro.
  - **Reescrita em `scripts/testa-estado.sh`** (A1, A2), sem mexer em mais nada:
    - Seção 13, `t-pend`: o `ok` (`:673-674`) ganha `"destinos":[{"pendente":"tarefa-6: falta rodar","destino":"resolvida","evidencia":"rodou: 6 de 6 ok"}]`. Acrescenta `igual "destinos do ok sobrevive ao fechamento" "1" ...` (+1).
    - Seção 13, `t-pend2` (`:689-702`):
      - O `ok` com `"pendentes":["nota: revisado depois"]` sem destino vira `esperado "ok com pendentes explicito e sem destino e recusado" 2 ...` (+1).
      - Em seguida o mesmo `ok` com `destinos` para `tarefa-2: falta` e `nota: revisado depois` sai 0, e duas `igual`: `pendentes` some mesmo vindo no `--json`, e `destinos` fica com 2 itens (+2, menos a asserção velha: líquido +2).
      - O comentário `:689-691` é reescrito.
    - Seção 14 (`:727-750`): o `ok` do mutante ganha o mesmo `destinos`, para a recusa do D3 não fazer a seção medir outra coisa. Contagem igual.
  - **Código:** `reconciliarPendencias` ganha, depois da validação:
    - o universo de pendências (A5);
    - `acum` (destinos do bloco anterior mais os do `--json`, o mais novo por `pendente`);
    - `terminal = estaFechado(estagio, { status })`;
    - `uniao` (anterior e novas, sem duplicata);
    - `semDestino(pendentes, destinos)`.

    Se `faltam` não é vazio, devolve `{ recusa }` com `RECUSADO: '<estagio>' nao fecha '<status>' com pendencia sem destino (<n>):`, uma linha `  - <texto>` por pendência e a forma esperada do `destinos`. Se é vazio, reescreve `extra.destinos = acum` (quando `acum` não é vazio) e, no terminal, apaga `extra.pendentes` (A2, A4). Em status não terminal esta tarefa **não** mexe em `extra.pendentes` (a tarefa 3 faz). O comentário de `CAMPOS_EFEMEROS` (`:176-190`) ganha a nota de que `destinos` não é efêmero.
  - **Sem regressão:** `bash scripts/testa-estado-leve.sh` (`ok: 74`), `bash scripts/testa-estado-principal.sh` (26), `bash scripts/testa-estado-territorio.sh` (`total=9 vermelhas:[]`).
  - Forma do alvo de mutação (código a nascer): `semDestino(pendentes, destinos)` é `pendentes.filter` dos textos que não aparecem em `destinos[].pendente`. A linha do `de:` é a única que decide a recusa, e o texto aparece uma vez no arquivo (a tarefa 3 usa `uniao` e `acum` em outra linha). Nenhum caso lê o texto do fonte.

### 3. `parcial` que omite pendência avisa e a mantém [tipo: implementar]
atende: D5
arquivos: `scripts/estado.cjs`, `scripts/testa-pendente-destino.cjs`
depende de: 2
paralela: nao
prova: `node scripts/testa-pendente-destino.cjs`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const persistem = semDestino(uniao, acum);`
  para: `const persistem = pendNovas === null ? semDestino(uniao, acum) : semDestino(pendNovas, acum);`
  bateria: `node scripts/testa-pendente-destino.cjs`
  fixture: `testa-pendente-destino.cjs, caso "parcial que omite a pendencia anterior continua com ela em pendentes"`
pronto quando: um status não terminal grava `pendentes` como a união com a anterior menos as destinadas, e avisa em stderr a pendência que ficou fora do `--json` — provado por `node scripts/testa-pendente-destino.cjs` com `41 ok, 0 falha(s)`.
  - **7 casos novos** (dois `parcial` seguidos na mesma caixa, salvo onde dito):
    1. `parcial` com [A,B], depois `parcial` com [B]: exit 0. O stderr cita o texto de A e **não** o de B. O bloco tem `pendentes` = [A,B]. **É o caso da mutação.**
    2. `parcial` com [A,B], depois `parcial` com [B] e destino para A: sem aviso (stderr não cita A) e `pendentes` = [B].
    3. `parcial` com [A,B], depois `parcial` com [B,C]: sem aviso. `pendentes` = [A,B,C], nessa ordem.
    4. `parcial` com [A,B], depois `parcial` com `{"tarefas_ok":1}` (sem a chave `pendentes`): sem aviso. `pendentes` continua [A,B].
    5. a omitida volta a barrar: `parcial` [A,B], `parcial` [B], `ok` com destino só para B: exit 2, o stderr lista A.
    6. `reprovado` com [A,B] já gravadas e `--json '{}'`: exit 0 (só o terminal exige destino) e `pendentes` continua [A,B]. CONFIRMADO que na base já é assim (exit 0, `pendentes` no bloco). O caso guarda que a tarefa não estrague isso.
    7. `parcial` com [A,B] e destino para os dois: `pendentes` = `[]` e `destinos` com 2 itens.
  - **Código:** em `reconciliarPendencias`, `pendNovas` é `null` quando o `--json` não traz `pendentes` e a lista caso contrário. `persistem` é o universo menos os destinados (A5). Em status não terminal, se o bloco anterior tinha `pendentes` ou o `--json` traz a chave, `extra.pendentes = persistem`. Fora disso o bloco não ganha o campo (fluxo sem pendência não muda). O aviso é `aviso: '<estagio>': pendencia(s) anterior(es) sem destino ficou(aram) fora do --json e continua(m) pendente(s):` seguido de uma linha `  - <texto>` por omitida. Exit 0.
  - Forma do alvo de mutação (código a nascer): `persistem` é a linha do `de:`, calculada depois de `uniao` e `acum`, e o texto aparece uma vez no arquivo. O `para:` reproduz o comportamento da fusão rasa de hoje (a lista nova do `--json` vence). Nenhum caso lê o texto do fonte.

### 4. `exigir --estagio fechar` recusa pendência sem destino [tipo: implementar]
atende: D6
arquivos: `scripts/estado.cjs`, `scripts/testa-pendente-destino.cjs`
depende de: 3
paralela: nao
prova: `node scripts/testa-pendente-destino.cjs`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const orfas = ESTAGIOS_DO_FLUXO.flatMap((e) => orfasDoBloco(e, estado[e]));`
  para: `const orfas = [];`
  bateria: `node scripts/testa-pendente-destino.cjs`
  fixture: `testa-pendente-destino.cjs, caso "exigir fechar recusa pendencia sem destino num bloco editado a mao"`
pronto quando: com um arquivo de estado em que todos os estágios estão fechados e um deles, editado à mão, tem pendência sem destino, `exigir --estagio fechar` sai 2 nomeando o estágio e o texto — provado por `node scripts/testa-pendente-destino.cjs` com `48 ok, 0 falha(s)`.
  - **7 casos novos.** O arquivo de estado vem de `iniciar` e é reescrito pela bateria com `fs.writeFileSync` (é exatamente o cenário "editado à mão"): os sete estágios com `status` de fechado (`design: aprovado`, os outros `ok`), mais o que o caso pede.
    1. nenhuma pendência: `exigir fechar` exit 0, stdout com `ok: pre-requisitos de 'fechar' fechados`.
    2. `executar` com `pendentes:[A]` e sem `destinos`: exit 2. O stderr cita `executar` e o texto de A.
    3. o mesmo, com `destinos` cobrindo A: exit 0. **Junto do 2, é o caso da mutação.**
    4. pendência órfã em `plano` e em `verificar`: exit 2. O stderr cita os **dois** estágios (a varredura não para na primeira).
    5. a chave `revisar_historico_1_23_0` com `status: "reprovado"` e `pendentes:[A]`: exit 0 (A8).
    6. `executar` com `pendentes: []`: exit 0.
    7. `exigir --estagio revisar` com a mesma órfã de `executar` (caso 2): exit 0 (a checagem é só do `fechar`).
  - **Na base** (CONFIRMADO por experimento na caixa): com os estágios fechados à mão e `design.pendentes: ["x"]` sem destino, `exigir --estagio fechar` sai **0** com `ok: pre-requisitos de 'fechar' fechados`.
  - **Código:** no ramo `if (!falta.length) {` do `exigir` (`:2080`), antes do `console.log('ok: ...')`, e só quando `estagio === 'fechar'`:
    - `ESTAGIOS_DO_FLUXO` (constante com os sete estágios, na ordem do fluxo);
    - `orfasDoBloco(estagio, bloco)`, que devolve as pendências do bloco sem destino (`semDestino`, da tarefa 2), ignorando bloco ausente e `pendentes` que não é lista.

    Se `orfas` não é vazio: `RECUSADO: 'fechar' exige que toda pendencia tenha destino. Sem destino:`, uma linha `  <estagio>: <texto>` por órfã, e a dica `Grave o destino: node scripts/estado.cjs marcar --slug <slug> --estagio <estagio> --status <status atual> --json '{"destinos":[...]}'`. Exit 2.
  - Forma do alvo de mutação (código a nascer): a linha do `de:` é a única que monta `orfas`, e o texto aparece uma vez no arquivo. `orfasDoBloco` é reaproveitada pela tarefa 5 (uma definição só de "órfã"). Nenhum caso lê o texto do fonte.

### 5. Verbo `deixado --slug` [tipo: implementar]
atende: D6
arquivos: `scripts/estado.cjs`, `scripts/testa-pendente-destino.cjs`
depende de: 4
paralela: nao
prova: `node scripts/testa-pendente-destino.cjs`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const itens = ESTAGIOS_DO_FLUXO.flatMap((e) => itensDeixados(e, estado[e]));`
  para: `const itens = [];`
  bateria: `node scripts/testa-pendente-destino.cjs`
  fixture: `testa-pendente-destino.cjs, caso "deixado lista os destinos de todos os estagios em markdown"`
pronto quando: `node scripts/estado.cjs deixado --slug <s>` imprime em markdown, uma linha por destino, na ordem do fluxo, ou `nada ficou para depois` — provado por `node scripts/testa-pendente-destino.cjs` com `56 ok, 0 falha(s)`.
  - **Formato (contrato testado):**
    - Uma linha por item: `- <estagio>: <pendente> → resolvida: <evidencia>`, `- <estagio>: <pendente> → plantada: <ref>` ou `- <estagio>: <pendente> → descartada: <motivo>`.
    - A pendência órfã sai como `- <estagio>: <pendente> → (sem destino)`.
    - Ordem: estágios na ordem do fluxo; em cada um, destinos na ordem gravada e depois as órfãs.
    - Quebra de linha e espaço repetido dentro de qualquer texto viram um espaço só (um texto com `\n` não quebra o markdown nem forja outro item).
    - Sem item nenhum: a linha `nada ficou para depois`.
    - Sempre exit 0. Não grava e não chama `carimbarFluxo`.
  - **8 casos novos:**
    1. fluxo sem pendência nem destino: stdout é exatamente `nada ficou para depois`.
    2. `executar` com 3 destinos (um de cada tipo): as 3 linhas exatas do formato, na ordem gravada. **É o caso da mutação.**
    3. destinos em `plano` e em `executar`: `plano` sai antes.
    4. pendência órfã (bloco editado à mão): linha com `(sem destino)`, exit 0.
    5. `pendente` e `evidencia` com `\n` e espaços repetidos: cada item ocupa uma linha só.
    6. `--slug` inexistente: exit 1 com a mensagem do `estado.cjs` ("nao existe").
    7. flag desconhecida (`deixado --slug x --estagio executar`): exit 1, `flag desconhecida: --estagio`.
    8. somente leitura: o arquivo de estado fica byte a byte igual depois do comando.
  - **Código:**
    - `FLAGS_POR_SUBCOMANDO.deixado = ['slug']` (`:1599-1610`). Sem essa entrada `validarFlagsDesconhecidas` ignora o subcomando.
    - O despacho entra logo depois de `ler` (`:2003`), já com o estado carregado, para herdar a recusa de slug inexistente.
    - `itensDeixados(estagio, bloco)` monta as linhas do bloco com `orfasDoBloco` (tarefa 4).
    - O cabeçalho de uso (`:27-36`) e a linha `uso:` (`:2507`) listam `deixado`.
    - A saída do `ler` não muda.
  - Forma do alvo de mutação (código a nascer): a linha do `de:` é a única que junta os itens de todos os estágios, e o texto aparece uma vez no arquivo. Nenhum caso lê o texto do fonte.

### 6. As skills `fechar` e `executar` falam de `destinos` [tipo: docs]
atende: D6, D7
arquivos: `skills/fechar/SKILL.md`, `skills/fechar/invariantes.json`, `skills/executar/SKILL.md`, `skills/executar/invariantes.json`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: texto de skill. A falsificação é o sensor `conferir-invariantes.cjs`, que sai diferente de 0 se a frase prescrita sumir do corpo, e a bateria `testa-fechar-destino.sh`, que lê o `fechar`. Não há comportamento de código a inverter.
pronto quando: o `fechar` manda colar a saída de `deixado` no corpo do PR e explica o exit 2 por pendência sem destino, o `executar` explica o `destinos` na "Condição de parada", e as duas frases ficam guardadas por invariante — provado por `node scripts/conferir-invariantes.cjs` imprimindo `ok: conferidas 21 invariantes`, `bash scripts/testa-fechar-destino.sh` com `ok: 32   falhou: 0`, `bash scripts/testa-conferir-invariantes.sh` com `ok: 32   falhou: 0` e `node hooks/testa-portaria-manifesto.cjs` com `62 ok, 0 falha(s)`.
  - **`skills/fechar/SKILL.md`:**
    - Abertura (`:10-15`): o parágrafo do exit 2 passa a dizer que ele também sai quando algum estágio tem pendência sem destino, e que o remédio é gravar o `destinos` com `marcar`, nunca editar o arquivo.
    - Passo 5: o corpo do PR passa de "três seções" (`:98`) a **quatro**. A quarta, `## Deixado para depois`, recebe a saída de `node scripts/estado.cjs deixado --slug <slug>` colada como está, inclusive a linha `nada ficou para depois`. O bloco do modelo (`:101-112`) ganha a seção.
    - A frase nova entra **antes** do parágrafo "Corpo do PR — palavras-chave de fechamento" (`:129`), para a região que `testa-fechar-destino.sh` extrai (de "O GitHub reconhece" até a primeira linha em branco) não mudar.
    - `invariantes.json`: nova entrada com a frase `node scripts/estado.cjs deixado --slug <slug>` e a descrição "Sem ela o PR volta a sair sem a lista do que ficou para depois".
  - **`skills/executar/SKILL.md`, "Condição de parada" (`:302-307`):**
    - A pendência nomeada continua indo no `pendentes` do `parcial`.
    - O texto novo diz que, para fechar `ok`, **cada pendência precisa de um destino** em `destinos`: `resolvida` com `evidencia`; `plantada` com `ref` `#<n>`, URL de issue do GitHub ou `ideia:<id>`; `descartada` com `motivo`. Leva um exemplo `--json` com `alfa`/`beta`.
    - Diz também que o `ok` sem destino sai 2 listando as que faltam, que `parcial` que omite uma pendência avisa e a mantém, e que `destinos` fica no estado para o `fechar` ler.
    - `invariantes.json`: nova entrada com a frase `cada pendência precisa de um destino` e a descrição "Sem ela volta o `ok` que apaga a pendência em silêncio".
  - Os textos de exemplo não citam nome real.

### 7. Registrar a bateria nova [tipo: configurar]
atende: D6
arquivos: `scripts/baterias-obrigatorias.txt`, `scripts/tempos-baterias.json`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: registro em lista. A falsificação é a própria varredura: sem o arquivo, o `FALTOU <caminho>` de `varrer-baterias.sh` acusa a obrigatória (mecanismo já coberto por `scripts/testa-varrer-baterias.sh`).
pronto quando: a bateria nova é descoberta, é obrigatória e tem peso — provado por `bash scripts/varrer-baterias.sh --listar | grep -c "^scripts/testa-pendente-destino.cjs$"` imprimindo `1`, por `grep -c "scripts/testa-pendente-destino.cjs" scripts/baterias-obrigatorias.txt` imprimindo `1`, por `node -p "require('./scripts/tempos-baterias.json')['scripts/testa-pendente-destino.cjs']>0"` imprimindo `true` e por `bash scripts/testa-varrer-baterias.sh` sem regressão (rode antes na base e cole o placar).
  - Linha nova em "Conferencias", ao lado de `scripts/testa-estado.sh`.
  - O peso em `scripts/tempos-baterias.json` é o tempo em segundos, inteiro, de `node scripts/testa-pendente-destino.cjs` medido por quem executa (chave na ordem alfabética do arquivo).

### 8. CHANGELOG e versão 1.55.0 [tipo: docs]
atende: D7
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: documentação e número de versão. A falsificação é a coerência do texto com as decisões e dos quatro lugares da versão entre si, medida por `conferir-versao.cjs` e `testa-versao.sh`.
pronto quando: a versão vale nos quatro lugares, é maior que a de `origin/main`, e o CHANGELOG descreve o contrato novo — provado pelos comandos abaixo.
  - **Antes de subir o número:** `git fetch origin`, depois `git show origin/main:.claude-plugin/plugin.json` (hoje 1.54.3). Se `origin/main` já passou de 1.54.3, renumerar para o próximo MINOR livre e dizer isso no relato. Em seguida `git merge origin/main` na branch (ela está um commit atrás, A14), **antes** de editar os quatro arquivos, para a entrada nova ficar acima da 1.54.3 e não haver conflito em `CHANGELOG.md`, `README.md` e nos `plugin.json`.
  - **Versão:** `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` vão a `1.55.0`; o badge do `README.md:7` (URL `vers%C3%A3o-1.55.0` e `alt="versão 1.55.0"`). Os quatro no mesmo commit.
  - **CHANGELOG:** `## 1.55.0 — <data de hoje>`, em linguagem de quem usa o plugin:
    - Fechar um estágio `ok`/`aprovado` com pendência sem destino passa a ser recusado (exit 2), listando as que faltam. Antes a pendência sumia em silêncio.
    - Os três destinos (`resolvida` com `evidencia`, `plantada` com `ref`, `descartada` com `motivo`) e as formas aceitas de `ref`.
    - `parcial` que omite pendência avisa e a mantém.
    - `exigir --estagio fechar` recusa pendência sem destino em arquivo antigo ou editado à mão.
    - `estado.cjs deixado --slug <s>` e o novo bloco "Deixado para depois" no corpo do PR.
    - Quem tem fluxo em andamento com `pendentes` num `parcial` precisa gravar `destinos` antes do `ok`. Estados já fechados não mudam e nenhum migra.
  - **Comandos:**
    - `node -p "require('./.claude-plugin/plugin.json').version+' '+require('./.codex-plugin/plugin.json').version"` imprimindo `1.55.0 1.55.0`.
    - `bash scripts/testa-versao.sh` terminando em `ok: 5   falhou: 0`.
    - `node scripts/conferir-versao.cjs` com exit 0.
    - `grep -o "1\.55\.0" README.md | wc -l` imprimindo `2` (URL e `alt` do badge).
  - **Coerência conferida à mão:** o CHANGELOG não cita comportamento que o design não tenha (por exemplo, nenhuma conferência de `ideia:<id>` contra o `ideias.jsonl`) e não cita nome real.

## Notas de integração

- **Ordem:** as oito tarefas são seriais. As cinco primeiras editam `scripts/estado.cjs` e a mesma bateria; a 6 e a 7 dependem do verbo da 5; a 8 fecha. Nenhuma é `paralela: sim`.
- **Alvos de mutação em código a nascer** (tarefas 1 a 5):
  - Se o executor escrever a linha diferente da prescrita, atualiza o bloco `mutacao:` do plano **antes** de rodar `conferir-mutacao.cjs`. A `cobertura` só avisa em zero ocorrências, mas a catraca sai com "MUTACAO NAO APLICADA".
  - Cada `de:` tem de aparecer **uma vez** no arquivo (a `conferir-mutacao` recusa `de:` que casa duas).
  - A mutação é feita no fonte de produção dentro do clone fiel. Nenhum caso de teste aplica mutação em cópia.
- **Contagens do `pronto quando`** (25, 34, 41, 48 e 56 na bateria nova; 324 em `testa-estado.sh`) saem desta lista de casos. Se o executor recontar e achar outro número por ter juntado ou separado um caso, atualiza o plano antes do `verificar`, como nos alvos de mutação.
- **Comandos com `timeout`:** a bateria nova roda dezenas de `node` em série. Quem executa a chama com `timeout` explícito na chamada do Bash (até 600000). Comando com variável vai entre aspas (`bash "$arquivo"`), nunca solto: o hook `gate-fechar-issue.cjs` barra `bash $arquivo`.
- **Integração (janela principal), depois da tarefa 8:**
  - `bash scripts/varrer-baterias.sh` completo (o agente não roda a varredura sem `--so`).
  - `node scripts/conferir-categoria.cjs`, `node scripts/conferir-fluxo.cjs cobertura --slug 2026-10-09-pendente-destino` e a conferência dos placares de "O que não pode quebrar".
- **`fechar` (janela principal):**
  - PR direto, com a seção "Deixado para depois" gerada pelo `deixado` deste fluxo (`nada ficou para depois`, ou a lista).
  - Comentário e fechamento da Issue #449 como resultado natural da entrega.
  - **Issue nova**, a critério do usuário: integração do painel "Deixado para depois" do mod (`hooks/mod.tsx`) com o estado. Fica fora de escopo no design e só vale abrir depois de medir o ruído do painel.

## Premissas aceitas sem conferir

1. **O design é fonte fechada.** Li as sete decisões e o critério de pronto e não reabri nenhuma. O número "12 arquivos de estado com `pendentes`" do design eu conferi (12, A9).
2. **Só este repositório lê `pendentes` do estado.** Busquei em `skills/`, `agents/`, `commands/`, `hooks/`, `scripts/`, `evals/`, `test/`, `workflows/`, `vigias/` e `types/`. Outro plugin ou projeto do usuário que grave ou leia o campo não foi visto.
3. **O orquestrador que escreve `--json` entrega JSON bem formado.** Não testei o quoting real do `--json` com acento e aspas no PowerShell. A bateria usa vetor de argumentos e não mede isso.
4. **`CI=1` na bateria equivale ao ambiente do runner.** Conferi o código de `checkoutPrincipalForaDaPadrao` (`:1373`), mas não rodei a bateria nova no Actions.
5. **`conferir-mutacao.cjs` aceita `node scripts/testa-pendente-destino.cjs` como `bateria:`.** Li o cabeçalho (exige que a bateria imprima o placar `N ok, M falha(s)`, que o formato prescrito atende). Não rodei a catraca contra código que ainda não existe.
6. **O tempo da bateria nova e o peso do shard não foram medidos.** A tarefa 7 manda medir.
7. **`git merge origin/main` na tarefa 8 não conflita.** O que `origin/main` mudou em relação ao HEAD (README, CHANGELOG, `plugin.json`, `scripts/varrer-baterias.sh`, `scripts/testa-varrer-baterias.sh`, um estado de outro fluxo) não toca `scripts/estado.cjs` nem as skills. Não simulei o merge.
8. **A seta `→` e os acentos saem intactos do `node` para o pipe no Windows.** O `deixado` imprime UTF-8 e a bateria lê o stdout como UTF-8. Não conferi o que o terminal do PowerShell mostra, e o corpo do PR é montado a partir da saída capturada.
9. **`reprovado` e `pendente` são "não terminal" também para o D5.** O design diz "status não terminal" sem listar. Assumi a leitura literal (A5).
10. **A forma exata das mensagens de recusa e aviso é minha.** O design fixa o exit 2, o stderr e "diz o item", não o texto. Os casos de teste conferem que o texto da pendência aparece e o campo faltante é nomeado, não a frase inteira.
11. **O rascunho passa em `conferir-fluxo.cjs cobertura`** (`ok: cobertura válida — 7 decisão(ões), 8 tarefa(s)`, rodado numa cópia do plano e do design no scratchpad). Não rodei `design` nem `mutacoes` sobre ele: o primeiro exige a varredura do design, que não copiei, e o segundo roda no `verificar`.
