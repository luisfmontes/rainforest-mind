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

### 5. Passada de LLM ligada de verdade [tipo: implementar] — BLOQUEADA
atende: (decisão em aberto no design)
pronto quando: a definir junto com o caminho escolhido. O critério **não** pode ser "a marca d'água fica intacta quando a LLM falha" — foi exatamente esse o critério que o toco de hoje satisfaz. Tem que ser observação **gravada** no banco a partir de transcrito real, com `projeto` correto, conferida por `SELECT`.

### 6. Teto por chamada e fatiamento do trecho [tipo: implementar] — BLOQUEADA
atende: (decisão em aberto no design)
pronto quando: trecho maior que o teto vira N chamadas, e a marca d'água avança por fatia processada — nunca de uma vez só no fim.

### 7. A virada: importar, provar, desligar [tipo: configurar]
atende: D5
depende de: 2, 3, 5
paralela: nao
pronto quando: as 10.071 observações estão no banco com os 26 projetos preservados (`SELECT projeto, count(*) ... GROUP BY 1` batendo com a contagem da origem); uma observação nova, vinda de sessão real, está gravada com o projeto certo; e só então os hooks do claude-mem saem. Desligar é ação no ambiente do usuário: pergunta antes.
