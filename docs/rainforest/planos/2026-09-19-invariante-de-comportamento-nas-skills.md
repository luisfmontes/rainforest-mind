# Plano: Invariante de comportamento nas skills de ação, com assertiva negativa

Design: docs/rainforest/design/2026-09-19-invariante-de-comportamento-nas-skills.md

Base: `4f714ef69` (`origin/main` no momento da abertura do fluxo). O hash corrente
se deriva com `git rev-parse`, nunca se copia desta linha.

## O que não pode quebrar

- As 5 invariantes já existentes de `skills/rainforest-mind/` continuam verdes, nas mesmas regras 10, 11, 12, 13 e 15, com o mesmo campo `onde` — quatro delas `["skill","nucleo"]` e a da regra 15 `["skill","referencia","nucleo"]` (corrigido em 2026-09-19: a forma anterior desta linha generalizava a primeira entrada para as cinco).
- `scripts/testa-conferir-invariantes.sh` continua sendo descoberto pelo glob `scripts/testa-*.sh` do `varrer-baterias.sh`, e continua verde em Node 22 e 24.
- Os **seis** blocos de mutação daquela bateria continuam existindo e continuam ficando vermelhos, **cada um sobre a SUA caixa de areia, cuja linha de base sai 0** — asserido por um caso `LINHA DE BASE (n): caixa integra passa antes da mutacao n` imediatamente antes de cada mutação. Os seis são: os cinco numerados `(1)` a `(5)` mais o do degrau desconhecido, `LINHA DE BASE (degrau)`. **Os casos `LINHA DE BASE` são SETE, não seis** — corrigido em 2026-09-20, por achado da OITAVA revisão: o sétimo é `LINHA DE BASE (dup-onde)`, do caso da linha abaixo, que é `# Caso:` e não bloco numerado, mas muta a árvore da `rainforest-mind` do mesmo jeito e por isso assere a sua linha de base. A forma anterior desta linha dizia "asserido pelos **seis** casos", e quem contasse acharia sete.
- A checagem de **ocorrência única** continua tendo caso nos **DOIS** ramos do sensor, `onde` ausente e `onde` presente — asserido por `VERMELHO: deve duplicado reprova com contagem` e por `VERMELHO: deve duplicado no ramo onde reprova com contagem`, acrescentado em 2026-09-20 por achado da OITAVA revisão. Medido na base `f6872939`, antes do caso novo: apagar as sete linhas da checagem do ramo `onde` deixava a bateria em `ok: 29   falhou: 0` — mutante sobrevivente. Com o caso novo, a mesma deleção deixa a bateria em `ok: 30   falhou: 1`, e o vermelho é ele.
- O roster de skills protegidas continua sendo **sete** arquivos `skills/*/invariantes.json` — `executar`, `fechar`, `limpar`, `plano`, `rainforest-mind`, `revisar`, `verificar` — e **15** invariantes conferidas, asserido pelo caso `ROSTER: as skills protegidas continuam as mesmas (7 arquivos, 15 invariantes)`, que roda contra o repositório real. Os dois números e a etiqueta saem de `ROSTER_ESPERADO` e `ROSTER_INVARIANTES`, numa fonte só — até 2026-09-20 eram três strings independentes que se desatualizavam separadas.
- Nenhum `SKILL.md` das seis skills tem o corpo alterado por este trabalho — o que entra é arquivo de invariante ao lado, nunca edição da skill.
- TODA entrada `tipo: "nao_deve"` dos `skills/*/invariantes.json` de produção continua sendo **detectável quando plantada** no corpo da sua skill, asserido pelo caso `VIVACIDADE: toda frase nao_deve de producao e detectavel quando plantada` — acrescentado em 2026-09-20, por achado da SEXTA revisão. A varredura lê os arquivos de produção, então `nao_deve` futuro fica coberto sem caso novo, e **varredura que não acha entrada nenhuma é VERMELHA**. O limite está medido e declarado no comentário do caso: ele prova que o caminho `nao_deve` mede a árvore real, e **não** distingue frase certa de frase com typo — plantada, a grafia errada também sai 2. Essa metade FECHOU em 2026-09-20, e a metade IRMÃ fechou junto, na sétima revisão: o caso `SEGUNDA FONTE: as frases de producao batem com a declaracao` declara em `INVARIANTES_ESPERADAS`, uma vez só e ao lado de `ROSTER_ESPERADO`, o conjunto `(skill, tipo, onde, frase)` das **quinze** invariantes, e exige que ele seja **igual** ao lido de `skills/*/invariantes.json`. A metade irmã era esta: até 2026-09-20 a segunda fonte cobria só a `nao_deve`, e para as catorze `deve` nada fixava **qual** frase era protegida — trocar a frase de um `deve` por `name:`, que é a chave do frontmatter e ocorre uma vez em cada `SKILL.md`, passava a checagem de presença e a de ocorrência única em qualquer skill do roster, e a frase real podia sumir do corpo com o CI verde.
- `node scripts/conferir-livro-de-repos.cjs` continua saindo 0.

> **Linha corrigida em 2026-09-20, por achado da revisão.** A forma anterior
> dizia "Os dois mutantes que aquela bateria já tem continuam existindo e
> continuam ficando vermelhos". Errada nas duas metades. Medido: são **cinco**
> blocos de mutação mais um meta-teste, não dois; e nenhum deles media coisa
> alguma, porque a `$CAIXA` compartilhada copiava `scripts/`, `invariantes.json`,
> `SKILL.md` e `hooks/`, mas **nunca** `skills/rainforest-mind/references/`. A
> invariante da regra 15 exige o degrau `referencia`, então a caixa já saía
> `FALHA invariante [rainforest-mind] regra-15` com **exit 2** antes da primeira
> mutação — e como os cinco blocos só aferem `exit != 0`, todos ficariam
> vermelhos com a mutação sendo no-op. O conserto é copiar `references/` no setup
> e asserir a linha de base antes de mutar.

> **Linha corrigida pela QUINTA vez em 2026-09-20.** A forma anterior dizia
> "os **cinco** blocos … (quatro distintos — o bloco (5) repete o (1)) e o
> meta-teste", e das cinco asserções de linha de base prometidas o meta-teste
> não tinha nenhuma. Duas coisas mudaram, e as duas fecham a mesma classe: o
> meta-teste — bloco (6) — foi **apagado**, porque repetia byte a byte a mutação
> do bloco (4), montava caixa em `/tmp/meta-ref` com caminho fixo em vez de
> `mktemp -d`, engolia a saída com `) > /dev/null 2>&1` e não asseria linha de
> base nenhuma; medido em 2026-09-20 com a cópia de `references/` desligada só
> nele, imprimia `ok META-TESTE` sobre caixa quebrada e a bateria seguia `26/0`.
> E o bloco (5) deixou de repetir o (1): passou a mover a frase da **regra 13**
> (``pelo `ideias.cjs plantar` ``), a única das cinco invariantes da
> `rainforest-mind` que não tinha mutação apontada para ela. Entrou junto um sexto bloco, o do degrau
> desconhecido ao lado de um válido. Agora "CADA bloco de mutação tem a SUA
> caixa e a SUA linha de base" é verdade sem exceção.

> **Linha corrigida de novo em 2026-09-20, por achado da TERCEIRA revisão.** A
> forma imediatamente anterior — a que a nota acima produziu — dizia que os cinco
> blocos ficavam vermelhos "sobre uma caixa de areia cuja linha de base sai 0",
> asserida por um caso único que rodava "entre o setup e a primeira mutação".
> Falso a partir do bloco (2). A `$CAIXA` era criada **uma vez** e nunca
> restaurada: cada bloco rodava sobre a árvore que o anterior estragou, o bloco
> (5) restaurava só o `SKILL.md` e deixava dentro a mutação que o (4) fez em
> `references/regra-15.md`, e a linha de base era medida uma vez só. Medido sem
> aplicar nenhuma das mutações (2) a (5): `LINHA DE BASE exit=0`, `apos (1)
> exit=2`, e então `SEM aplicar (2) exit=2`, `SEM (3) exit=2`, `SEM (4) exit=2`,
> `(5) NAO aplicada exit=2` — quatro dos seis blocos afiravam vermelho de vácuo.
> O vácuo estava fechado só para o primeiro bloco. O conserto é cada bloco montar
> a sua caixa com `nova_caixa_rf` e ter a sua própria asserção de linha de base
> imediatamente antes da mutação.

## Tarefas

### 1. Estender o conferir-invariantes: N skills, `onde` opcional, `nao_deve` e ocorrência única [tipo: implementar]
atende: D2, D3, D4, D5, D8, D11
arquivos: `scripts/conferir-invariantes.cjs`, `scripts/testa-conferir-invariantes.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-invariantes.cjs`
  de: `const proibidaPresente = tipo === 'nao_deve' && corpo.toLowerCase().includes(frase.toLowerCase());`
  para: `const proibidaPresente = false;`
  bateria: `bash scripts/testa-conferir-invariantes.sh`
  fixture: `testa-conferir-invariantes.sh, secao "nao_deve: frase proibida presente no corpo reprova"`
pronto quando: com uma cópia de caixa de areia onde `skills/fechar/invariantes.json` declara `{"frase": "CONFIRMO fechar issue", "tipo": "nao_deve"}` e a string `CONFIRMO fechar issue` foi plantada dentro de `skills/fechar/SKILL.md`, `node scripts/conferir-invariantes.cjs` sai **2** e o stderr contém `fechar` e `CONFIRMO fechar issue`; com a mesma string ausente do corpo, sai **0**; e com um `deve` cuja frase aparece **duas** vezes no corpo, sai **2** citando a contagem — provado por `bash scripts/testa-conferir-invariantes.sh` terminando em `falhou=0`. **E, para a SEGUNDA FONTE**, cinco cenários falsificáveis, cada um numa cópia de caixa de areia da árvore inteira: **(a) RETARGET** — com a frase do `deve` de `skills/revisar/invariantes.json` trocada por `name:`, `node scripts/conferir-invariantes.cjs` continua saindo **0** com `ok: conferidas 15 invariantes` e `bash scripts/testa-conferir-invariantes.sh` fica **VERMELHA** reprovando o caso `SEGUNDA FONTE: as frases de producao batem com a declaracao`; **(b)** o mesmo, agora com `nunca reduz a severidade de um achado` também apagada de `skills/revisar/SKILL.md` — a bateria **continua vermelha**, enquanto na base `eaae2a6f` esse mesmo par saía `ok: conferidas 15 invariantes` e `ok: 29   falhou: 0`; **(c)** invariante nova em produção e não declarada — vermelho, com a recusa nomeando `INVARIANTES_ESPERADAS` e `scripts/testa-conferir-invariantes.sh` e imprimindo a linha pronta para colar; **(d)** invariante declarada que sumiu de produção, e varredura vazia — vermelho, com a linha que falta impressa com `-`; **(e)** `onde` removido da entrada da regra 12 de `skills/rainforest-mind/invariantes.json` — vermelho, enquanto na base `eaae2a6f` isso saía `ok: conferidas 15 invariantes`, exit 0 e `ok: 29   falhou: 0`

> **Alvo da mutação atualizado em 2026-09-20, por achado da revisão.** A forma
> anterior era `de: const proibidaPresente = tipo === 'nao_deve' && corpo.includes(inv.frase);`.
> A revisão achou que o `nao_deve` tinha perdido o `/i` do enxerto citado na D5 —
> `Confirmo fechar issue #12` no corpo passava com exit 0 —, e o conserto trocou
> essa linha por `corpo.toLowerCase().includes(frase.toLowerCase())`. A linha
> antiga deixou de existir no fonte, então manter o `de:` velho faria o
> `conferir-mutacao.cjs` sair **3** (`MUTACAO NAO APLICADA`), que é veredito de
> declaração errada, não de bateria fraca. O `para:` e o `fixture:` não mudam.

> **`pronto quando:` emendado em 2026-09-20, por achado da SÉTIMA revisão.** Duas
> coisas, e a primeira é a que importa. **Nenhum** dos quatro `pronto quando:`
> deste plano cobria o caso `SEGUNDA FONTE`, que é o que fechou o bloqueante da
> rodada 6: o estágio `verificar` não tinha o que executar contra o mecanismo
> entregue, e um critério que não existe não reprova nada. A segunda: a linha de
> "O que não pode quebrar" acima declarava **aberta** a metade que `210a7233`
> tinha fechado — ela foi escrita em `1fbe4769` e não foi tocada pelo commit que
> entregou o fechamento, então o design foi atualizado e o plano não.
>
> O critério novo inclui o cenário do **RETARGET**, que é o achado da sétima
> revisão e o motivo de a segunda fonte ter deixado de valer só para `nao_deve`:
> `name:` ocorre exatamente uma vez em cada um dos sete `SKILL.md` protegidos, e
> com ele no `invariantes.json` a invariante passa a "proteger" a chave do
> frontmatter enquanto a frase real some do corpo com o CI verde. Medido na base
> `eaae2a6f`: `ok: conferidas 15 invariantes`, exit 0, `ok: 29   falhou: 0`.

### 2. Escrever os seis arquivos de invariante das skills de ação [tipo: configurar]
atende: D1, D6, D10
arquivos: `skills/fechar/invariantes.json`, `skills/limpar/invariantes.json`, `skills/executar/invariantes.json`, `skills/revisar/invariantes.json`, `skills/verificar/invariantes.json`, `skills/plano/invariantes.json`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/limpar/SKILL.md`
  de: `**Nunca entra na remoção**`
  para: `**Entra na remoção**`
  bateria: `bash scripts/testa-conferir-invariantes.sh`
  fixture: `testa-conferir-invariantes.sh, caso "repositorio integro passa no conferir"`
pronto quando: com os seis arquivos na árvore e nenhum `SKILL.md` alterado, `node scripts/conferir-invariantes.cjs` sai **0** e relata **15** invariantes conferidas (as 5 da `rainforest-mind` mais as 10 aprovadas); e com a frase `Nunca entra na remoção` removida de `skills/limpar/SKILL.md` numa cópia de caixa de areia, sai **2** nomeando `limpar` — provado por `bash scripts/testa-conferir-invariantes.sh` terminando em `falhou=0`

> **Fixture emendado em 2026-09-20, por achado da revisão.** A forma anterior
> nomeava o caso `skill de acao: frase obrigatoria removida do corpo reprova`.
> Medido rodando `node scripts/conferir-mutacao.cjs` com esta mutação: aquele
> caso **não detecta** — ele aborta no próprio setup, imprimindo `Nao achei a
> frase Nunca entra na remoção` e `FALHA: nao consegui aplicar mutacao na
> limpar`, porque a mutação externa já tinha removido a frase que ele precisava
> remover. Aborto de setup não é detecção. Quem fica vermelho é o caso nomeado
> no `fixture:` acima, e o motivo é estrutural: a mutação é aplicada na árvore
> inteira, e o caso que roda o checador contra a árvore real alcança exatamente
> o ramo que o invariante protege — `deve` cuja frase sumiu do corpo, exit 2.
> Caso de caixa de areia que muta a mesma frase X colide com a mutação externa
> de X e não serve de fixture para ela.

As dez frases aprovadas pelo usuário em 2026-09-19, sem corte, estão na tabela
"Frases propostas" do design. Nenhuma delas usa `--confirmo` como frase de
`nao_deve`, pela D6: o token é obrigatório no `limpar` e aparece dentro da
própria frase que o proíbe no `fechar`.

### 3. Migrar as 5 invariantes da rainforest-mind para o formato novo [tipo: configurar]
atende: D7
arquivos: `skills/rainforest-mind/invariantes.json`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: `3.000+ tokens`
  para: `3.000 tokens`
  bateria: `bash scripts/testa-conferir-invariantes.sh`
  fixture: `testa-conferir-invariantes.sh, caso "repositorio integro passa no conferir"`
pronto quando: o arquivo é **byte a byte idêntico** ao da base — `git hash-object skills/rainforest-mind/invariantes.json` devolve o mesmo blob que `git rev-parse <base>:skills/rainforest-mind/invariantes.json` — e `node scripts/conferir-invariantes.cjs` passa a conferir **15** invariantes lendo esse arquivo pelo **mesmo caminho genérico** das outras seis, sem caso especial no código (`SKILLS_DIR` + `readdirSync`, conferível por `grep -n "rainforest-mind" scripts/conferir-invariantes.cjs` não casando nada fora de comentário); com `3.000+ tokens` trocado por `3.000 tokens` em `skills/rainforest-mind/SKILL.md`, a bateria fica **vermelha** — provado por `node scripts/conferir-mutacao.cjs` saindo **0**

> **Critério emendado em 2026-09-19, durante o `executar`.** A forma anterior
> exigia que as cinco entradas mantivessem `onde: ["skill","nucleo"]`. Errado:
> a entrada da regra 15 sempre teve um terceiro valor, `"referencia"`, e o
> critério foi escrito olhando só a primeira entrada do arquivo. Erro de quem
> escreveu o plano, não da entrega. A emenda também troca a exigência de
> "arquivo migrado" por "arquivo idêntico": a tarefa 1 generalizou o caminho de
> leitura, então a migração da D7 aconteceu no **código**, e editar o JSON só
> para parecer migrado seria churn. A prova de que os dois formatos deixaram de
> conviver é o caminho único de leitura, não uma edição no dado.

> **Fixture emendado em 2026-09-20, por achado da revisão.** A forma anterior
> nomeava o caso `(1) MUTACAO: mover a frase "3.000+ tokens" para DEPOIS de <!-- detalhe --> no SKILL.md`.
> Medido rodando `node scripts/conferir-mutacao.cjs` com esta mutação: aquele caso **não detecta** — ele aborta no próprio setup,
> com `FALHA: nao consegui aplicar a primeira mutacao`, porque a mutação externa
> já tinha alterado a frase que ele precisava mover. Aborto de setup não é
> detecção. Quem fica vermelho é o caso nomeado no `fixture:` acima, e o motivo
> é estrutural: a mutação é aplicada na árvore inteira, e o caso que roda o
> checador contra a árvore real alcança exatamente o ramo que o invariante
> protege — `deve` cuja frase sumiu do corpo, exit 2. Caso de caixa de areia que
> muta a mesma frase X colide com a mutação externa de X e não serve de fixture
> para ela.

### 4. Registrar o openai-developers-for-claude no livro de repos [tipo: docs]
atende: D9
arquivos: `vigias/livro-de-repos.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: linha de tabela num documento de registro — não há comportamento a inverter. A falsificação dela é outra e está no critério: a sintaxe da célula é validada por peça marcada `sensor`, e o conteúdo tem de casar com o que foi medido no repo de terceiro.
pronto quando: com a linha nova na tabela "Avaliados", `node scripts/conferir-livro-de-repos.cjs` sai **0** e a tabela passa de **51** linhas de dado na base para **52** — contadas por `awk '/^## Avaliados/{f=1;next} /^## /{f=0} f&&/^\|/{n++} END{print n-2}' vigias/livro-de-repos.md`, que desconta cabeçalho e separador. **Dois dados da célula têm segunda fonte e se conferem contra o design**: a trilha `Enxertar: enxerta`, que está na D9, e a âncora `gate-do-p1-e-hook-nao-texto`, que está no cabeçalho e na seção "Objetivo". **Os outros dois são fonte única**: o último push `2026-07-13` e a licença `Apache-2.0` — esta registrada como fato e não como veredito — foram medidos do repositório de terceiro em 2026-09-19 e **não existem no design**; conferi-los exige abrir `openai/openai-developers-for-claude`, não o design. Acrescentá-los ao design para "fechar" o cruzamento seria fabricar segunda fonte a partir da mesma medição.

> **Critério emendado em 2026-09-20, por achado da revisão.** A forma anterior
> terminava em "conferido lendo a célula contra a seção 'Objetivo' do design,
> que traz os mesmos quatro dados". Falso, e falso de um jeito que torna o
> critério inexecutável: medido no design, `Enxertar: enxerta` aparece 1 vez e
> `gate-do-p1-e-hook-nao-texto` 2 vezes, mas o último push e a licença aparecem
> **0** vezes. Metade do cruzamento prometido não tinha como ser feita. O
> conserto é o critério dizer o que tem duas fontes e o que tem uma, não o
> design ganhar o dado que faltava.

## Nota sobre a ordem

As tarefas 1 e 4 são paralelas entre si: tocam árvores disjuntas
(`scripts/` contra `vigias/`) e nenhuma lê o resultado da outra. As tarefas 2 e
3 dependem da 1 porque seus critérios rodam o checador com o formato novo — sem
a tarefa 1 na árvore, o `onde` ausente e o campo `tipo` são campo desconhecido,
não formato aceito.

A tarefa 3 vem depois da 2 na numeração, mas não depende dela: as duas dependem
só da 1. A ordem entre elas é indiferente e foi fixada para manter a leitura do
plano linear.
