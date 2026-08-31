# Plano: a ponte ganha o bloco do projeto (entrevista + varredura), e o setup declara integrações opcionais

Design: docs/rainforest/design/2026-08-28-ponte-bloco-do-projeto-e-integracoes.md

**Achados que o briefing não tinha, e que mudam onde este plano mexe** (checados por leitura, não por suposição):

1. **`skills/ponte/SKILL.md` não existe.** CONFIRMADO — só existe `commands/ponte.md`, um comando leve sem `Carregue Skill(...)`. Comparado com `commands/setup.md:6`, essa é a convenção do repo para comando que delega método a uma skill — e a ponte nunca ganhou a sua. O método de entrevista que D1 pede é hoje só o do `/brainstorm`. Este plano **cria** `skills/ponte/SKILL.md`.
2. **O hook de abertura não faz "GET `http://localhost:3005/api`".** CONFIRMADO por `hooks/foco-session-start.cjs:100-159`: é `net.createConnection` (TCP puro) contra host/porta de `WHATSAPP_API_BASE_URL`, e só quando a env var está declarada. Não derruba a Q1 fechada (loopback aceito) — mas a checagem nova (Tarefa 7) segue a letra da Q1 (GET HTTP) e **respeita `WHATSAPP_API_BASE_URL` quando declarada**, sem travar cego em `localhost:3005`. Decisão técnica, assumida.
3. **`C:/Projetos/whatsapp-mcp` e `C:/Projetos/sabia` são fatos desta máquina, não do plugin.** Caminho fixo não entra em código compartilhado; o mecanismo genérico é o `projetos.json` por slug (`hooks/lib/projetos.cjs`) — é o que a Tarefa 8 usa para `sabia`. Para `whatsapp-mcp` não há caminho a generalizar (a checagem é só a porta).
4. **`scripts/ponte.cjs` e `scripts/conferir-ponte.cjs` têm o mesmo `corpo()` colado palavra por palavra** — e `scripts/conferir-ponte.cjs:148` referencia `CODIGO_ROOT`, que nunca é declarado ali (`ReferenceError` engolido pelo catch de `raizDeDados()`). Hoje dois defeitos se cancelam (o `dados` sai `null` e `ponte.cjs` nunca usa o parâmetro); qualquer um corrigido sozinho faria a catraca acusar "editado à mão" em toda ponte gerada. Como o plano precisa mexer em `corpo()` dos dois, a Tarefa 1 deduplica antes de acrescentar.

## O que não pode quebrar

- **Os blocos de regras já gerados continuam regeneráveis e a catraca do `conferir-ponte.cjs` mantém os mesmos 4 vereditos para o bloco de regras.** A extração do `corpo()` (Tarefa 1) e o segundo bloco (Tarefas 4/5) não mudam hash, texto nem comportamento do bloco `rainforest-mind:inicio`/`fim` existente.
- **`ponte.cjs --alvo <dir> --aplicar` continua idêntico para quem nunca rodou `--entrevistar`.** Sem `docs/rainforest/projeto.md` no alvo, o bloco de projeto não entra — nenhuma pergunta, nenhum erro, nenhuma linha a mais.
- **`/saude` sem nenhuma `integracao-*` ligada não ganha item nenhum de integração** — no `--json`, nenhum achado com `item` começando em `integracao`.
- **Nenhuma checagem de integração faz rede externa** — só loopback (`127.0.0.1`/`localhost`, ou o que `WHATSAPP_API_BASE_URL` declarar) e leitura de disco/`projetos.json`. `integracao-sabia` não roda `sabia.py doutor` por padrão (checagem rasa — o `/saude` é barato de propósito).
- **Integração declarada e quebrada é sempre `aviso`, nunca `alerta`** — não muda o exit code de `/saude` de 0 para 1 (D4).
- **Nada é gravado fora de `--aplicar` explícito** — ensaio continua sem gravar.
- **`docs/rainforest/projeto.md` e os blocos gerados nunca chumbam caminho de home nem credencial.**
- **As chaves existentes de `hooks/lib/config.cjs` não mudam padrão nem descrição.**

## Tarefas

### 1. Extrai `corpo()`/`raizDeDados()` duplicados para `hooks/lib/ponte-corpo.cjs`, conserta o `CODIGO_ROOT` quebrado [tipo: implementar]
atende: D2
arquivos: `hooks/lib/ponte-corpo.cjs`, `scripts/ponte.cjs`, `scripts/conferir-ponte.cjs`, `scripts/testa-ponte.sh`, `scripts/testa-conferir-ponte.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/ponte-corpo.cjs`
  de: a condicional do aviso de pasta de dados ausente (movida de `conferir-ponte.cjs:225` para o módulo novo)
  para: string vazia fixa (nunca avisa a ausência da pasta de dados)
  bateria: `bash scripts/testa-ponte.sh`
  fixture: o caso "mas ENSINA a descobrir" de `scripts/testa-ponte.sh` (linha ~106)
pronto quando: `scripts/ponte.cjs` e `scripts/conferir-ponte.cjs` chamam a MESMA função `corpo()` de `hooks/lib/ponte-corpo.cjs` (provado gerando o mesmo `AGENTS.md` pelos dois caminhos e comparando byte a byte); `raizDeDados()` do módulo novo, com `RFM_ROOT` fixture real, devolve o caminho de verdade — não `null` por `ReferenceError` engolido — provado chamando a função direto; e `bash scripts/testa-ponte.sh` + `bash scripts/testa-conferir-ponte.sh` continuam 100% verdes após a extração

### 2. Varredura pura do repositório alvo — `ponte.cjs --entrevistar --varredura` [tipo: implementar]
atende: D1
arquivos: `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: a detecção de stack Node por `package.json` dentro de `varrerRepositorio`
  para: `false` fixo
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso "detecta stack Node por package.json real, com scripts.test e scripts.build"
pronto quando: rodando `node scripts/ponte.cjs --entrevistar --varredura --alvo <repo fixture>` — com `package.json` (com `scripts.test`/`scripts.build`) e `.github/workflows/ci.yml` reais no fixture — a saída JSON nomeia `node`/`npm`, lista literalmente os comandos de `scripts.test` e `scripts.build` do fixture, e lista os diretórios de primeiro nível (ignorando `.git`/`node_modules`) — provado por `node -e` com `JSON.parse` comparando campo a campo; nada é escrito em disco (prova: `projeto.md` não existe no alvo depois)

### 3. Grava `projeto.md` atomicamente — `ponte.cjs --entrevistar --gravar --respostas <arquivo> --aplicar` [tipo: implementar]
atende: D1
arquivos: `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: o `fs.renameSync` que promove o `.tmp` a `projeto.md`
  para: linha comentada (a escrita para em `.tmp`, nunca promovida)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso "grava projeto.md atomicamente, e nao pela metade"
pronto quando: com um `--respostas` fixture (4 respostas de Q numeradas: o que é "pronto" aqui, o que não se toca, convenção não escrita, política de revisão) e `--alvo` fixture, `--aplicar` cria `docs/rainforest/projeto.md` contendo as 4 respostas literais E os 3 fatos da varredura (stack, comando de teste, layout) — provado por grep de cada um dos 7 textos; sem `--aplicar`, nada é criado (ensaio); a mutação prova que `projeto.md` pela metade não sobrevive — só o `.tmp` órfão

### 4. Bloco `rainforest-mind:projeto` no `corpo()`/`escrever()` compartilhado [tipo: implementar]
atende: D2
arquivos: `hooks/lib/ponte-corpo.cjs`, `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: `blocoProjetoComHash ? ` + "`" + `${marcado}\n${blocoProjetoComHash}\n` + "`" + ` : marcado` (a condição do `escrever()` que decide incluir o bloco quando `projeto.md` existe — movida do `corpo()` para cá pela T5, que pôs hash no marcador)
  para: `marcado` (nunca inclui o bloco)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso "bloco de projeto aparece quando ha projeto.md no alvo, e some quando nao ha" (caso i)
pronto quando: gerando a ponte num alvo COM `docs/rainforest/projeto.md` fixture, o `AGENTS.md` tem os dois pares de marcador (regras + `rainforest-mind:projeto:inicio`/`fim`) e o bloco de projeto é o conteúdo REAL do fixture (grep do texto, não só do marcador); no MESMO alvo SEM `projeto.md`, só o primeiro par aparece (grep negativo); regenerar duas vezes não duplica marcador (contagem = 1 cada); e o bloco de projeto é byte-idêntico entre `CLAUDE.md`, `AGENTS.md` e `GEMINI.md` gerados do mesmo `projeto.md` (D2: só o bloco de regras varia por host)

### 5. `conferir-ponte.cjs` estende a catraca para o bloco de projeto [tipo: implementar]
atende: D2
arquivos: `scripts/conferir-ponte.cjs`, `scripts/testa-ponte-entrevista.sh`, `hooks/lib/ponte-corpo.cjs`, `scripts/ponte.cjs`
depende de: 1, 4
paralela: nao
mutacao:
  arquivo: `scripts/conferir-ponte.cjs`
  de: a comparação de hash do bloco `rainforest-mind:projeto` contra o hash de `docs/rainforest/projeto.md`
  para: sempre `true` (a checagem nunca acusa)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso "bloco de projeto editado a mao e detectado, sem confundir com o bloco de regras"
pronto quando: editando à mão uma linha DENTRO do bloco de projeto (regras intactas), `conferir-ponte.cjs` sai RECUSADO citando a linha divergente do bloco de PROJETO; regenerando o `projeto.md` fonte sem regerar o `AGENTS.md`, acusa "ficou para trás" nomeando o bloco de projeto; com os dois em dia sai CONFERIDO; e arquivo só com o bloco de regras (sem entrevista) continua CONFERIDO — não ter entrevistado não é erro

### 6. Registro de integrações + toggles no setup [tipo: implementar]
atende: D3
arquivos: `hooks/lib/integracoes.cjs`, `hooks/lib/config.cjs`, `scripts/setup.cjs`, `scripts/testa-setup.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/config.cjs`
  de: a entrada `integracao-whatsapp-mcp` inteira do objeto de chaves
  para: entrada removida
  bateria: `bash scripts/testa-setup.sh`
  fixture: bloco novo "INTEGRACOES: declaravel, desligada por padrao" em `scripts/testa-setup.sh`, no padrão do bloco 5 (PONTES)
pronto quando: `node scripts/setup.cjs` (nada ligado) mostra a seção `INTEGRACOES` com `integracao-whatsapp-mcp` e `integracao-sabia` DESLIGADAS, cada uma com descrição de uma linha sem caminho desta máquina; `--ligar integracao-sabia --escopo usuario` liga só ela; e a mutação faz `integracao-whatsapp-mcp` sumir da seção sem afetar a outra

### 7. Checagem de `whatsapp-mcp` — loopback, sem rede externa [tipo: implementar]
atende: D4
arquivos: `hooks/lib/integracoes.cjs`, `scripts/testa-integracoes.sh`
depende de: 6
paralela: nao
mutacao:
  arquivo: `hooks/lib/integracoes.cjs`
  de: a linha que decide "bridge de pé" no `checar` do whatsapp-mcp
  para: a decisão invertida
  bateria: `bash scripts/testa-integracoes.sh`
  fixture: um `http.createServer` de teste em `127.0.0.1:<porta livre>`
pronto quando: com o servidor fixture no ar e `WHATSAPP_API_BASE_URL` apontando para ele, `checar()` devolve ok; derrubando o servidor, devolve não-ok com `acao` citando "suba a bridge no repositório local"; SEM a env var mas com o fixture em `127.0.0.1:3005`, também ok (o default) — os três chamando `checar()` direto via `node -e`; nenhuma chamada sai de loopback (o host usado nunca difere de `127.0.0.1`/`localhost`)

### 8. Checagem de `sabia` — existência via `projetos.json` [tipo: implementar]
atende: D4
arquivos: `hooks/lib/integracoes.cjs`, `scripts/testa-integracoes.sh`
depende de: 6
paralela: nao
mutacao:
  arquivo: `hooks/lib/integracoes.cjs`
  de: a checagem de existência da `.venv` no `checar` do sabia
  para: `true` fixo
  bateria: `bash scripts/testa-integracoes.sh`
  fixture: pasta fixture com `sabia.py` e `.venv/`, e uma segunda sem `.venv/`
pronto quando: com `projetos.json` fixture registrando `sabia` → pasta que TEM `sabia.py` e `.venv/`, `checar()` devolve ok "presente" (sem rodar `doutor`); apagando só a `.venv/`, devolve não-ok citando `python -m venv .venv && .venv/Scripts/pip install -r requirements.txt`; sem o slug registrado, devolve não-ok citando o registro via setup — os três chamando `checar()` direto com a raiz no fixture

### 9. `/saude` só confere o que foi declarado [tipo: implementar]
atende: D4
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: 7, 8
paralela: nao
mutacao:
  arquivo: `scripts/saude.cjs`
  de: o `aviso(...)` da nova `checarIntegracoes`
  para: `alerta(...)` com os mesmos argumentos
  bateria: `bash scripts/testa-saude.sh`
  fixture: ambiente fixture com `integracao-sabia` ligada e a pasta do sabia sem `.venv`
pronto quando: `saude.cjs --json` SEM integração ligada não tem item com `item` começando em `integracao`; ligando `integracao-sabia` no fixture quebrado, aparece exatamente uma linha `aviso` para `integracao sabia` com a ação na linha seguinte (layout do painel), e o exit segue 0; a mutação faz o mesmo cenário virar `alerta` E exit 1 — provando que o teste mede o nível, não só a presença

### 10. `skills/ponte/SKILL.md` — o método da entrevista, e a ponte com `commands/ponte.md` [tipo: docs]
atende: D1
arquivos: `skills/ponte/SKILL.md`, `commands/ponte.md`, `scripts/testa-ponte-entrevista.sh`
depende de: 2, 3
paralela: nao
mutacao: n/a
  motivo: documento de método sem lógica executável própria; a prova de não-divergência com o código é EXECUÇÃO real dos exemplos citados (abaixo), não mutação
pronto quando: `skills/ponte/SKILL.md` traz um bloco de exemplos de linha de comando e um caso na bateria `scripts/testa-ponte-entrevista.sh` EXTRAI cada linha desse bloco e a EXECUTA contra um fixture, exigindo exit 0 — execução, não grep; quem lê o arquivo inteiro sabe, sem abrir outro, que a varredura roda ANTES de qualquer pergunta (regra 16), que o aprovado grava em `docs/rainforest/projeto.md` no alvo, e que a ponte sem entrevista segue funcionando; `commands/ponte.md` ganha `Carregue Skill(ponte)...` no padrão de `commands/setup.md:6` — provado por grep

## Premissas aceitas sem conferir

- Porta `3005` como default real e estável do bridge — aceito da Q1 fechada.
- `sabia` como slug reservado em `projetos.json` — leitura literal da Q1.
- `.github/workflows/*.yml` como fonte suficiente de comandos de CI na varredura — caso mais comum; outros CIs ficam de fora.
- `mktemp -d`/git-bash disponíveis para as baterias novas, como nas existentes.
- Marcadores `rainforest-mind:projeto:inicio/fim` sem colisão em instalações existentes — inferido dos dois scripts da ponte, sem varredura de terceiros.

## Emendas da revisão de 2026-08-31 (reprovação, 2 críticos reproduzidos)

O `revisar` reprovou com controle reproduzido pela sessão (commit 242c0b4).
Estas tarefas reabrem o `executar` e são o critério da nova rodada.

### 11. Bloco gerado não depende da máquina de quem gera — restaura a frase incondicional [tipo: implementar]
atende: invariante 1 do plano (quebrada pelo C1 da revisão)
arquivos: `hooks/lib/ponte-corpo.cjs`, `scripts/testa-ponte.sh`
depende de: nenhuma
paralela: nao (mesmo arquivo da 12)
mutacao:
  arquivo: `hooks/lib/ponte-corpo.cjs`
  de: a frase ", e monte com `node <plugin>/scripts/setup.cjs --criar` se ainda nao existir" emitida incondicionalmente
  para: de volta a condicional `${dados ? "" : "..."}`
  bateria: `bash scripts/testa-ponte.sh`
  fixture: caso novo "bloco gerado e identico com e sem pasta de dados resolvida"
pronto quando: `corpo(agente, nucleo, dados)` devolve byte a byte o MESMO texto para `dados` resolvido e `dados=null` (provado por caso novo em `testa-ponte.sh` que compara as duas saídas — pode fixar `RFM_ROOT` num caminho inexistente numa das execuções); a frase do `setup.cjs --criar` presente no bloco gerado NESTA máquina (que resolve a pasta de dados); e um bloco gerado pelo código do commit `21266f79` (fixture congelada não é viável porque o núcleo do SKILL.md evolui — a prova é a identidade com/sem `dados`, que é a propriedade que o código antigo tinha)

### 12. Resposta da entrevista não corrompe o bloco — sanitiza marcadores [tipo: implementar]
atende: T3 (critério "as 4 respostas literais" sob entrada adversarial)
arquivos: `scripts/ponte.cjs`, `hooks/lib/ponte-corpo.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: 11
paralela: nao
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: a sanitização dos marcadores nas respostas em `gerarProjetoMarkdown`
  para: respostas gravadas cruas (sem sanitizar)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "resposta contendo o marcador projeto:fim nao trunca o bloco"
pronto quando: com `--respostas` contendo `<!-- rainforest-mind:projeto:fim -->` dentro de uma resposta, o `projeto.md` E o `CLAUDE.md` gerados contêm as 4 respostas (sentinelas por grep), o bloco de projeto fecha no marcador REAL (último do arquivo), e `conferir-ponte.cjs` devolve CONFERIDO exit 0 no arquivo gerado

### 13. `conferir-ponte.cjs` usa o módulo compartilhado de verdade [tipo: implementar]
atende: D2 (achado 3 da revisão — duplicação que a T1 existia para eliminar)
arquivos: `scripts/conferir-ponte.cjs`
depende de: 12
paralela: nao
mutacao:
  arquivo: `scripts/conferir-ponte.cjs`
  de: a chamada a `lerProjetoMd` do módulo compartilhado na conferência do bloco de projeto
  para: `null` fixo (nunca acha o bloco)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: os casos existentes de conferência do bloco de projeto
pronto quando: `grep -c 'lerProjetoMd' scripts/conferir-ponte.cjs` ≥ 2 (import E uso), a extração à mão por `indexOf` dos marcadores de projeto removida do arquivo, e todas as baterias verdes

### 14. SKILL.md descreve o título que o código gera [tipo: docs]
atende: T10 (achado 4 da revisão)
arquivos: `skills/ponte/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a (docs)
pronto quando: a linha "Título:" da seção "O arquivo gerado" descreve `# Bloco do projeto` (o que `gerarProjetoMarkdown` emite), provado por grep nos dois arquivos

## Emendas da revisão rodada 2 (2026-08-31)

A rodada 2 reprovou com 2 críticos novos, reproduzidos de ponta a ponta pela sessão.

### 15. Resposta da entrevista é string ou é erro — o bypass por tipo fecha [tipo: implementar]
atende: T3/T12 (critério "as 4 respostas literais" sob entrada adversarial, agora por tipo)
arquivos: `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao (mesmo arquivo da 16 nas baterias)
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: a validação de tipo das respostas (rejeita não-string)
  para: validação removida (qualquer tipo passa)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "resposta que nao e string e recusada com erro"
pronto quando: `--respostas` com valor não-string em qualquer das 4 chaves (ex.: array contendo o marcador de fim) sai com erro claro e exit != 0, sem gravar nada; E defesa em profundidade: depois de gerar o markdown do projeto.md, o gerador conta os marcadores — se houver mais de um `inicio` ou mais de um `fim` no conteúdo final, aborta com erro em vez de gravar; caso de bateria prova os dois

### 16. `conferir-ponte.cjs` funciona com caminho relativo e POSIX [tipo: implementar]
atende: T5/T13 (a catraca do bloco de projeto no uso documentado do CLI)
arquivos: `scripts/conferir-ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/conferir-ponte.cjs`
  de: a resolução do diretório do alvo por `path.resolve`
  para: de volta ao regex `/^[A-Z]:/` com `null` no não-casado
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "conferir com caminho relativo devolve o mesmo veredito do absoluto"
pronto quando: `node scripts/conferir-ponte.cjs CLAUDE.md` rodado de dentro do diretório alvo (caminho relativo, sem cygpath) devolve o MESMO veredito e exit do caminho absoluto — CONFERIDO 0 em arquivo em dia; o regex de letra de drive sai do código (a resolução usa `path.resolve(alvo)`, que cobre relativo, POSIX e Windows); alvo `-` (stdin) continua funcionando como antes

### 17. Um único cálculo de hash — as reimplementações locais saem [tipo: implementar]
atende: D2 (aviso 3 da rodada 2 — mesma classe do incidente que motivou a T1)
arquivos: `scripts/conferir-ponte.cjs`, `scripts/ponte.cjs`, `hooks/lib/ponte-corpo.cjs`, `scripts/testa-ponte.sh`
depende de: 16
paralela: nao
mutacao:
  arquivo: `hooks/lib/ponte-corpo.cjs`
  de: o cálculo compartilhado de hash (sha256 slice 16)
  para: slice(8) (hash mais curto)
  bateria: `bash scripts/testa-ponte.sh && bash scripts/testa-ponte-entrevista.sh`
  fixture: os casos existentes de hash de bloco
pronto quando: o cálculo sha256-slice(16) existe UMA vez, exportado de `hooks/lib/ponte-corpo.cjs`, e `grep -n 'createHash' scripts/ponte.cjs scripts/conferir-ponte.cjs` devolve vazio; todas as baterias verdes; a mutação prova que o hash compartilhado é o que os dois scripts realmente usam

## Emenda da revisão rodada 3 (2026-08-31)

### 18. Regeneração só remove bloco de projeto REAL — texto manual que menciona o marcador sobrevive [tipo: implementar]
atende: invariante 1 e a garantia do próprio código ("o que era dela continua intacto, byte a byte")
arquivos: `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: a exigência do marcador de INÍCIO do projeto na remoção do bloco antigo em `escrever()`
  para: de volta ao corte cego por `depois.includes(FIM_PROJETO)`
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "texto manual que cita o marcador sobrevive a regeneração"
pronto quando: em `escrever()`, o trecho removido do conteúdo pós-FIM é exatamente o bloco delimitado por `<!-- rainforest-mind:projeto:inicio` ... `<!-- rainforest-mind:projeto:fim -->` — e só quando o INÍCIO existe e vem ANTES do fim; menção solta ao marcador de fim em texto manual não remove nada. Provado por caso novo: CLAUDE.md gerado + notas manuais contendo a string literal do marcador de fim → segundo `--aplicar` → as notas sobrevivem byte a byte (sentinelas antes e depois da menção). E o achado 2 junto: a regeneração volta a separar o bloco do texto manual seguinte com linha em branco (`\n` restaurado como na base), provado comparando a saída da regeneração com bloco+texto manual — o texto não pode colar na linha do FIM

## Emenda da revisão rodada 4 (2026-08-31)

### 19. Remoção do bloco antigo é posicional — só o bloco que o gerador escreveu [tipo: implementar]
atende: invariante 1; fecha a família inteira dos vetores de menção (fim na R3, início na R4)
arquivos: `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: a exigência posicional (pós-FIM começa com o marcador de início do projeto)
  para: de volta ao indexOf em qualquer posição
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "mencao ao inicio antes de bloco real nao apaga nada"
pronto quando: em `escrever()`, o bloco de projeto antigo só é removido quando o pós-FIM (após aparar quebras de linha) COMEÇA com `<!-- rainforest-mind:projeto:inicio` — a posição onde o próprio gerador o escreve; o corte vai até o primeiro `<!-- rainforest-mind:projeto:fim -->` a partir daí. Menção a QUALQUER marcador em texto manual (antes, depois, com ou sem bloco real deslocado) não remove nada. Provado por caso novo com 4 sentinelas (antes da menção ao início, entre a menção e um bloco real deslocado, dentro do bloco deslocado, depois dele) — as 4 sobrevivem à regeneração; e os casos existentes (i)/(o) continuam verdes (bloco gerado-adjacente continua substituído sem duplicar)

## Emenda da revisão rodada 5 (2026-08-31)

### 20. Bloco de projeto truncado não duplica calado — regeneração recusa com erro [tipo: implementar]
atende: invariante 1 e o lema do próprio ponte.cjs ("errada calada" é o pior estado)
arquivos: `scripts/ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/ponte.cjs`
  de: a recusa com erro quando o pós-FIM começa com projeto:inicio sem projeto:fim
  para: seguir gravando como antes (duplicata calada)
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "bloco de projeto sem fim recusa a regeneração com erro"
pronto quando: em `escrever()`, quando o pós-FIM começa com `<!-- rainforest-mind:projeto:inicio` mas não há `<!-- rainforest-mind:projeto:fim -->` no restante, a regeneração desse arquivo FALHA com mensagem clara (bloco de projeto truncado — restaure o marcador de fim ou remova o bloco) e exit != 0, sem gravar nada nesse arquivo; provado por caso novo (gera com projeto, apaga a linha do fim à mão, regenera → exit != 0, arquivo intocado byte a byte, mensagem presente); cenários vizinhos continuam: menção solta sem bloco real segue gravando normal (casos o/p verdes)

## Emenda da revisão rodada 6 (2026-08-31)

### 21. Extração do bloco na CATRACA é posicional como a escrita — menção em prosa nunca casa [tipo: implementar]
atende: invariante 1; espelha a tarefa 19 no lado da leitura
arquivos: `scripts/conferir-ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/conferir-ponte.cjs`
  de: a âncora de linha inteira na extração do bloco de projeto
  para: de volta ao match de primeira ocorrência em qualquer posição
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "mencao em prosa aos marcadores nao confunde a catraca"
pronto quando: `extrairBlocoProjetoGerado` só reconhece marcador que OCUPA A LINHA INTEIRA (âncora multiline, como o gerador escreve), e o fim considerado é o primeiro APÓS o início; menção em prosa (marcador no meio de uma frase) nunca casa. Provado por caso novo: CLAUDE.md pré-existente com menção em prosa aos dois marcadores + bloco real acrescentado pelo gerador → `conferir-ponte.cjs` devolve CONFERIDO exit 0; e mudar o projeto.md depois ainda dá ficou-para-trás (a catraca continua mordendo o bloco real)

## Emendas da revisão rodada 7 (2026-08-31)

### 22. `lerProjetoMd` só reconhece marcador de linha inteira — prosa no projeto.md não corrompe a escrita [tipo: implementar]
atende: invariante 1; fecha a última instância da família posicional (T19 escrita do CLAUDE.md, T21 leitura da catraca, agora a leitura do projeto.md)
arquivos: `hooks/lib/ponte-corpo.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `hooks/lib/ponte-corpo.cjs`
  de: a âncora de linha inteira em `lerProjetoMd`
  para: de volta ao `indexOf` sem âncora
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso novo "prosa no topo do projeto.md nao corrompe o bloco gravado"
pronto quando: `lerProjetoMd` acha os marcadores por âncora multiline de linha inteira (início e o primeiro fim APÓS ele); prosa mencionando os marcadores no projeto.md não muda o bloco extraído. Provado por caso novo: projeto.md gerado + nota da equipe no topo citando os dois marcadores → `--aplicar` grava o bloco REAL no CLAUDE.md (resposta literal presente), e `conferir-ponte.cjs` dá CONFERIDO exit 0

### 23. `temBloco` no veredito da catraca — a linha de status humana volta a imprimir [tipo: implementar]
atende: aviso 2 da rodada 7 (cosmético, sem mudança de exit)
arquivos: `scripts/conferir-ponte.cjs`, `scripts/testa-ponte-entrevista.sh`
depende de: 22
paralela: nao
mutacao:
  arquivo: `scripts/conferir-ponte.cjs`
  de: o `temBloco: true` nos retornos com bloco presente
  para: removido
  bateria: `bash scripts/testa-ponte-entrevista.sh`
  fixture: caso estendido do (r) conferindo a linha de status na saída texto
pronto quando: `conferirBlocoProjetoGerado` retorna `temBloco: true` em todo veredito em que o bloco existe no arquivo, a saída texto imprime a linha de status do bloco de projeto, e um caso da bateria a confere por grep
