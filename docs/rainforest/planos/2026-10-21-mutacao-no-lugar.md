# Plano: mutação no lugar para runtime vivo (#527, #569)

Design: docs/rainforest/design/2026-10-21-mutacao-no-lugar.md

## O que não pode quebrar
- Sem `--no-lugar`, o `conferir-mutacao.cjs` copia a árvore como hoje e o fonte real nunca é tocado (#266): `bash scripts/testa-conferir-mutacao.sh` e `bash scripts/testa-conferir-mutacao-flaky.sh` verdes.
- Os códigos de saída de hoje (0, 1, 2, 3, 4, 5, 6, 69) mantêm o significado.
- Bloco `mutacao:` sem `no-lugar:` passa na `cobertura` e na catraca como hoje (`bash scripts/testa-conferir-fluxo.sh` verde).
- Nenhum caso de teste afirma sobre o texto do fonte: as baterias medem comportamento.

## Tarefas

### 1. `--no-lugar` mede na própria raiz e restaura byte a byte [tipo: implementar]
atende: D1, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: nenhuma
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `fs.writeFileSync(restauro.caminho, restauro.original);`
  para: `void 0;`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, casos N1 e N2`
pronto quando: num repo git descartável com `src.js` commitado e uma bateria que lê `src.js` na pasta real, `node scripts/conferir-mutacao.cjs --no-lugar --raiz <repo> --arquivo src.js --de <trecho> --para <inverso> --bateria <bateria>` sai 0 com a bateria vermelha (N1), e sai 2 com uma bateria que não mede o trecho (N2). Nos dois, `src.js` termina com o mesmo sha256 de antes. Com uma pasta da raiz que não se deixa copiar (arquivo sem permissão de leitura, ou bateria que falha quando o cwd não é a raiz real), o modo no lugar mede mesmo assim (N3), e sem `--no-lugar` a mesma raiz continua passando pela cópia (N4: o fonte real não muda durante a bateria). Com a bateria estourando o `--timeout` (N5), sai 1 e `src.js` volta ao sha256 de antes. Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 2. Alvo com mudança não commitada é recusado [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 1
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (sujoNoGit) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso S1`
pronto quando: com `src.js` modificado e não commitado no repo descartável, `--no-lugar` sai 4, o stderr nomeia o arquivo e diz que não há como desfazer pelo git, a bateria não roda e `src.js` fica com o conteúdo sujo intacto (S1). Fora de repo git, `--no-lugar` mede e o stderr avisa que não há conferência pelo git (S2). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 3. Backup órfão é restaurado na abertura [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 2
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (hashAtual === backup.hashMutado) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso O1`
pronto quando: com um backup `conferir-mutacao-nolugar-*.json` no temporário de um PID que não existe, apontando para `src.js` com o hash mutado igual ao conteúdo atual, a próxima execução do `conferir-mutacao.cjs` (com ou sem `--no-lugar`) devolve `src.js` aos bytes originais, apaga o backup e avisa no stderr (O1). Com `src.js` mudado depois da mutação (hash diferente), o arquivo fica intocado, o backup permanece e o stderr nomeia o caminho do backup (O2). O temporário dos casos é isolado (`TMPDIR`/`TEMP`/`TMP` apontando para pasta do caso). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 4. Backup vivo para o mesmo arquivo recusa [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 3
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (pidVivo(backup.pid)) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso V1`
pronto quando: com um backup do mesmo `src.js` cujo PID está vivo (o PID do próprio shell do teste), `--no-lugar` sai 4, a bateria não roda, `src.js` e o backup ficam intocados (V1). Antes da bateria pós-mutação, o stderr de uma execução normal no lugar traz o aviso de que o fonte real fica mutado até ela acabar (V2). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 5. `no-lugar: sim` no plano vira `--no-lugar` na catraca [tipo: implementar]
atende: D2, D4
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo-no-lugar.sh`
depende de: 4
prova: `bash scripts/testa-conferir-fluxo-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (noLugar) argumentos.push('--no-lugar');`
  para: `void 0;`
  bateria: `bash scripts/testa-conferir-fluxo-no-lugar.sh`
  fixture: `testa-conferir-fluxo-no-lugar.sh, caso F1`
pronto quando: num repo descartável com plano cuja tarefa declara `no-lugar: sim` e uma bateria que só fica vermelha quando roda na pasta real do repo (ela confere o próprio cwd contra a raiz real), `node scripts/conferir-fluxo.cjs mutacoes --slug <slug>` imprime `tarefa 1: vermelho` (F1). A mesma tarefa sem `no-lugar:` sai pela cópia e não fica `vermelho` (F2). Provado por `bash scripts/testa-conferir-fluxo-no-lugar.sh` com placar `0 falha(s)`.

### 6. A `cobertura` recusa `no-lugar:` com valor que não é `sim` [tipo: implementar]
atende: D2, D4
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo-no-lugar.sh`
depende de: 5
prova: `bash scripts/testa-conferir-fluxo-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (noLugarInvalido) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-fluxo-no-lugar.sh`
  fixture: `testa-conferir-fluxo-no-lugar.sh, caso C1`
pronto quando: com o plano declarando `no-lugar: talvez`, `node scripts/conferir-fluxo.cjs cobertura --slug <slug>` sai ≠ 0 nomeando a tarefa e o valor (C1). Com `no-lugar: sim` (crases opcionais), sai 0 sem acusar campo desconhecido (C2). Provado por `bash scripts/testa-conferir-fluxo-no-lugar.sh` com placar `0 falha(s)`.

### 7. Docs e versão 1.72.0 [tipo: docs]
atende: D5
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `skills/plano/SKILL.md`, `skills/plano/references/mutacao-no-lugar.md`, `scripts/conferir-mutacao.cjs`, `docs/rainforest/estado/2026-10-21-portaria-aviso-bash.json`
depende de: 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18
mutacao: n/a
  motivo: texto e número de versão, sem comportamento a inverter
pronto quando: com os dois `plugin.json` em `1.72.0`, `node scripts/conferir-versao.cjs` sai 0 com `versao 1.72.0`. O CHANGELOG abre com `## 1.72.0` e descreve o que D1 a D3 decidiram: o `--no-lugar` sem cópia, a restauração byte a byte em toda saída, a recusa com o alvo sujo ou com backup vivo, a restauração do backup órfão e o campo `no-lugar: sim` do plano. A seção `mutacao:` da skill `plano` aponta `references/mutacao-no-lugar.md`, que documenta o campo, as recusas e o risco que ele traz de volta (outra sessão lê o fonte mutado durante a bateria), e `bash scripts/testa-teto-skills.sh` sai 0. O estado do fluxo `2026-10-21-portaria-aviso-bash` entra com `fechar ok` e PR 574. O uso do `conferir-mutacao.cjs` (`USO`) lista `--no-lugar`. O README traz o badge `1.72.0`.

### 8. Arquivo editado durante o baseline não é mutado [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 4
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (!relido.equals(original)) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso R3`
pronto quando: com uma bateria que anexa `// EDICAO` ao `src.js` durante o baseline, `--no-lugar` sai 4 com "mudou durante o baseline", e o `src.js` termina com a edição (R3). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 9. Arquivo editado durante a bateria pós-mutação não é sobrescrito [tipo: implementar]
atende: D1, D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 8
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (atual && sha256(atual) !== restauro.hashMutado) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso R4`
pronto quando: com uma bateria que anexa `// EDICAO` ao `src.js` mutado, `--no-lugar` sai 1 com "mudou durante a bateria", o `src.js` termina com a edição e o backup fica no temporário (R4). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 10. Alvo que já é o original só apaga o backup [tipo: implementar]
atende: D1, D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 9
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (atual && atual.equals(restauro.original)) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso R2`
pronto quando: com o `src.js` somente-leitura, `--no-lugar` sai 1 sem mutar, sem "FALHA AO RESTAURAR" e sem backup no temporário; com a permissão de volta, a execução seguinte sai 0 (R2). Um backup órfão de PID morto com o arquivo já original é apagado sem aviso de backup órfão (O5). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 11. Backup de PID vivo não é restaurado por outra execução [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 10
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (pidVivo(Number(backup.pid))) continue;`
  para: `void 0;`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso O4`
pronto quando: com um backup do `src.js` cujo PID está vivo e o `src.js` com o hash mutado, outra execução não restaura o arquivo, o backup fica e ela sai 4 (O4). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 12. Restauração que falha sai 1 [tipo: implementar]
atende: D1, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 11
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `process.exitCode = 1;`
  para: `void 0;`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso R1`
pronto quando: com uma bateria que deixa o `src.js` mutado somente-leitura, `--no-lugar` sai 1 com "FALHA AO RESTAURAR", mesmo com a bateria vermelha, e o backup fica no temporário (R1). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 13. Alvo ignorado pelo git recusa [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 12
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `['status', '--porcelain', '--ignored', '--untracked-files=normal', '--', alvo]`
  para: `['status', '--porcelain', '--untracked-files=normal', '--', alvo]`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso I1`
pronto quando: com `ign.js` listado no `.gitignore` do repo descartável, `--no-lugar --arquivo ign.js` sai 4 e o stderr diz que o arquivo é ignorado (I1). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 14. `git status` que falha dentro do repo recusa [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 13
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (st.error || st.status !== 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso G1`
pronto quando: com o `.git/index` do repo descartável corrompido, `--no-lugar` sai 4 com "git status falhou", e o `src.js` fica intocado (G1). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 15. Falha de restauração chega ao `mutacoes` com o motivo e o backup [tipo: implementar]
atende: D1, D2, D4
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo-no-lugar.sh`
depende de: 6, 14
prova: `bash scripts/testa-conferir-fluxo-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `|| t.startsWith('FALHA AO RESTAURAR');`
  para: `|| false;`
  bateria: `bash scripts/testa-conferir-fluxo-no-lugar.sh`
  fixture: `testa-conferir-fluxo-no-lugar.sh, caso F3`
pronto quando: com o plano `no-lugar: sim` e uma bateria que edita o fonte mutado, `node scripts/conferir-fluxo.cjs mutacoes --slug <slug>` sai ≠ 0 e a linha da tarefa traz `FALHA AO RESTAURAR` e o caminho do backup (F3). Provado por `bash scripts/testa-conferir-fluxo-no-lugar.sh` com placar `0 falha(s)`.

### 16. Git que não reconhece um `.git` existente recusa [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 14
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (!naoERepo && (dentro.error || dentro.status !== 0)) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso G2`
pronto quando: com o `src.js` sujo e o `.git/HEAD` do repo descartável corrompido, `--no-lugar` sai 4 com "git rev-parse falhou" e o `src.js` sujo fica intacto (G2). Fora de repo de verdade, sem `.git` acima, segue medindo com aviso (S2). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 17. Alvo não rastreado recusa com `status.showUntrackedFiles=no` [tipo: implementar]
atende: D3, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 16
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `['status', '--porcelain', '--ignored', '--untracked-files=normal', '--', alvo]`
  para: `['status', '--porcelain', '--ignored', '--', alvo]`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso U1`
pronto quando: com o repo descartável em `status.showUntrackedFiles=no` (a configuração típica de dotfiles na home) e o alvo `novo.js` não rastreado, `--no-lugar` sai 4 e o stderr diz que o arquivo não é rastreado (U1). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.

### 18. A linha de sucesso não afirma a restauração [tipo: implementar]
atende: D1, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-no-lugar.sh`
depende de: 17
prova: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `console.log('    A bateria sabe falhar.');`
  para: `console.log('    A bateria sabe falhar, e o fonte foi restaurado.');`
  bateria: `bash scripts/testa-conferir-mutacao-no-lugar.sh`
  fixture: `testa-conferir-mutacao-no-lugar.sh, caso R4`
pronto quando: com uma bateria que edita o fonte mutado e sai vermelha, `--no-lugar` sai 1 com `FALHA AO RESTAURAR` no stderr, e o stdout não diz que o fonte foi restaurado (R4). Provado por `bash scripts/testa-conferir-mutacao-no-lugar.sh` com placar `0 falha(s)`.
