# Plano: Skills finas com references

Design: docs/rainforest/design/2026-08-24-skills-finas-com-references.md

## O que não pode quebrar

> **Referência aqui é por símbolo, não por linha.** A redação original desta seção citava
> `arquivo:linha`, e a terceira revisão independente achou **três** ponteiros já mortos —
> as próprias tarefas 4 e 5 inseriram 402 linhas em `testa-contexto-sessao.sh` e empurraram
> tudo para baixo. Número de linha em documento apodrece por construção; nome de símbolo,
> não. Corrigido em 2026-08-24 tirando os números, não atualizando-os.

- **Os núcleos injetados não mudam um byte.** Medição de referência, com o parser real:
  `nucleos bytes = 5593`, `regras contadas = 17`. A folga sobre `NUCLEOS_MAX_BYTES` é de
  7 B — qualquer texto que escorregue para antes de um `<!-- detalhe -->` derruba a suíte.
  (A tarefa 2 baixou o núcleo para **5.589 B** ao tirar o `↳` literal da regra 15, e a
  folga subiu para 11 B. É queda esperada e autorizada pela D6, não regressão.)
- **O literal `## As regras` continua no `SKILL.md`.** Verificado por mutação: trocá-lo
  zera o payload de núcleo e a sessão sobe com "FALHA AO CARREGAR AS REGRAS".
- **O formato de início de regra continua** para as 17 — é o lookahead da constante
  `INICIO_REGRA`, em `hooks/lib/contexto-sessao.cjs`, e a contagem é a asserção
  `as 17 regras cabem no orcamento`, em `hooks/testa-contexto-sessao.sh`.
- **A linha `Última revisão:` continua no `SKILL.md`.** Lida por `hooks/foco-session-start.cjs`
  num `if` sem `else` — sair dali desliga o aviso bimestral em silêncio.
- **A seção `## Comando /foco` continua no `SKILL.md`.** Não é estrutural para o tamanho
  (mutá-la devolve o mesmo número de bytes de núcleo), mas o teste de mutação da catraca de
  núcleos, em `hooks/testa-contexto-sessao.sh`, usa o literal `## Comando` como ponto de
  injeção da regra gorda.
- **Todo arquivo novo nasce em LF, UTF-8 sem BOM.** Dois mecanismos, e eles não são
  duplicata: o **preflight** de `.github/workflows/baterias.yml` roda
  `git ls-files --eol skills hooks` — só essas duas pastas —, e `scripts/conferir-encoding.cjs`
  varre a lista **inteira** de arquivos rastreados, cobrindo o que o preflight deixa de
  fora. A redação original desta linha atribuía ao script o escopo estreito do preflight;
  o erro veio de eu ler o relato de um agente, que citava a linha do comentário onde o
  preflight é **descrito**, e tomá-lo como o comportamento do script.

## Tarefas

### 1. Extrair as 17 elaborações para `references/` e deixar o ponteiro no lugar [tipo: implementar]
atende: D1, D2, D3, D5
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-01.md`, `skills/rainforest-mind/references/regra-02.md`, `skills/rainforest-mind/references/regra-03.md`, `skills/rainforest-mind/references/regra-04.md`, `skills/rainforest-mind/references/regra-05.md`, `skills/rainforest-mind/references/regra-06.md`, `skills/rainforest-mind/references/regra-07.md`, `skills/rainforest-mind/references/regra-08.md`, `skills/rainforest-mind/references/regra-09.md`, `skills/rainforest-mind/references/regra-10.md`, `skills/rainforest-mind/references/regra-11.md`, `skills/rainforest-mind/references/regra-12.md`, `skills/rainforest-mind/references/regra-13.md`, `skills/rainforest-mind/references/regra-14.md`, `skills/rainforest-mind/references/regra-15.md`, `skills/rainforest-mind/references/regra-16.md`, `skills/rainforest-mind/references/regra-17.md`, `scripts/medir-skill.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: a elaboração da regra 12 mora em `references/regra-12.md`, e o `SKILL.md` tem só a linha de ponteiro
  para: a elaboração da regra 12 colada de volta no `SKILL.md`, logo depois do `<!-- detalhe -->`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: a catraca de tamanho do `SKILL.md` criada na tarefa 4 — o arquivo passaria de 11.000 B
pronto quando: com o `SKILL.md` real do repositório, o parser devolve exatamente os mesmos 5.593 B de núcleo e as mesmas 17 regras que devolve hoje, e a pasta tem 17 arquivos com numeração zero-padded de `regra-01` a `regra-17` — provado por `node scripts/medir-skill.cjs` devolvendo `nucleo=5593 regras=17 references=17`

### 2. Tirar o `↳` literal do fim do núcleo da regra 15 [tipo: implementar]
atende: D6
arquivos: `skills/rainforest-mind/SKILL.md`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: o núcleo da regra 15 termina em `nunca dump filtrado.` sem seta
  para: o núcleo da regra 15 termina em `nunca dump filtrado. ↳`, com a seta literal de volta
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: a asserção de seta única criada na tarefa 5
pronto quando: com o `SKILL.md` real, o núcleo emitido pelo parser não contém nenhuma seta dupla — provado por `node scripts/medir-skill.cjs` devolvendo `setas-duplas=0`

### 3. Trocar o texto do contrato: consultar deixa de ser carregar a skill [tipo: implementar]
atende: D4
arquivos: `hooks/lib/contexto-sessao.cjs`, `scripts/ponte.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: o cabeçalho manda ler o arquivo da regra e interpola o caminho da pasta `references/`
  para: o cabeçalho volta a mandar carregar a skill inteira, com o caminho do `SKILL.md`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: a asserção de cabeçalho criada na tarefa 5
pronto quando: com o JSON de SessionStart que o harness realmente envia no stdin — `session_id`, `cwd`, `hook_event_name`, `source`, e nenhum campo inventado —, o `additionalContext` emitido cita o caminho da pasta `references/` e não manda mais carregar a skill inteira, e o payload continua abaixo de `ORCAMENTO_BYTES` — provado por `bash hooks/testa-contexto-sessao.sh` saindo 0 com as asserções de cabeçalho e de teto verdes

### 4. Catraca de tamanho: o custo de consulta vira número vigiado [tipo: teste]
atende: D9
arquivos: `hooks/testa-contexto-sessao.sh`, `hooks/lib/contexto-sessao.cjs`, `scripts/medir-skill.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: `REFERENCE_MAX_BYTES: 10500`
  para: `REFERENCE_MAX_BYTES: 99000`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: o teste de mutação da própria catraca, que engorda `references/regra-12.md` em 3.000 B e exige que a suíte acuse
pronto quando: com os arquivos reais de `references/`, a suíte mede o maior deles contra 10.500 B e o `SKILL.md` contra 11.000 B, e engordar `regra-12.md` em 3.000 B faz a suíte falhar citando `regra-12.md` pelo nome na mensagem — provado por `bash hooks/testa-contexto-sessao.sh` saindo 0 antes da engorda, e saindo diferente de 0 com `regra-12.md` na saída depois dela

### 5. Travas da quebra: seta única, literais estruturais e núcleo inalterado [tipo: teste]
atende: D4, D5, D6, D7
arquivos: `hooks/testa-contexto-sessao.sh`
depende de: 1, 2, 3
paralela: nao
mutacao:
  arquivo: `hooks/testa-contexto-sessao.sh`
  de: `const setasDuplas = (nucleo.match(/↳\s↳/g) || []).length;` — a linha que MEDE a seta dupla
  para: `const setasDuplas = 0;` — a medição fica cega
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: a sabotagem 7, que devolve o `↳` literal ao núcleo da regra 15 numa cópia e exige que a medição acuse `setas-duplas=1`
  corrigido em 2026-08-24, na integração: o alvo declarado originalmente era "a asserção que exige zero ocorrências, aceitando qualquer quantidade". Rodado, deu **exit 2 (bateria VERDE)** — e o motivo não era a bateria ser fraca. A sabotagem 7 guarda a **medição**, não o operador de comparação da asserção; nenhuma das 233 asserções desta suíte é guardada contra si mesma, e essa é a norma do arquivo, não um defeito desta entrega. Mirar na medição devolveu **exit 0 (vermelha)**. Falsificar tarefa de teste é cegar o que ela mede, não afrouxar o `if` que lê a medida.
pronto quando: com o `SKILL.md` real, a suíte afirma as quatro invariantes — zero setas duplas, 5.593 B de núcleo, `## As regras` presente, e o cabeçalho citando `references/` — e mutar cada uma delas no arquivo real deixa a suíte vermelha pela asserção correspondente, nomeada na saída — provado por `bash hooks/testa-contexto-sessao.sh` saindo 0, e por cada uma das quatro mutações produzindo o nome da sua asserção na saída de falha

### 6. O gate de orçamento agregado ignora `references/` [tipo: teste]
atende: D8
arquivos: `scripts/testa-orcamento.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/orcamento.cjs`
  de: `const skillMd = path.join(skillsDir, dir.name, 'SKILL.md');`
  para: uma varredura recursiva de markdown dentro de `skills/<dir>/`, que passaria a somar os arquivos de `references/`
  bateria: `bash scripts/testa-orcamento.sh`
  fixture: a asserção que compara o total agregado com e sem a pasta `references/` presente, exigindo que os dois sejam iguais
pronto quando: com os 17 arquivos reais em `references/`, o total agregado medido pelo `orcamento.cjs` é idêntico ao total medido com a pasta ausente — provado por `bash scripts/testa-orcamento.sh` saindo 0 **com a raiz de dados neutralizada** (`RFM_ROOT` apontando para pasta vazia, que é a condição do runner de CI), e com a asserção de igualdade nomeada na saída
corrigido em 2026-08-24, depois de a revisão independente reprovar por este critério: a redação original também exigia "continua abaixo do teto de 14.000 B", medido com a raiz de dados **do desenvolvedor**. Isso é inalcançável aqui e não por causa desta entrega — o agregado já estava em 14.220 B na base, estouro de +220 B que vem do `FOCO.md` e do radar de sessões da máquina, não de conteúdo versionado (medido: 13.294 B com a raiz neutra). É a issue #81, e ela é dona desse número. O critério agora mede o **repositório** em vez da mesa. O que esta entrega devia a esse orçamento — os 86 B que a tarefa 7 acrescentou ao `description` — foi devolvido na rodada de conserto, para que a entrega seja neutra sobre um teto que ela não quebrou.

### 7. Acertar o `description` da skill e o ponteiro do `ponte.cjs` [tipo: docs]
atende: D3, D4
arquivos: `skills/rainforest-mind/SKILL.md`, `scripts/ponte.cjs`, `README.md`, `scripts/medir-skill.cjs`
depende de: 1, 4
paralela: nao
mutacao: n/a
  motivo: é texto de interface, não comportamento — não há ramo a inverter. A falsificação dela é de coerência e está no critério de pronto: o número do texto tem de casar com os bytes medidos no arquivo real, e a prescrição do texto tem de ser a que a tarefa 3 implementou, não uma frase que se satisfaça sendo digitada.
pronto quando: o custo citado no `description` do `SKILL.md` casa, dentro de 10%, com o tamanho real do arquivo depois da quebra, e o texto que o `ponte.cjs` grava manda ler o arquivo da regra em vez de `skills/rainforest-mind/SKILL.md` — provado por `node scripts/medir-skill.cjs --conferir-description` devolvendo `ok`, e por `node scripts/ponte.cjs` gerando um `AGENTS.md` cujo bloco de contrato cita `references/` e não cita mais o `SKILL.md` como destino de leitura

### 8. As outras skills param de mandar carregar a skill [tipo: docs]
atende: D4
arquivos: `skills/executar/SKILL.md`, `skills/verificar/SKILL.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: texto de instrução em skill, sem ramo a inverter. A falsificação é de coerência e está no critério de pronto: a varredura do repositório inteiro é mecânica e não se satisfaz digitando trecho nenhum.
pronto quando: uma varredura de todos os arquivos rastreados não acha nenhum texto **afirmando como mecanismo atual** que se carrega `Skill(rainforest-mind)` para consultar a elaboração de uma regra, ou que a elaboração mora no `SKILL.md` — provado por `git grep -n -e 'carregue .Skill(rainforest-mind)' -e 'carrega sob demanda' -e 'elaboração continua no SKILL' -- ':!docs/rainforest/' | grep -vE ':[0-9]+:> '` devolvendo saída vazia

Duas exclusões, e as duas são de categoria, não de conveniência. **`docs/rainforest/`** guarda os artefatos do fluxo — design, plano, estado —, que registram a decisão no instante em que foi tomada e descrevem o estado anterior de propósito; tratá-los como spec viva confunde histórico com contrato. E **linha de blockquote** (`> `) é incidente datado citado literalmente: `skills/rainforest-mind/references/regra-16.md` conta o estouro de 2026-08-10 reproduzindo o que foi explicado naquele dia, e reescrever a citação para o mecanismo de hoje falsificaria o registro. O critério mede o que o repositório **afirma**, não o que ele **relata ter afirmado**.

**Tarefa acrescentada em 2026-08-24**, na terceira rodada de conserto, porque a varredura do achado principal encontrou a mesma frase obsoleta em duas skills que **nenhuma tarefa deste plano declarava tocar** — `skills/executar/SKILL.md` e `skills/verificar/SKILL.md`. Isso é creep pela definição da skill `revisar`: arquivo no diff que não casa com nenhum `arquivos:`. A saída registrada para creep é emendar o plano com a tarefa que faltava, e não justificar em prosa que "era necessário" — é a emenda que deixa o rastro de que o escopo cresceu conscientemente. As duas skills mandavam carregar a skill inteira para ler a regra 12, exatamente o que a D4 eliminou; deixá-las como estavam faria o plugin distribuir instrução que contradiz o próprio mecanismo.
