# Plano: Zerar as Issues abertas, rodada 6 — regra 6 e as 3 da rodada 5

Design: docs/rainforest/design/zerar-issues-6.md

## O que não pode quebrar
- Toda bateria que hoje passa continua passando; caso existente só muda quando a decisão muda o comportamento (a seção 20 do `testa-conferir-mutacao.sh`, D8; o `medir_sobra`, D12).
- Casos verdes que dependem do marcador `dados-de-exemplo` continuam verdes: os 8 usos reais estão na linha 1 ou 2.
- Nenhuma tarefa escreve no `$TEMP` real, em `~/.rainforest` ou fora do próprio worktree: a varredura de órfãos (tarefa 6) é testada com `TMP`/`TEMP` apontando para sandbox.
- `NUCLEOS_MAX_BYTES` (6000) não sobe: a regra 6 cabe na folga de 103 B ou paga por subtração.
- Os 9 `agents/*.md` só mudam por `node scripts/perfil.cjs --aplicar`.

## Notas do planejamento
- Dois planejadores escreveram as tarefas 2-4 e 5, 6, 8, 9 lendo o código em `9a539128`, medindo em worktrees descartáveis; a janela principal escreveu 1 e 7 e trocou os `para:` vazios das tarefas 5 e 8 por substitutos executáveis.
- Tarefa 2: a causa é uma só nos três itens — `foco.cjs:70-91` faz os `require` relativos no topo do módulo, então qualquer subcomando do mutante morre antes da lógica.
- Tarefa 3: medido que hoje uma credencial nova num arquivo com o marcador só na linha 100 passa pelo `gate-publicacao-destino` (exit 0) — a D6 fecha isso, não só alinha os dois gates.
- Tarefas 3 e 4 tocam a mesma bateria; 5 e 6 também; 1 e 9 também: daí as dependências seriais.
- Tarefa 6: o nome `limparTemporariosOrfaos()` e o ponto de chamada são inferência do planejamento, não do design.
- Execução, tarefa 2: o item 13 do `testa-foco.sh` nunca mediu nada — a âncora `while (arquivos.length > teto)` não existe em `foco.cjs` desde que a poda foi para `scripts/lib/backup-rotativo.cjs`. O agente reescreveu a mutação do item 13 para o laço real, dentro do mesmo arquivo.
- Execução, tarefa 8: a fixture passou de caminho de home para `/c/proj/x` — o gate de publicação instalado barra caminho de home mesmo com marcador (o defeito da #293, que só some quando esta versão for instalada).
- Execução, tarefa 7: deixou `regra-12.md` em 10571 B, acima de `REFERENCE_MAX_BYTES` (10500); a integração não rodou `testa-contexto-sessao.sh` e só a tarefa 9 revelou. Corrigido em `edcc44b2` (10491 B).

## Tarefas

### 1. Regra 6: fronteira de repo e limiar único "atrapalha", no núcleo e na elaboração [tipo: docs]
atende: D1, D2, D3, D4
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-06.md`, `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: a tarefa só muda texto de regra; não há ramo de código a inverter. A catraca de bytes (`NUCLEO_ESPERADO` em `hooks/testa-contexto-sessao.sh`) já é a falsificação mecânica do tamanho, e a coerência se confere pelas prescrições abaixo.
pronto quando: com o núcleo emitido de verdade pelo hook de abertura (`node hooks/contexto-sessao.cjs` via a seção D7 de `bash hooks/testa-contexto-sessao.sh`, que mede os bytes do núcleo real), (i) o texto da regra 6 no `SKILL.md` prescreve as três coisas decididas e nenhuma contrária: conserto na hora só **no repo da sessão** e quando o defeito **atrapalha** a tarefa (D1, D2); defeito em repo **alheio** → Issue no repo dono + `Q` com recomendação, sem commit (D1); e "bloqueia" não aparece como **limiar** de conserto em nenhum dos dois arquivos — `grep -n "bloqueia o trabalho\|Defeito que \*\*bloqueia\|se bloqueia" skills/rainforest-mind/references/regra-06.md skills/rainforest-mind/SKILL.md` sai vazio (a palavra pode aparecer citando o argumento do incidente); (ii) `regra-06.md` deixa de dizer "não sobe como Issue: conserta e segue" sem condição e passa a dizer que no repo da sessão o commit é o registro e só vira Issue o que não for consertado (D2), tem subseção com a fronteira de repo que diz explicitamente que o peso do defeito ("mas bloqueia a entrega") não move a fronteira e que a recomendação da `Q` pode ser consertar agora (D1), diz que a fronteira é só texto, sem hook (D3), e registra o incidente de 2026-09-16 (Issue #291, sessão em outro repo que consertou o gerador do repo vizinho com outra sessão ativa nele) num bloco `>` com linha `re-verificar:` executável (`gh issue view 291 --json title`) — sem nome de cliente, repo privado ou empresa (D4); (iii) a nota final "nunca barrar defeito" (hoje `regra-06.md:51`) diz o mesmo limiar e a mesma fronteira; (iv) `NUCLEO_ESPERADO` é atualizado para os bytes reais com uma linha de histórico datada 2026-09-17 no padrão das anteriores, e o valor fica **≤ 6000** (`NUCLEOS_MAX_BYTES`) sem subir a catraca — se não couber, paga por subtração no próprio texto da regra 6 — provado por `bash hooks/testa-contexto-sessao.sh` com as linhas `D7: nucleo emitido mede exatamente` e a do teto em `ok`, e por `node scripts/conferir-invariantes.cjs` exit 0 se ele cobrir `references/` (datas com bloco `>`).

### 2. testa-foco.sh: itens 9, 13 e 15 param de aceitar MODULE_NOT_FOUND como detecção [tipo: teste]
atende: D5
arquivos: `scripts/testa-foco.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/testa-foco.sh`
  de: `MUT="$SRC/scripts/.mut-tmp-foco-09.cjs"`
  para: `MUT="$SBP/foco-mutante.cjs"`
  bateria: `bash scripts/testa-foco.sh`
  fixture: item 9 ("9. mutacao (a bateria tem de acusar)") — mutante que desliga a condição de corte de `rotacionar`
pronto quando: (`de:` acima é trecho NOVO — hoje a linha 246 é literalmente o `para:`; reverter o caminho reproduz o crash que o guard novo tem de reconhecer.) Causa única, CONFIRMADA ao vivo pelo planejamento nos três itens: `scripts/foco.cjs:70-91` faz `require('./lib/backup-rotativo.cjs')` e `require('../hooks/lib/contexto-sessao.cjs')` no topo do módulo, então mutante gravado em `$SBP` (item 9 `:246` `rotacionar`, item 13 `:219` `backup`, item 15 `:613` `separar`) morre com `MODULE_NOT_FOUND` antes da lógica mutada, com o stderr em `/dev/null`, e o item lê o arquivo intocado como detecção. Conserto nos três: mutante em `$SRC/scripts/.mut-tmp-foco-<NN>.cjs` (padrão do item 17, `:314`), apagado ao fim com `rm -f` (o item 9 hoje não apaga nada); stderr capturado numa variável; se contiver `MODULE_NOT_FOUND`, o item registra `FALHA mutante nao rodou (MODULE_NOT_FOUND) -- crash mascarado de deteccao` e nunca `ok`. Com a entrada real `node <mutante> rotacionar --raiz <sandbox> --aplicar` (a mesma forma de `commands/foco.md:23`), o efeito é: com o `para:` aplicado, `bash scripts/testa-foco.sh` sai **exit 1** com a linha `FALHA mutante nao rodou (MODULE_NOT_FOUND)`; sem a mutação, sai exit 0 e nenhum dos três mutantes escreve em stderr — provado por `node scripts/conferir-mutacao.cjs --arquivo scripts/testa-foco.sh --de 'MUT="$SRC/scripts/.mut-tmp-foco-09.cjs"' --para 'MUT="$SBP/foco-mutante.cjs"' --bateria "bash scripts/testa-foco.sh"` saindo 0 (`vermelho`), e por `git status --short scripts/` vazio depois da bateria (nenhum `.mut-tmp-*` sobra). Superfície humana: quem lê a saída da bateria vê `FALHA ... crash mascarado` no lugar de um `ok` indistinguível de detecção real.

### 3. temMarcadorDados sobe para hooks/lib/marcador-dados.cjs, olha só as 5 primeiras linhas, e gate-verificador-staged passa a respeitá-lo [tipo: implementar]
atende: D6
arquivos: `hooks/lib/marcador-dados.cjs`, `hooks/gate-publicacao-destino.cjs`, `hooks/gate-verificador-staged.cjs`, `hooks/testa-gate-publicacao-destino.sh`, `hooks/testa-gate-verificador-staged.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/marcador-dados.cjs`
  de: `const primeirasLinhas = conteudo.split('\n').slice(0, 5).join('\n');`
  para: `const primeirasLinhas = conteudo;`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: caso novo "marcador só conta nas 5 primeiras linhas (Issue #293)" — arquivo versionado com o marcador só na linha 6 e `Edit` introduzindo `jid="5500900000001@s.whatsapp.net"`
pronto quando: (`de:`/`para:` são trecho NOVO — `hooks/lib/marcador-dados.cjs` não existe em `9a539128`.) `hooks/lib/marcador-dados.cjs` exporta `temMarcadorNoConteudo(conteudo)`, que testa `/rainforest-gate:\s*dados-de-exemplo/i` só nas 5 primeiras linhas; o próprio arquivo da lib **não** traz o literal do marcador nas suas 5 primeiras linhas. Em `hooks/gate-publicacao-destino.cjs`, `temMarcadorDados(caminhoDoArquivo)` (`:309-317`) vira wrapper que lê o disco e delega (assinatura e `try/catch` preservados; chamadores `:672` e `:700` sem mudança), e a regex inline de `:601` passa a chamar `temMarcadorNoConteudo(conteudo)`. Em `hooks/gate-verificador-staged.cjs`, dentro de `materializaStaged`, logo após `if (jaPublicado) continue;` (`:118`), entra `if (temMarcadorNoConteudo(conteudo)) continue;` (o `conteudo` de `git show :nome`, não o disco). Entradas reais, CONFIRMADAS ao vivo pelo planejamento: (a) payload PreToolUse `{"cwd":"<repo>","tool_name":"Edit","tool_input":{"file_path":"<repo>/marcador-tardio.sh","old_string":"...","new_string":"jid=\"5500900000001@s.whatsapp.net\""}}` contra arquivo versionado com marcador só na linha 6 (no caso medido, linha 100) sai **HOJE exit 0**; depois do conserto sai **exit 2**; (b) payload `{"cwd":"<repo>","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}` com `arquivo.txt` staged = `# rainforest-gate: dados-de-exemplo` + `contato: SEGREDO` e `.rainforest/config.json` com `{"verificador-staged": "bash scripts/verifica.sh"}` que reprova `SEGREDO` sai **HOJE exit 2**; depois do conserto sai **exit 0**, e o mesmo conteúdo sem a linha do marcador continua exit 2. Sem regressão: os 8 usos reais do marcador no repo estão na linha 1 ou 2, e os casos verdes de hoje que dependem dele (`testa-gate-publicacao-destino.sh` "Edit em arquivo COM marcador em disco"; `hooks/testa-gate-commit.cjs:129`) continuam `ok` — provado por `bash hooks/testa-gate-publicacao-destino.sh`, `bash hooks/testa-gate-verificador-staged.sh` e `node hooks/testa-gate-commit.cjs` saindo 0 com os casos (a) e (b) presentes, e por `node scripts/conferir-mutacao.cjs --arquivo hooks/lib/marcador-dados.cjs --de "const primeirasLinhas = conteudo.split('\n').slice(0, 5).join('\n');" --para "const primeirasLinhas = conteudo;" --bateria "bash hooks/testa-gate-publicacao-destino.sh"` saindo 0 (`vermelho`).

### 4. gate-verificador-staged entra em CHAVES: o toggle do config.json passa a desligar de verdade [tipo: implementar]
atende: D7
arquivos: `hooks/lib/config.cjs`, `hooks/testa-gate-verificador-staged.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `hooks/lib/config.cjs`
  de: `'gate-verificador-staged': {`
  para: `'gate-verificador-staged-desativada': {`
  bateria: `bash hooks/testa-gate-verificador-staged.sh`
  fixture: caso novo (j) — `.rainforest/config.json` com `"verificador-staged"` reprovando `SEGREDO` e `"gate-verificador-staged": false`
pronto quando: (`de:`/`para:` são trecho NOVO — a chave não existe em `CHAVES` em `9a539128`.) `hooks/gate-verificador-staged.cjs:250` já chama `ligado("gate-verificador-staged", { projeto: cwdDoEvento })`, mas `ligado()` devolve `true` antes de ler config para chave fora de `CHAVES` (`hooks/lib/config.cjs:324`). Entra em `CHAVES`, depois de `gate-agente-em-voo`, a entrada `'gate-verificador-staged': { tipo: 'boolean', padrao: true, descricao: '...' }`; o hook não muda. Entrada real, CONFIRMADA ao vivo pelo planejamento: payload `{"cwd":"<repo>","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}` com `contato: SEGREDO` staged e config `{"verificador-staged": "bash scripts/verifica.sh", "gate-verificador-staged": false}` sai **HOJE exit 2**, e a própria mensagem de bloqueio anuncia o toggle como saída; depois do conserto sai **exit 0**, e com `"gate-verificador-staged": true` (ou chave ausente) continua exit 2 — provado pelo caso (j) em `bash hooks/testa-gate-verificador-staged.sh` saindo 0, por `node -e "console.log(require('./hooks/lib/config.cjs').ligado('gate-verificador-staged', {projeto: process.argv[1]}))" <repo-com-config-desligando>` imprimindo `false`, e por `node scripts/conferir-mutacao.cjs --arquivo hooks/lib/config.cjs --de "'gate-verificador-staged': {" --para "'gate-verificador-staged-desativada': {" --bateria "bash hooks/testa-gate-verificador-staged.sh"` saindo 0 (`vermelho`).

### 5. testa-conferir-mutacao.sh: checagem do __pycache__ lê o stdout da bateria de fixture, que roda na cópia; a asserção sobre $CAIXA sai [tipo: teste]
atende: D8
arquivos: `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `PYTHONDONTWRITEBYTECODE: '1',`
  para: `PYTHONDONTWRITEBYTECODE_DESLIGADO: '1',`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  timeout: `600000`
  fixture: seção 20 (`D25: Python .pyc nao fica mutado`), `bateria-pyc.sh` imprimindo `PYCACHE_VISTO=`
pronto quando: com a entrada real de `rodaBateria()` (`scripts/conferir-mutacao.cjs:357`, env da bateria executada dentro de `raizExecucao`, a cópia criada em `:513` e apagada por `limpar()` antes de o controle voltar ao teste), o `bateria-pyc.sh` da seção 20 passa a imprimir no próprio stdout `PYCACHE_VISTO=sim` ou `PYCACHE_VISTO=nao` conforme exista `__pycache__` no diretório em que ele roda, e a asserção passa a exigir `PYCACHE_VISTO=nao` nas duas rodadas (baseline e pós-mutação) em `$SAIDA`, substituindo o `[ -d "$CAIXA/__pycache__" ]` (`:856-857`), que nunca pode ver nada. CONFIRMADO ao vivo pelo planejamento em worktree descartável: com o teste de hoje e a mutação aplicada, a seção 20 continua `ok` nas 8 linhas (o defeito); com o conserto e sem mutação, a seção fica `ok`; com o conserto e a mutação, a seção fica vermelha (`PYCACHE_VISTO=sim` duas vezes) — provado por `bash scripts/testa-conferir-mutacao.sh` saindo 0 sem mutação e por `node scripts/conferir-mutacao.cjs --arquivo scripts/conferir-mutacao.cjs --de "PYTHONDONTWRITEBYTECODE: '1'," --para "PYTHONDONTWRITEBYTECODE_DESLIGADO: '1'," --bateria "bash scripts/testa-conferir-mutacao.sh"` saindo 0 (`vermelho`). A asserção que grepa o texto `PYTHONDONTWRITEBYTECODE` na doc-string (~`:190`) não é tocada.

### 6. conferir-mutacao.cjs apaga na abertura diretórios conferir-mutacao-* órfãos com mais de 24 h [tipo: implementar]
atende: D9
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: 5
paralela: nao
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (Date.now() - st.mtimeMs < LIMITE_ORFAO_MS) continue;`
  para: `continue;`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  timeout: `600000`
  fixture: seção nova "varredura de órfãos (Issue #294.2)" com `TMP`/`TEMP` apontando para sandbox do teste
pronto quando: (`de:`/`para:` são trecho NOVO — a varredura não existe em `9a539128`; `para:` é o comportamento de hoje.) Uma função `limparTemporariosOrfaos()` roda na abertura de `main()`, antes do `fs.mkdtempSync` de `:513`, sobre `os.tmpdir()`: só **diretórios**, só nomes `conferir-mutacao-*` (o que inclui `conferir-mutacao-git-*`), só mtime acima de `LIMITE_ORFAO_MS` (24 h); erro de leitura ou remoção é silencioso e nunca muda o exit. Entrada real: `node scripts/conferir-mutacao.cjs ...` com `TMP`/`TEMP` do processo filho apontando para um sandbox (nunca o `$TEMP` real; `os.tmpdir()` honra as duas no Windows, CONFIRMADO pelo planejamento) contendo `conferir-mutacao-VELHO/` e `conferir-mutacao-git-VELHO/` (mtime 2 dias atrás), `conferir-mutacao-NOVO/` (agora), `outra-coisa-velha/` (2 dias) e o arquivo `conferir-mutacao-ARQUIVO.txt` (2 dias): depois de uma execução, somem só os dois primeiros e os outros três ficam — CONFIRMADO ao vivo pelo planejamento; com a mutação, um `conferir-mutacao-VELHO2/` de 2 dias sobrevive — provado pela seção nova em `bash scripts/testa-conferir-mutacao.sh` e por `node scripts/conferir-mutacao.cjs --arquivo scripts/conferir-mutacao.cjs --de "if (Date.now() - st.mtimeMs < LIMITE_ORFAO_MS) continue;" --para "continue;" --bateria "bash scripts/testa-conferir-mutacao.sh"` saindo 0 (`vermelho`).

### 7. A frase "nunca numa cópia" distingue clone fiel via catraca de fixture isolada [tipo: docs]
atende: D10
arquivos: `referencias/perfil-de-trabalho.md`, `skills/rainforest-mind/references/regra-12.md`, `agents/tester.md`, `agents/revisor.md`, `agents/resolvedor-de-build.md`, `agents/planejador.md`, `agents/executor.md`, `agents/documentador.md`, `agents/depurador.md`, `agents/auditor-de-seguranca.md`, `agents/arqueologo.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de regra replicado por script; a falsificação mecânica é a identidade fonte↔agentes, já coberta por `node scripts/perfil.cjs --conferir`, e a coerência se confere contra o comportamento real do `conferir-mutacao.cjs`.
pronto quando: com o comportamento real de `scripts/conferir-mutacao.cjs` (que sempre copia a árvore para `raizExecucao = fs.mkdtempSync(...)`, linha ~513, aplica a mutação no fonte **de produção dentro dessa cópia fiel** e roda a bateria lá), (i) o item "Mutação é editar o código de produção" de `referencias/perfil-de-trabalho.md` (~76-82) e o fecho do parágrafo de mutação de `regra-12.md` (~96, "nunca numa cópia") deixam de contradizer esse comportamento: dizem que a catraca `conferir-mutacao.cjs`, que clona a árvore inteira e muta o fonte de produção no clone, é o caminho aceito, e que **proibido** continua sendo o caso de teste que aplica a mutação numa cópia isolada do trecho (fixture) ou a cópia feita à mão; (ii) a razão original (Issue #21, P4 — passa nos dois mundos, infla o placar) permanece; (iii) os 9 agentes recebem o bloco novo só por `node scripts/perfil.cjs --aplicar`, nunca por edição à mão — provado por `node scripts/perfil.cjs --conferir` exit 0 com `ok: os 9 agentes carregam o bloco da fonte`, e por `grep -c "conferir-mutacao" agents/executor.md referencias/perfil-de-trabalho.md` ≥ 1 em cada, e `git diff --stat` mostrando os 9 `agents/*.md` alterados com o mesmo número de linhas.

### 8. normalizarMsys devolve o caminho intacto fora de win32 [tipo: implementar]
atende: D11
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-cwd-efetivo.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `if (plataforma !== "win32") return caminho;`
  para: `if (false) return caminho;`
  bateria: `bash hooks/testa-cwd-efetivo.sh`
  fixture: caso novo `(msys-1) plataforma injetada 'linux': /c/proj/x volta INTACTO`
pronto quando: (`de:` é trecho NOVO.) A assinatura vira `normalizarMsys(caminho, plataforma = process.platform)`; os chamadores reais (`:371`) não mudam. Entrada real: `normalizarMsys("/c/proj/x", "linux")` devolve `/c/proj/x`, e `normalizarMsys("/c/proj/x", "win32")` continua devolvendo `c:/proj/x` — CONFIRMADO ao vivo pelo planejamento: `bash hooks/testa-cwd-efetivo.sh` vai de 47/0 para 49/0, e com a mutação fica 48/1 com a falha em `(msys-1)`; `bash hooks/testa-gate-worktree.sh` (ponta a ponta com `cd /c/...`, seção "Issue #289") continua 204/0 — provado pelas duas baterias e por `node scripts/conferir-mutacao.cjs --arquivo hooks/lib/cwd-efetivo.cjs --de 'if (plataforma !== "win32") return caminho;' --para 'if (false) return caminho;' --bateria "bash hooks/testa-cwd-efetivo.sh"` saindo 0 (`vermelho`).

### 9. testa-contexto-sessao.sh: SOBRA_22_* medem a saída real de montarContexto; medir_sobra sai [tipo: teste]
atende: D12
arquivos: `hooks/testa-contexto-sessao.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: `if (fixoComCorteMaximo <= TETOS.ORCAMENTO_BYTES - TETOS.FOCO_MIN_BYTES) {`
  para: `if (true) {`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  timeout: `300000`
  fixture: seção nova 22.3 "só corta se resolver — corte que não resolve fica de fora", fixture `PRINCIPAL_DOMINANTE_22`
pronto quando: (depende da 1 porque as duas tocam esta bateria; a 1 só na linha `NUCLEO_ESPERADO=`.) `medir_sobra()` (~`:2761-2818`, espelho do corte sem o "só corta se resolver" de `contexto-sessao.cjs:1167-1188`) sai; `SOBRA_22_1`/`SOBRA_22_2` passam a vir de `sobra_real()`, que roda o driver real (`contexto_rodape`, ~`:2755`, ganhando parâmetro opcional de foco com default `$FOCO_MUITOS`) com foco vazio e desconta a mensagem fixa de foco vazio (`contexto-sessao.cjs:1210-1211`), sem reimplementar corte. Entrada real: o `montarContexto` exportado, com os fixtures 22.1 e 22.2 — CONFIRMADO ao vivo pelo planejamento que `sobra_real` dá os mesmos 725 e 851 do espelho; com aviso de principal atrasado dominante, espelho dá -2934 e a saída real +7413 (a divergência da #294.5). Seção nova 22.3 com `PRINCIPAL_DOMINANTE_22` (aviso acrescido de 510 B): sem mutação, a saída real mantém `Dependências de ambiente` e `radar multi-janela` e não traz `ACIMA DO ORÇAMENTO`; com a mutação, os dois blocos somem — provado por `bash hooks/testa-contexto-sessao.sh` saindo 0 (placar de hoje 293 → 296) e por `node scripts/conferir-mutacao.cjs --arquivo hooks/lib/contexto-sessao.cjs --de "if (fixoComCorteMaximo <= TETOS.ORCAMENTO_BYTES - TETOS.FOCO_MIN_BYTES) {" --para "if (true) {" --bateria "bash hooks/testa-contexto-sessao.sh"` saindo 0 (`vermelho`). A seção "22.3 MUTAÇÃO" existente vira 22.4, só rótulo. Se a string de foco vazio mudar no fonte, `sobra_real` falha alto (asserção de que a mensagem fixa foi achada na saída), nunca calcula com ela ausente.
