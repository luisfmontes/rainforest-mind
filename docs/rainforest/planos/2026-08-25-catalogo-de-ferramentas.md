# Plano: Catálogo de ferramentas — a janela sabe antes de tentar (#76)

Design: docs/rainforest/design/2026-08-25-catalogo-de-ferramentas.md

## O que não pode quebrar

- **O payload do `SessionStart` não cresce.** Ele já mede 8.085 B contra
  `ORCAMENTO_BYTES` de 8.000. Byte novo na abertura sai de bloco de regra (D1).
- **Nenhuma execução é recusada por causa do ledger.** O hook de consulta sai 0
  sempre, sem exceção (D10). Recusa silenciosa é o pior caso da issue.
- **A checagem da bridge do WhatsApp em `hooks/foco-session-start.cjs` fica
  intacta** (D4).
- **Nada escreve fora de `~/.rainforest/ferramentas.jsonl`** — nem PATH, nem env,
  nem config, nem instalação (regra 15).
- **O arquivo nunca ganha campo de negativa.** Não existe `ausente`, `faltando`
  nem `status: "nao-encontrado"` (D2).
- **O payload de teste é o que o harness realmente manda**, tirado de transcrito
  real, nunca inventado. Em 2026-08-19 dez baterias verdes certificaram um
  subsistema morto porque o hook lia `evento.project`, campo que o harness nunca
  envia, e os testes injetavam o campo à mão.

## Tarefas

### 1. Porta única do ledger: `scripts/ferramentas.cjs` [tipo: implementar]
atende: D2, D3, D5, D11, D13
arquivos: `scripts/ferramentas.cjs`, `scripts/testa-ferramentas.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/ferramentas.cjs`
  de: a recusa por campo de negativa — o `process.exit(2)` do ramo que detecta chave proibida na entrada de `registrar`
  para: `process.exit(0)`
  bateria: `bash scripts/testa-ferramentas.sh`
  fixture: o caso "registrar com campo de negativa é recusado" de `scripts/testa-ferramentas.sh`
pronto quando: com um `ferramentas.jsonl` de caixa contendo a entrada real do caso da transcrição (`whisper-cli`, com receita apontando o binário fora do PATH e o `.bin` de modelo), `node scripts/ferramentas.cjs consultar whisper-cli` devolve a receita gravada e sai 0; `consultar` de nome ausente sai 0 imprimindo `desconhecido` e **nunca** a palavra `ausente`; `registrar` de uma entrada que carregue qualquer chave de negativa é recusado com exit 2 nomeando a chave; e `registrar` do mesmo nome duas vezes deixa **uma** linha, com a data da segunda — provado por `bash scripts/testa-ferramentas.sh` e pela contagem `wc -l` do arquivo da caixa antes e depois

### 2. Consulta antes de tentar, e grava o que a sonda achar: `hooks/ferramentas-consulta.cjs` [tipo: implementar]
atende: D5, D6, D8, D10, D11, D12, D14
arquivos: `hooks/ferramentas-consulta.cjs`, `hooks/testa-ferramentas-consulta.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/ferramentas-consulta.cjs`
  de: o `process.exit(0)` do caminho final, que garante que o hook nunca recusa
  para: `process.exit(2)`
  bateria: `bash hooks/testa-ferramentas-consulta.sh`
  fixture: o caso "executável desconhecido não recusa a execução" de `hooks/testa-ferramentas-consulta.sh`
pronto quando: com o JSON que o harness realmente envia num `PreToolUse` de `Bash` — extraído de transcrito real, não montado a partir da documentação —, o hook sai **0 em todos os casos**; com o executável presente no ledger ele não gasta nenhum subprocesso (provado contando processos filhos, ou pela ausência da sonda no rastro); com o executável ausente do ledger ele gasta **exatamente uma** checagem e imprime o anúncio nomeando a ferramenta e o efeito prático — provado por `bash hooks/testa-ferramentas-consulta.sh`

### 3. Registro do hook em `hooks/hooks.json` [tipo: configurar]
atende: D7, D9
arquivos: `hooks/hooks.json`, `hooks/testa-config.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/hooks.json`
  de: o `matcher: "Bash"` do hook novo
  para: matcher que casa com qualquer ferramenta
  bateria: `bash hooks/testa-config.sh`
  fixture: o caso que afirma que o hook de ferramentas só dispara em `Bash`, a acrescentar em `hooks/testa-config.sh`
pronto quando: `hooks/hooks.json` continua sendo JSON válido e o hook novo aparece **apenas** sob `PreToolUse`, com `matcher: "Bash"`, e **nenhum** hook aparece sob `PostToolUse`, sem tocar nos três hooks já registrados — e `bash hooks/testa-memoria-marca.sh` continua verde, que é a trava que proíbe `PostToolUse` neste repo — provado por `bash hooks/testa-config.sh` e por `node -e` contando as entradas de cada evento antes e depois

### 4. Catraca: a abertura não cresce e a bridge fica intacta [tipo: teste]
atende: D1, D4
arquivos: `hooks/testa-ferramentas-nao-toca-abertura.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `hooks/hooks.json`
  de: o bloco de `SessionStart`, sem o hook de ferramentas
  para: o mesmo bloco com o `ferramentas-consulta.cjs` acrescentado
  bateria: `bash hooks/testa-ferramentas-nao-toca-abertura.sh`
  fixture: o caso "nada de ferramentas entrou na abertura" da própria bateria
pronto quando: `node hooks/foco-session-start.cjs` não produz **nenhum** byte vindo deste trabalho — nenhuma menção ao ledger, ao hook de ferramentas ou a entrada de catálogo na saída —, o `SessionStart` do `hooks.json` continua com os mesmos 4 hooks de antes, e a linha `Dependências de ambiente (regra 14)` com a checagem da bridge continua presente e vinda de `foco-session-start.cjs` — provado por `bash hooks/testa-ferramentas-nao-toca-abertura.sh`

> **Critério corrigido em 2026-08-25, e a correção é o achado.** A versão anterior
> comparava a saída da abertura contra um teto absoluto de 8.085 B. Medido depois da
> tarefa 3: a saída está em **8.430 B**, e nenhum dos 345 B veio deste trabalho —
> `git diff origin/main HEAD -- hooks/foco-session-start.cjs hooks/lib/contexto-sessao.cjs`
> é vazio, e a única ocorrência da palavra "ferramenta" na saída é o texto da regra 15.
> O payload varia com o FOCO.md, com o corpus de memória e com o bloco multi-janela —
> ou seja, com **dado do usuário**. Um teto absoluto ficaria vermelho por motivo alheio
> e mediria a coisa errada. O que a D1 promete é que **este trabalho** contribui zero
> para a abertura, e é isso que se afere.

### 5. README e elaboração da regra 14 [tipo: docs]
atende: D3, D4
arquivos: `README.md`, `skills/rainforest-mind/references/regra-14.md`
depende de: 4
paralela: nao
mutacao: n/a
  motivo: texto não tem ramo de execução a inverter; a falsificação dele é casar com a interface real, que é o que o critério abaixo confere
pronto quando: o README descreve o ledger **sem** prometer varredura, comando de scan ou inventário completo (D3), e a contagem de hooks e de baterias do README bate com a contagem real obtida rodando `node -e` sobre `hooks/hooks.json` e `ls hooks/testa-*.sh scripts/testa-*.sh`; e a elaboração da regra 14 nomeia a dívida da D4 — a checagem da bridge segue separada — sem afirmar que ela foi unificada; nenhum dos dois textos menciona campo de negativa como possibilidade — provado por comparação dos números do texto com a saída dos dois comandos, e por `node scripts/conferir-publicacao.cjs` saindo 0 nos dois arquivos
