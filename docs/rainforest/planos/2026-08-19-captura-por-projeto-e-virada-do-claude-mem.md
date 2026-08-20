# Plano: a captura passa a ser nossa, e por projeto

Design: `docs/rainforest/design/2026-08-19-captura-por-projeto-e-virada-do-claude-mem.md`

As tarefas 1 a 4 são a **identidade de projeto** e não dependem de nenhuma
decisão em aberto. As 5 e 6 esperam a decisão do caminho da LLM (seção "Em
aberto" do design). A 7 é a virada, e só corre depois das duas.

## O que não pode quebrar

- A abertura de sessão continua funcionando com o banco **ausente, vazio ou
  corrompido**. Memória indisponível degrada o bloco, nunca bloqueia a sessão.
- O `ORCAMENTO_BYTES` de `hooks/lib/contexto-sessao.cjs` **não aumenta** (está
  em 7.977 B de 8.000 — 23 B de folga).
- Nenhum caminho de execução passa a exigir o claude-mem instalado.
- As baterias do repo continuam verdes, local e no CI.
- `grep -rl "node:sqlite" scripts/ hooks/ --exclude="testa-*"` continua listando
  **exatamente** `scripts/memoria.cjs`.

## Tarefas

### 1. O projeto vem do diretório da sessão, não da raiz de dados [tipo: implementar]
atende: D1
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria.sh`
depende de: nenhuma
paralela: nao
pronto quando: os três casos abaixo, com o comando e a saída colados:
  a) de dentro deste repositório, `node -e "console.log(require('./scripts/memoria.cjs').resolverCaminhos().projeto)"` imprime `rainforest-mind` — **hoje imprime `Luis`**, e imprimir `Luis` reprova;
  b) de uma pasta temporária **fora** de qualquer repositório git, imprime o basename dessa pasta e sai 0 (fallback do D1, não erro);
  c) de dentro de uma worktree linkada criada com `git worktree add`, imprime o basename **da worktree**, não o do repositório principal.

### 2. O importador preserva o projeto da origem [tipo: implementar]
atende: D2, D4
arquivos: `scripts/importar-claude-mem.cjs`, `scripts/testa-importar-claude-mem.sh`
depende de: 1
paralela: nao
pronto quando: `bash scripts/testa-importar-claude-mem.sh` sai 0 com um caso novo: origem sintética com observações de **três** projetos distintos, um deles no formato `pai/filho`. Depois de importar, `SELECT DISTINCT projeto FROM observacoes ORDER BY 1` devolve **três** linhas, e a do `pai/filho` está normalizada para `filho` (D2).
falsificação: se a implementação ignorar a coluna `project` da origem (o defeito de hoje), esse `SELECT DISTINCT` devolve **uma** linha — a bateria tem que ficar vermelha nesse caso, e o relatório precisa mostrar isso rodando contra o código velho.

### 3. A injeção filtra por projeto e completa o teto com as globais [tipo: implementar]
atende: D3
arquivos: `hooks/memoria-session-start.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: 1
paralela: nao
pronto quando: `bash hooks/testa-memoria-session-start.sh` sai 0 **exercitando o hook de verdade** (`echo '{}' | node hooks/memoria-session-start.cjs`, lendo o `additionalContext`), cobrindo dois casos contra banco de fixture:
  a) projeto com 8 observações próprias e outro projeto com 8 — o bloco traz as **8 próprias primeiro** e completa até o teto de **14** com as do outro, cada linha com o rótulo do projeto;
  b) projeto com **2** observações próprias — o bloco traz as 2 dele primeiro e completa com 12 de outros projetos, rotuladas.
falsificação: removido o `WHERE projeto = ?` da consulta (o código de antes), a bateria tem que ficar **vermelha** — a ordem "próprias primeiro" cai.

> **Correção de 2026-08-19 (madrugada).** A redação original dizia teto **5** e
> "nenhuma do segundo aparece no bloco". As duas coisas estavam erradas, e o erro
> foi meu: li o default da assinatura (`lerObservacoes(caminhoDb, limite = 5)`)
> em vez do call site, que passa **14** desde antes deste trabalho, calibrado pela
> D11 do desenho anterior. Com teto 14 e 8 observações próprias, completar com as
> de outro projeto é o comportamento decidido na D3, não defeito. Fica registrado
> porque critério que muda em silêncio é o que a esteira anterior passou o dia
> pagando para descobrir.

### 4. As marcas d'água escritas sob o rótulo velho saem [tipo: implementar]
atende: D1
arquivos: `scripts/memoria.cjs`
depende de: 1
paralela: nao
pronto quando: a migração remove de `marca_dagua` as linhas cujo `projeto` não corresponde mais à derivação nova, e `node scripts/memoria.cjs esquema --json` continua saindo 0 depois dela. A `UNIQUE(projeto, sessao)` é a razão: linha velha com `projeto` constante nunca mais casa com a sessão que a escreveu, e fica órfã para sempre.

### 5. Passada de LLM ligada de verdade [tipo: implementar]
atende: D6
arquivos: `scripts/observar.cjs`, `scripts/testa-observar.sh`
depende de: 1
paralela: nao
pronto quando: os quatro itens abaixo, cada um com comando e saída colados:
  a) `bash scripts/testa-observar.sh` sai 0, com caso novo em que o dublê devolve texto e a observação **aparece no banco** — `SELECT projeto, conteudo FROM observacoes` traz a linha, com o `projeto` resolvido pela tarefa 1;
  b) **prova de ponta a ponta com a LLM de verdade**, rodada à mão e colada no relatório: um transcrito de fixture pequeno, `node scripts/observar.cjs` sem dublê, e o `SELECT` mostrando a observação gravada. Esta é a régua que o toco de hoje não passa: hoje o mesmo comando imprime `AVISO: LLM não disponível` e não grava nada;
  c) a linha de comando montada carrega `--setting-sources ''`, o modelo fixado, e o travamento de ferramenta da D6 — `grep -n "setting-sources\|disallowedTools\|permission-mode" scripts/observar.cjs` mostra os três;
  d) `cwd` da chamada é diretório neutro, nunca o do projeto — para o transcrito, que é conteúdo não confiável, não conseguir puxar arquivo do repositório de quem estiver rodando.
falsificação: com a LLM falhando (dublê que devolve `null`), **nenhuma observação vazia é gravada** e a marca d'água **não avança** — `SELECT count(*) FROM observacoes` fica em 0 e o `offset_processado` fica onde estava. Rodar e colar.

### 6. Teto por chamada e fatiamento do trecho [tipo: implementar]
atende: D6
arquivos: `scripts/observar.cjs`, `scripts/testa-observar.sh`
depende de: 5
paralela: nao
pronto quando: `bash scripts/testa-observar.sh` sai 0 com um trecho de fixture **maior que o teto** (o limite medido é `ENAMETOOLONG` entre 16.908 e 33.708 caracteres de argumento; adote teto conservador e deixe-o nomeado numa constante): o dublê conta as chamadas e recebe **mais de uma**, nenhuma delas acima do teto, e a marca d'água avança **por fatia processada**, não de uma vez no fim.
falsificação: com o teto elevado artificialmente acima do trecho, a chamada única tem que estourar `ENAMETOOLONG` — se não estourar, o teste não está exercitando o caminho que a constante existe para evitar.

### 7. A virada: importar, provar, desligar [tipo: configurar]
atende: D5
depende de: 2, 3, 5
paralela: nao
pronto quando: as 10.071 observações estão no banco com os 26 projetos preservados (`SELECT projeto, count(*) ... GROUP BY 1` batendo com a contagem da origem); uma observação nova, vinda de sessão real, está gravada com o projeto certo; e só então os hooks do claude-mem saem. Desligar é ação no ambiente do usuário: pergunta antes.
