# Plano: Memória e dados do rainforest saem de dependência frágil

Design: docs/rainforest/design/2026-08-17-memoria-e-dados-do-rainforest.md

As tarefas 1 a 9 são a **fase 1** (leitura, reversível); 10 a 12 são a **fase 2**
(captura). A 13 não depende de nenhuma das duas.

## O que não pode quebrar

- A abertura de sessão funciona com o banco **ausente, vazio ou corrompido** — memória indisponível degrada o bloco de memória, nunca bloqueia a sessão. É a falha que este trabalho inteiro existe para não repetir.
- O `ORCAMENTO_BYTES` de `hooks/lib/contexto-sessao.cjs` **não aumenta**: o bloco de memória é item separado (D10) e não come o espaço das regras nem do FOCO.md.
- Nenhum caminho de execução do rainforest passa a exigir o claude-mem instalado. Só o importador (tarefa 3) o menciona, e ele roda sob demanda.
- `FOCO.md` e `ideias.jsonl` continuam legíveis e editáveis à mão, e `node scripts/ideias.cjs conferir` continua sendo a autoridade sobre o arquivo.
- As 20 baterias do repo continuam verdes, local e no CI.

## Tarefas

### 1. Esquema e criação do banco próprio [tipo: implementar]
atende: D2, D5, D9
arquivos: `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`
depende de: nenhuma
paralela: sim
pronto quando: `RFM_ROOT=$(mktemp -d) node scripts/memoria.cjs iniciar && RFM_ROOT=<a mesma> node scripts/memoria.cjs esquema --json` devolve exit 0 e um JSON cujas chaves incluem `observacoes`, `resumos`, `prompts` e `marca_dagua`, com a coluna `projeto` presente em `observacoes`; e o arquivo criado é `<RFM_ROOT>/rainforest.db`, não um caminho fixo.

### 2. Adaptador de leitura — o único módulo que conhece o esquema [tipo: implementar]
atende: D8
arquivos: `scripts/memoria.cjs`
depende de: 1
paralela: nao
pronto quando: `node scripts/memoria.cjs buscar --texto "porta orfa" --limite 3 --json` devolve exit 0 e um array (vazio é resultado válido); e `grep -rl "node:sqlite" scripts/ hooks/` lista **exatamente** `scripts/memoria.cjs` — qualquer outro arquivo tocando o driver reprova a tarefa.

### 3. Importador do claude-mem, único e incremental [tipo: implementar]
atende: D6
arquivos: `scripts/importar-claude-mem.cjs`, `scripts/testa-importar-claude-mem.sh`
depende de: 1
paralela: nao
pronto quando: `bash scripts/testa-importar-claude-mem.sh` sai 0, cobrindo três casos contra um banco de origem sintético: importa N observações num banco vazio; reimportar sem novidade insere 0; e origem **ausente** devolve exit 0 com a mensagem de que não há o que importar, nunca erro.

### 4. Bloco de injeção de memória, item separado com teto próprio [tipo: implementar]
atende: D10
arquivos: `hooks/memoria-session-start.cjs`, `hooks/hooks.json`, `hooks/testa-memoria-session-start.sh`
depende de: 2
paralela: nao
pronto quando: `bash hooks/testa-memoria-session-start.sh` sai 0, provando que o bloco respeita seu próprio teto em bytes, anuncia o corte quando ele acontece, e emite bloco vazio sem estourar quando o banco não existe; e `node scripts/orcamento.cjs` continua reportando o hook de foco em `<= 8000 B`.

### 5. Calibrar quantas observações ficam residentes [tipo: pesquisar]
atende: D11
arquivos: `docs/rainforest/design/2026-08-17-memoria-e-dados-do-rainforest.md`, `hooks/memoria-session-start.cjs`
depende de: 4
paralela: nao
pronto quando: o design ganha uma linha com o número escolhido e o **tamanho medido em bytes** de 1, 3, 5 e 10 observações residentes do corpus real, e o valor no código bate com o escolhido — número arbitrado sem a medição colada reprova.

### 6. Provar que a fase 1 é reversível [tipo: teste]
atende: D16
arquivos: `scripts/testa-memoria-somente-leitura.sh`
depende de: 2, 3, 4
paralela: nao
pronto quando: `bash scripts/testa-memoria-somente-leitura.sh` sai 0, provando que uma abertura de sessão completa **não altera** o `rainforest.db` — hash do arquivo idêntico antes e depois — e que apagar o `rainforest.db` devolve a máquina ao estado anterior sem erro em nenhum hook.

### 7. Índice derivado de foco e ideias, reconstruível [tipo: implementar]
atende: D1
arquivos: `scripts/memoria.cjs`, `scripts/testa-indice-derivado.sh`
depende de: 1
paralela: nao
pronto quando: `bash scripts/testa-indice-derivado.sh` sai 0, provando que `node scripts/memoria.cjs reindexar` reconstrói o índice a partir de `FOCO.md` e `ideias.jsonl` **do zero**, que apagar o índice não perde dado nenhum, e que o `ideias.cjs` segue sendo o único que escreve no `ideias.jsonl`.

### 8. Versionar a raiz de dados [tipo: configurar]
atende: D3, D7
arquivos: `scripts/setup.cjs`, `scripts/testa-setup.sh`
depende de: nenhuma
paralela: sim
pronto quando: `RFM_ROOT=$(mktemp -d) node scripts/setup.cjs versionar` sai 0, cria repo git na raiz com um commit inicial, e o `.gitignore` gerado ignora `rainforest.db*`; e `git -C <raiz> status --short` sai vazio logo após o comando.

### 9. Backup próprio do banco [tipo: implementar]
atende: D7
arquivos: `scripts/memoria.cjs`, `scripts/testa-memoria-backup.sh`
depende de: 1
paralela: nao
pronto quando: `bash scripts/testa-memoria-backup.sh` sai 0, provando que `node scripts/memoria.cjs backup` gera cópia consultável (abre e responde a um `SELECT`) e que a rotação mantém o teto de cópias declarado, sem apagar a mais recente.

### 10. Marca d'água sobre o transcrito, gravada pelo hook [tipo: implementar]
atende: D12, D13
arquivos: `hooks/memoria-marca.cjs`, `hooks/hooks.json`, `hooks/testa-memoria-marca.sh`
depende de: 1
paralela: nao
pronto quando: `bash hooks/testa-memoria-marca.sh` sai 0, provando que o hook grava sessão, caminho do transcrito e offset **sem subir processo nenhum** (nenhum `spawn`/`exec` no arquivo, verificado por `grep`), e que reprocessar após recuar o offset é idempotente — mesma contagem final.

### 11. Gatilho no SessionEnd com recuperação na abertura [tipo: implementar]
atende: D14
arquivos: `hooks/memoria-marca.cjs`, `hooks/hooks.json`, `hooks/testa-memoria-recuperacao.sh`
depende de: 10
paralela: nao
pronto quando: `bash hooks/testa-memoria-recuperacao.sh` sai 0, cobrindo os dois caminhos: `SessionEnd` normal processa até o fim do transcrito; e uma sessão cujo `SessionEnd` **nunca dispara** é recuperada na abertura seguinte pela marca d'água, chegando à mesma contagem.

### 12. Passada de LLM: transcrito em observação [tipo: implementar]
atende: D4
arquivos: `scripts/observar.cjs`, `scripts/testa-observar.sh`
depende de: 10
paralela: nao
pronto quando: `bash scripts/testa-observar.sh` sai 0 contra um transcrito de fixture, provando que a passada roda **fora** de qualquer hook de `UserPromptSubmit` ou `PostToolUse` (verificado no `hooks.json`), que grava observação com `projeto` preenchido, e que falha na LLM deixa a marca d'água intacta para nova tentativa.

### 13. Issue no upstream: filtro antes do spawn [tipo: docs]
atende: D15
arquivos: `docs/rainforest/design/2026-08-17-memoria-e-dados-do-rainforest.md`
depende de: nenhuma
paralela: sim
pronto quando: a Issue existe no repo do claude-mem com os números medidos colados (15.331 `PostToolUse` em 8 dias, três processos por evento, `SKIP_TOOLS` lido só dentro do `worker-service.cjs`), e o design registra o link. **Texto escrito junto com o Luís antes de enviar** — publicação em repo de terceiro não sai sozinha.
