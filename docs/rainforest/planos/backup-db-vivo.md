# Plano: Backup externo falha quando o rainforest.db está aberto por outra sessão

Design: docs/rainforest/design/backup-db-vivo.md

## O que não pode quebrar
- A lista D10 (`ITENS_BACKUP`) não muda, e o zip continua com os itens na raiz, com os mesmos nomes (`rainforest.db` inclusive).
- A escrita atômica (temp `.parcial.zip` + rename), a idempotência ("ja existe") e a rotação de 30 zips continuam como estão.
- O `rainforest.db` da origem nunca é escrito: a cópia abre a conexão só de leitura (`readOnly: true`).
- Os outros arquivos do zip continuam provados por hash no `conferir`.
- Nada de temporário fica para trás: o diretório da cópia sai em sucesso e em falha.

## Tarefas

### 1. `gravar` zipa uma cópia consistente do banco [tipo: implementar]
atende: D1, D2, D4
arquivos: `scripts/backup.cjs`, `scripts/testa-backup-gravar.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/backup.cjs`
  de: const fullPath = substituicoes[item] || path.join(origem, item);
  para: const fullPath = path.join(origem, item);
  bateria: `bash scripts/testa-backup-gravar.sh`
  fixture: testa-backup-gravar.sh, caso "(db-aberto) gravar com conexao aberta no rainforest.db sai 0 e o banco do zip passa no integrity_check"
Implementação:
- Nova função `copiarBancoConsistente(origem)`. Se `rainforest.db` não existe na origem, devolve `{ caminho: null }`. Senão, cria `fs.mkdtempSync(path.join(os.tmpdir(), 'rainforest-db-'))`, abre `new (require('node:sqlite').DatabaseSync)(<origem>/rainforest.db, { readOnly: true })`, roda `VACUUM INTO '<dir>/rainforest.db'` (apóstrofo do caminho duplicado) e fecha. Devolve `{ caminho, dir }`, ou `{ erro: <mensagem>, dir }` em qualquer exceção, com o `require` dentro do `try`.
- `compactarSimples(origem, itens, zipPath, substituicoes = {})`. No `map` dos caminhos, a linha passa a ser exatamente a do `de:` acima. O filtro de existentes usa o mesmo `substituicoes[item] || path.join(origem, item)`.
- Em `cmdGravar`, antes de compactar, chama `copiarBancoConsistente(origem)`.
  - Com `caminho`: passa `{ 'rainforest.db': caminho }`.
  - Com `erro`: compacta a lista sem `'rainforest.db'`, segue o fluxo normal até o rename e a rotação, e no fim imprime em stderr `RECUSADO: rainforest.db ficou fora do backup: <erro>` e sai 2.
  - O `dir` temporário é removido com `fs.rmSync(dir, { recursive: true, force: true })` em todos os caminhos de saída depois da cópia.
- Docblock do topo e `imprimirUso`: dizem que o banco entra por cópia `VACUUM INTO` e que exit 2 também cobre "zip gravado sem o rainforest.db".
- Bateria (`scripts/testa-backup-gravar.sh`):
  - `criarOrigem` passa a criar o `rainforest.db` como SQLite de verdade, via `node -e` com `node:sqlite` (tabela com uma linha), no lugar do `dd` de zeros.
  - Caso `(db-aberto)`: um processo `node` em background abre o banco da origem com conexão de escrita e fica vivo (ex.: `setTimeout` de 60 s, pid guardado e morto no fim). Com ele de pé, `gravar` sai 0, o zip existe, e o `rainforest.db` extraído do zip abre com `node:sqlite` e dá `PRAGMA integrity_check` = `ok`.
  - Caso `(db-invalido)`: o `rainforest.db` da origem são bytes que não formam SQLite. `gravar` sai 2, o stderr contém `rainforest.db ficou fora do backup`, o zip existe com o nome final, contém `FOCO.md` e não contém `rainforest.db`.
  - Os dois casos também conferem que nenhum `rainforest-db-*` sobrou no `os.tmpdir()` do processo (use `TMP`/`TEMP` apontando para um `mktemp -d` da bateria para dar para contar).
pronto quando: com uma origem cujo `rainforest.db` é um SQLite real mantido aberto para escrita por outro processo `node`, `node scripts/backup.cjs gravar --origem <o> --destino <d>` sai 0 e o `rainforest.db` dentro de `<d>/rainforest-<hoje>.zip` dá `integrity_check` = `ok`; com o banco inválido, sai 2 com "rainforest.db ficou fora do backup" e o zip final existe sem o banco. Provado pelos casos `(db-aberto)` e `(db-invalido)` de `bash scripts/testa-backup-gravar.sh` (0 falhas, 0 skipped) e pela saída do mesmo comando rodado à mão pela integração contra um banco aberto.

### 2. `conferir` prova o banco por restauração [tipo: implementar]
atende: D3, D4
arquivos: `scripts/backup.cjs`, `scripts/testa-backup-conferir.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/backup.cjs`
  de: if (caminhoRelativo === 'rainforest.db') {
  para: if (false) {
  bateria: `bash scripts/testa-backup-conferir.sh`
  fixture: testa-backup-conferir.sh, caso "(db-snapshot) zip recem-gravado, com o banco da origem alterado depois, conferir sai 0 (integrity_check, nao hash)"
Implementação:
- No laço de `cmdConferir` que compara arquivo por arquivo, antes da comparação de hash, entra exatamente a linha `if (caminhoRelativo === 'rainforest.db') {`.
- Dentro desse ramo, abre o arquivo extraído com `node:sqlite` `{ readOnly: true }` e roda `PRAGMA integrity_check`, fechando a conexão em `finally`. Resultado diferente de `ok`, ou exceção ao abrir, vira divergência com a descrição `banco nao passa no integrity_check (<resultado ou erro>)`. Com `ok`, segue para o próximo arquivo com `continue`, sem hash.
- A direção origem → zip não muda.
- Bateria (`scripts/testa-backup-conferir.sh`):
  - A origem usa SQLite real, como na tarefa 1.
  - Caso `(db-snapshot)`: `gravar`, depois uma escrita nova no banco da origem (`insert`), depois `conferir` sai 0 e diz `intacto`.
  - Caso `(db-corrompido)`: o `rainforest.db` dentro do zip é trocado por bytes inválidos, recompactando o zip na bateria. `conferir` sai 1 e o stderr contém `integrity_check`.
  - Os casos existentes de hash dos outros arquivos continuam passando.
pronto quando: com um zip gravado pela tarefa 1 e o banco da origem alterado depois, `node scripts/backup.cjs conferir --origem <o> --destino <d>` sai 0 com `intacto`; com o banco do zip corrompido, sai 1 citando `integrity_check`. Provado pelos casos `(db-snapshot)` e `(db-corrompido)` de `bash scripts/testa-backup-conferir.sh` (0 falhas).

### 3. Versão e registro [tipo: docs]
atende: D5
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto de registro e número de versão; não há comportamento a inverter. A coerência se confere pela bateria de versão e pela leitura contra o design.
pronto quando: com `origin/main` em 1.30.0, os dois manifestos e o badge do README dizem 1.30.1 e `bash scripts/testa-versao.sh` sai com 0 falhas. A entrada do CHANGELOG descreve a causa (o banco aberto por outra sessão travava o zip inteiro, nas seis datas), o conserto (cópia `VACUUM INTO`, zip parcial com exit 2 quando a cópia falha) e a prova nova do `conferir` (`integrity_check`), sem prometer nada além de D1–D3. Isso se confere lendo a entrada contra o design.
