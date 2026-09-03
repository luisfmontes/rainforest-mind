# Plano: Fluxo 7 — Recibo (`recibo.cjs`)

Design: `docs/rainforest/design/fluxo-7-design-recibo.md` (seção final `# Design formal` fecha D1–D10 — decisão fechada, não reaberta aqui; leia-se `fechar` onde o design ainda fala em `colher`).

## Achados que mudam o plano (leia antes das tarefas)

**1. O nome deste arquivo é derivado do slug — CONFIRMADO.** `scripts/conferir-fluxo.cjs` deriva `docs/rainforest/planos/${slug}.md` de `--slug`. Por isso este conteúdo mora em `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md`.

**2. O núcleo do `SKILL.md` está a 3 B do teto — CONFIRMADO por medição.** `node scripts/medir-skill.cjs` devolve `nucleo=5597 regras=17 references=19 skill-bytes=10139`; o teto é `NUCLEOS_MAX_BYTES: 5600` em `hooks/lib/contexto-sessao.cjs`. A regra 18 (D10) **não cabe** sem abrir espaço. A Tarefa 6 carrega essa exigência e a decisão de COMO abrir espaço fica com quem executa — ver a nota na própria tarefa.

**3. `.rainforest/` não é ignorado em bloco neste repo — CONFIRMADO.** `git ls-files .rainforest` devolve `agentes.json`, `portaria/LEIA-ME.md` e as duas `portaria/amostra*.json`; só `.rainforest/portaria/despachos.jsonl` está no `.gitignore`, com comentário explicando a divisão rastro-vs-documentação. D9 precisa da MESMA forma de entrada nova, comentada, para `.rainforest/colheita/`.

**4. `recibo.cjs` não pode importar `RAIZ` de `estado.cjs` — CONFIRMADO.** `module.exports` (`scripts/estado.cjs:1113`) expõe só `novo, proximo, faltando, estaFechado, EXECUCAO, PRE_REQUISITOS, DIR_ESTADO`. A resolução `RFM_ESTADO_ROOT || CLAUDE_PROJECT_DIR || cwd()` já está duplicada em `estado.cjs`, `conferir-fluxo.cjs` e `conselho.cjs` — repetir o padrão não cria acoplamento novo.

**5. `recibo` está livre como verbo — CONFIRMADO.** Os `cmd === '...'` do `estado.cjs` são `listar, iniciar, ler, proximo, exigir, liberar, marcar`.

**6. `nao_provado` é efêmero da chamada, não pode vir do disco.** Quando o gate de `fechar` roda dentro do `marcar`, o bloco `fechar` ainda não foi persistido — a mesma janela em que `revisar` hoje recebe `base`/`head` só pelo `--json` da chamada corrente. `nao_provado` viaja igual: por CLI.

**7. D4 não fixa exit 1 vs 2 no texto do design — decidido exit 2.** É pré-condição impeditiva (não dá nem para tentar hashear), no mesmo grupo do "recusado na gravação com exit 2" que D7 já fixa, e no mesmo espírito da distinção que o cabeçalho do `portoes.cjs` documenta: "os portões reprovaram" (1) vs "não consegui nem ler" (2).

**8. `nao_provado` nunca tem sugestão padrão.** Resolve a seção "Em aberto" do design a favor de sempre escrito à mão: default poupa digitação e convida a aceitar a lista sem pensar, que é o oposto do que D7 quer.

## O que não pode quebrar

- Fluxo sem `plano.entregaveis` fecha `fechar` **exatamente como hoje** (D3) — e a decisão de opt-in mora dentro do `recibo.cjs`, não em `estado.cjs` decidir de antemão se chama. Um lugar só decide.
- Os dois pontos de disparo dos portões (fluxo 6: `plano`/lint, `verificar`/rodar) continuam intactos. D5 abre um **terceiro**, dentro do `recibo.cjs`, no `fechar`.
- `conferirFechamento` continua **acumulando** recusas em vez de parar na primeira (achado do fluxo 6). O gate novo entra nessa lista, não a interrompe.
- Nenhuma asserção sobre `\r` usa `grep` — o `grep` do Git Bash normaliza CRLF antes de casar.
- Confinamento de caminho é sempre por `realpath`, nunca `path.resolve` + `startsWith`.

## Tarefas

### 1. `recibo.cjs` nasce — leitura do estado + `mostrar` [tipo: implementar]
atende: D9
arquivos: `scripts/recibo.cjs`, `scripts/testa-recibo-mostrar.sh`, `test/fixtures/recibo/**`
depende de: nenhuma
paralela: sim

Escopo: `scripts/recibo.cjs` nasce com RAIZ resolvida como em `estado.cjs`/`conselho.cjs` e validação de slug idêntica. `mostrar <slug>`: lê `.rainforest/colheita/<slug>-recibo.json`. Existindo, imprime por entregável caminho + sha256 + bytes, a lista `nao_provado` e o timestamp. Não existindo, imprime "sem recibo gravado para `<slug>`" e sai **0** — reportar ausência não é erro. Slug com `/`, `\` ou `..` sai **2**.

mutacao:
  arquivo: `scripts/recibo.cjs`
  de: `mostrar` de slug sem recibo sai 0 e avisa "sem recibo gravado"
  para: `mostrar` de slug sem recibo lança e sai com stack trace
  bateria: `bash scripts/testa-recibo-mostrar.sh`
  fixture: slug sem recibo nenhum, em raiz sandbox — a bateria afirma exit 0 e a mensagem exata.

pronto quando: `bash scripts/testa-recibo-mostrar.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) slug sem recibo → mensagem + exit 0; (b) recibo gravado (fixture JSON) → mostra hash/bytes/`nao_provado` por entregável; (c) slug com caractere proibido → exit 2.

### 2. `gravar` — entregáveis, hash, escrita atômica, `nao_provado` obrigatório [tipo: implementar]
atende: D2, D4, D6, D7, D9
arquivos: `scripts/recibo.cjs`, `scripts/testa-recibo-gravar.sh`, `test/fixtures/recibo/**`, `.gitignore`
depende de: 1
paralela: nao

Escopo: `gravar --slug <slug> --nao-provado '<json array>'`. Lê `plano.entregaveis` do estado gravado. Chave ausente ou array vazio → D3: sai **0** sem gravar nada, "sem manifesto — fechar segue sem recibo". Com `entregaveis`: cada caminho resolvido relativo à RAIZ e confinado por `realpath` (a cerca do achado A3 do fluxo 6). Entregável ausente OU fora da árvore nomeia o arquivo e sai **2** (D4, achado 7). `--nao-provado` ausente ou `[]` → sai **2** citando "nao_provado vazio" (D7). Passando as duas: sha256 e `Buffer.byteLength` de cada entregável, monta `{slug, em, entregaveis:[{caminho,sha256,bytes}], nao_provado}` e grava atomicamente (temp+rename) em `.rainforest/colheita/<slug>-recibo.json`, criando o diretório se faltar. `.gitignore` ganha `.rainforest/colheita/` comentado no padrão do bloco existente.

mutacao:
  arquivo: `scripts/recibo.cjs`
  de: entregável ausente (ou fora da árvore via junction) recusa a gravação
  para: entregável ausente é ignorado em silêncio e o recibo grava sem ele
  bateria: `bash scripts/testa-recibo-gravar.sh`
  fixture: plano com `entregaveis` citando arquivo inexistente e, num segundo caso, junction dentro da raiz sandbox apontando para fora (desenho do G20 de `testa-portoes-gate.sh`) — com a mutação os dois gravam recibo "de sucesso" para arquivo que nunca existiu dentro da árvore.

pronto quando: `bash scripts/testa-recibo-gravar.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) sem `entregaveis` → sai 0, nada criado; (b) entregável ausente → sai 2 nomeando o arquivo; (c) entregável via junction para fora → sai 2; (d) `nao_provado` ausente → sai 2; (e) `nao_provado: []` → sai 2; (f) caminho feliz → grava o JSON com sha256 conferido contra hash calculado por fora e bytes corretos; (g) `.gitignore` tem a linha nova.

### 3. `gravar` exige portões re-executados antes de congelar [tipo: implementar]
atende: D5
arquivos: `scripts/recibo.cjs`, `scripts/testa-recibo-portoes.sh`, `test/fixtures/recibo/**`
depende de: 2
paralela: nao

Escopo: dentro do mesmo `gravar`, IMEDIATAMENTE antes de escrever o arquivo final (depois de validar entregáveis e `nao_provado`), se `docs/rainforest/portoes/<slug>.md` existir, invoca `portoes.cjs rodar --reverificar <caminho>` via `spawnSync` com stdio herdado. Exit ≠ 0 cancela a gravação inteira (nenhum arquivo em `.rainforest/colheita/` é tocado nem sobrescrito) e sai **1** — veredito negativo sobre o trabalho, distinto do 2 de D4/D7. Reaproveita `test/fixtures/portoes/scripts/sempre-ok.cjs` e `sempre-falha.cjs`; nenhum oráculo novo.

mutacao:
  arquivo: `scripts/recibo.cjs`
  de: `gravar` invoca `portoes.cjs rodar --reverificar` (RE-executa) quando `portoes.md` existe
  para: `gravar` invoca `portoes.cjs rodar` sem a flag (aceita evidência gravada)
  bateria: `bash scripts/testa-recibo-portoes.sh`
  fixture: `portoes.md` com portão `[x]` cumprido, `EVIDENCIA:` de sucesso, mas `CHECK:` apontando hoje para `sempre-falha.cjs` (espelha G21/G22) — sem a flag `rodar` lê a evidência e pula; com ela, re-executa e reprova.

pronto quando: `bash scripts/testa-recibo-portoes.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) sem `portoes.md` → grava normalmente; (b) `portoes.md` com CHECK que passa → grava; (c) CHECK que falha → sai 1, nenhum recibo criado nem sobrescrito; (d) o caso da evidência velha reprova mesmo com `[x]` e evidência de sucesso gravados.

### 4. `conferir` — re-hash e comparação [tipo: implementar]
atende: D8
arquivos: `scripts/recibo.cjs`, `scripts/testa-recibo-conferir.sh`, `test/fixtures/recibo/**`
depende de: 2
paralela: sim

Escopo: `conferir <slug>`. Sem recibo gravado → sai **2** ("nada para conferir"). Com recibo: para cada entregável, re-lê o arquivo (mesmo confinamento por `realpath`), recalcula sha256+bytes e compara. Tudo batendo → "intacto", sai **0**. Qualquer divergência (hash diferente, arquivo sumiu, tamanho mudou) → sai **1**, nomeando o arquivo e o que mudou.

mutacao:
  arquivo: `scripts/recibo.cjs`
  de: `conferir` recusa (sai 1) quando o sha256 recalculado diverge do gravado
  para: `conferir` só compara o campo `bytes`, ignora o sha256
  bateria: `bash scripts/testa-recibo-conferir.sh`
  fixture: recibo de um entregável, e o entregável editado trocando um caractere por outro do MESMO tamanho — com a mutação, `conferir` aprova um arquivo que mudou de conteúdo.

pronto quando: `bash scripts/testa-recibo-conferir.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) sem recibo → sai 2; (b) intacto → sai 0; (c) entregável editado com tamanho idêntico → sai 1 nomeando o arquivo; (d) entregável removido depois da gravação → sai 1 dizendo que sumiu.

### 5. Encaixe no `fechar` de `estado.cjs` [tipo: implementar]
atende: D1, D3
arquivos: `scripts/estado.cjs`, `scripts/testa-recibo-fechar.sh`
depende de: 2, 3
paralela: nao

Escopo: `conferirFechamento` ganha um branch para `estagio === 'fechar'` que roda **sempre** — é o único gancho que age mesmo sem `portoes.md`, porque a decisão de opt-in mora dentro do `recibo.cjs`. Chama `rodarChecador(RECIBO, ['gravar', '--slug', slug, '--nao-provado', JSON.stringify(extra.nao_provado || [])], estagio)`, empilhando a recusa nas demais (padrão acumulativo do fluxo 6). `RECIBO = path.join(__dirname, 'recibo.cjs')`, com a mesma guarda `fs.existsSync` que `PORTOES` já usa — plugin antigo sem o arquivo não inventa trava.

mutacao:
  arquivo: `scripts/estado.cjs`
  de: `marcar --estagio fechar --status ok` chama `recibo.cjs gravar` e recusa se o exit for ≠ 0
  para: `marcar --estagio fechar --status ok` nunca chama `recibo.cjs`
  bateria: `bash scripts/testa-recibo-fechar.sh`
  fixture: sandbox `RFM_ESTADO_ROOT`, fluxo cujo plano declara `entregaveis` com arquivo inexistente — `marcar fechar ok` deve recusar (exit 2); com a mutação, fecharia normalmente.

pronto quando: `bash scripts/testa-recibo-fechar.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) fluxo sem `plano.entregaveis` fecha `fechar ok` como hoje (D3); (b) `entregaveis` com arquivo ausente → recusa citando o arquivo (D4); (c) `nao_provado` ausente no `--json` do `marcar fechar` → recusa (D7 alcançando o pipeline real, não só o script isolado); (d) caminho feliz → `fechar ok` fecha E `.rainforest/colheita/<slug>-recibo.json` existe depois; (e) com `portoes.md` de CHECK falho → `fechar ok` recusa (D5 alcançando o pipeline); (f) o caso da mutação.

### 6. A regra do exit não-zero, no núcleo [tipo: implementar]
atende: D10
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-12.md`, `skills/rainforest-mind/references/regra-18.md`
depende de: nenhuma
paralela: sim

Escopo: a regra "exit não-zero nunca é descrito como sucesso — nem 'quase passou', nem 'passou com aviso'; o número é a verdade e a prosa se ajusta a ele" entra no núcleo injetado.

**A folga medida é de 3 B** (`nucleo=5597`, teto `5600` em `hooks/lib/contexto-sessao.cjs`). Duas formas de caber, e quem executa escolhe **medindo**, não por preferência:

- **(a) Regra 18 nova**, no formato das 17, com `references/regra-18.md`. Custa um título, um número, um ponteiro de elaboração — e exige cortar de outra regra no mínimo o mesmo tanto.
- **(b) Uma cláusula na regra 12**, que já é "entrega de agente se valida na saída real" e já diz "✅ sem comando e saída colados = não feito". "Exit ≠ 0 não é sucesso" é a mesma família, e uma cláusula custa muito menos bytes que uma regra inteira. A elaboração vai para `references/regra-12.md`, que é a maior (9.277 B, teto 10.500) mas ainda tem folga.

**(b) é a recomendação**, e o motivo é de conteúdo, não de bytes: uma regra 18 separada convida a ler "não narre otimista" como assunto de tom, quando o assunto é evidência — que é exatamente o que a 12 já governa. Se a medição mostrar que (b) não cabe em `regra-12.md`, aí (a) se justifica.

mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: o núcleo com a regra do exit não-zero fica ≤ 5.600 B
  para: remove o corte compensatório — o núcleo estoura o teto
  bateria: `node scripts/medir-skill.cjs && bash hooks/testa-contexto-sessao.sh`
  fixture: a própria medição do `SKILL.md` real. Sem o corte, `medir-skill.cjs` reporta `nucleo` > 5600 e a bateria do contexto reprova citando o estouro.

pronto quando: `node scripts/medir-skill.cjs` mostra `nucleo` ≤ 5600; `bash hooks/testa-contexto-sessao.sh` sai 0; `bash scripts/testa-orcamento.sh` sai 0; e a regra aparece no núcleo **injetado de verdade**, conferido na saída do hook de SessionStart, não só no arquivo fonte.

### 7. Documentação [tipo: docs]
atende: D1, D9
arquivos: `README.md`
depende de: 5, 6
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação — sem comportamento de código para mutar.

Conteúdo: a tabela de travas mecânicas do `README.md`, na vizinhança da linha de `portoes.cjs`, ganha uma linha para `scripts/recibo.cjs`: o que grava e quando (`gravar`, chamado pelo `fechar`), os campos (entregáveis com sha256+bytes, `nao_provado` obrigatório), o opt-in (sem `plano.entregaveis` nada muda), a reverificação dos portões antes de congelar, e o caminho fora do git (D9). A prosa sobre o núcleo ganha a menção à regra do exit não-zero.

pronto quando: o trecho novo responde por leitura semântica onde o recibo mora, quando grava, o que é opt-in e que fica fora do git — nomeando arquivo e comportamento, sem citar número de linha.

### 8. Rastro do fluxo e contrato de bytes [tipo: docs]
atende: D10
arquivos: `docs/rainforest/design/fluxo-7-design-recibo.md`, `hooks/testa-contexto-sessao.sh`, `relatorios/2026-09-02-handover-fila-de-fluxos.md`
depende de: 6
paralela: nao
mutacao: n/a
  motivo: a bateria de contexto muda so a constante D7 (contrato de tamanho exato do nucleo, 5597 -> 5595, consequencia da Tarefa 6) e cinco epochs de fixture reescritos em notacao numerica para o gate de publicacao; os outros dois sao documento.

Emenda de 2026-09-03, no `revisar` (creep medido contra o plano): a seção
`# Design formal` do design (exigida pela checagem `cobertura` do fluxo 6), a
constante `NUCLEO_ESPERADO` e os epochs da bateria de contexto, e o handover que
abriu esta branch já estavam no diff e não cabiam em tarefa nenhuma. Ficam
nomeados aqui para o rastro dizer por que cada um entrou.

pronto quando: `node scripts/medir-skill.cjs` mostra `nucleo=5595` e `bash hooks/testa-contexto-sessao.sh` sai 0 (D7 bate com o núcleo real); `node scripts/conferir-publicacao.cjs hooks/testa-contexto-sessao.sh` sai 0.

## Divergências do design

Nenhuma nova. As três resolvidas em 2026-09-02 (o `colher` inexistente, o caminho velho do `portoes.md`, o verbo `recibo` livre) estão fechadas na seção `# Design formal` e foram reconferidas no fonte antes deste plano.
