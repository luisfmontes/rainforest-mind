# Backup externo falha quando o rainforest.db está aberto por outra sessão

## Objetivo
Fazer o `scripts/backup.cjs gravar` produzir o zip diário mesmo com o
`rainforest.db` aberto por uma sessão do Claude Code. Hoje o `Compress-Archive`
não abre um arquivo que outro processo mantém aberto para escrita, e o zip
inteiro falha com exit 2: foram seis rondas do sentinela sem backup externo
(11, 21, 22, 23, 25 e 29/09), todas com sessão aberta na hora. A causa foi
reproduzida numa caixa de testes: com uma conexão `node:sqlite` aberta o
`Compress-Archive` sai 1 ("O processo não pode acessar o arquivo"), e com a
conexão fechada sai 0.

## Decisões fechadas
- **D1 — O `gravar` não zipa o `rainforest.db` vivo: tira antes uma cópia consistente com `VACUUM INTO` (conexão `node:sqlite` só de leitura) num diretório temporário próprio (`fs.mkdtempSync` em `os.tmpdir()`), com o nome `rainforest.db`, e é essa cópia que entra no zip, na raiz como hoje; o diretório temporário é removido no fim, com sucesso ou falha** — porquê: `VACUUM INTO` lê pela própria SQLite, que convive com a conexão aberta; na caixa de testes, o zip da cópia saiu 0 com a conexão ainda aberta. Também evita guardar um banco pego no meio de uma escrita.
- **D2 — Se a cópia do banco falhar (banco corrompido, `node:sqlite` ausente, `VACUUM INTO` com erro), o `gravar` zipa os demais itens da lista D10, renomeia o zip para o nome final e sai 2 com `RECUSADO: rainforest.db ficou fora do backup: <motivo>`** — porquê: um arquivo não pode tirar do backup o FOCO.md e as ideias, que foi o custo dos seis dias. O exit 2 mantém a linha no `vigias/ERROS.md` (o `backup-estado.ps1` já registra a linha `RECUSADO`), e o `conferir` desse zip reprova pela direção origem → zip ("existe na origem e nao esta no zip").
- **D3 — O `conferir` prova o `rainforest.db` do zip por restauração, não por hash: abre o arquivo extraído só para leitura e exige `PRAGMA integrity_check` = `ok`; os outros arquivos continuam na comparação por hash** — porquê: a cópia do `VACUUM INTO` nunca tem o hash do arquivo vivo, e o hash de um banco vivo já divergia em qualquer dia com escrita depois do zip. O que o `conferir` precisa provar é que o backup restaura.
- **D4 — Baterias: o `rainforest.db` de zeros de `scripts/testa-backup-gravar.sh` e `scripts/testa-backup-conferir.sh` vira um SQLite de verdade, criado com `node:sqlite`; o `gravar` ganha um caso que mantém uma conexão aberta no banco durante a execução e exige exit 0, com o banco do zip passando no `integrity_check`; o `conferir` ganha um caso em que o `rainforest.db` do zip está corrompido e exige reprovação** — porquê: é a reprodução de hoje transformada em caso de teste. Com o banco de zeros, a cópia nem roda.
- **D5 — Entrega: um PR com bump de patch sobre `origin/main` e a nota no CHANGELOG** — porquê: é conserto, sem contrato novo (tabela do `CONTRIBUTING.md`).

## Avaliado e descartado
- Zipar o banco vivo abrindo com `FileShare.ReadWrite` (cópia por .NET em vez de `Compress-Archive`): lê bytes no meio de uma escrita e pode guardar um banco inconsistente; `VACUUM INTO` dá a mesma disponibilidade com consistência.
- Pular o backup do dia quando o banco está em uso (como hoje): é o defeito.

## Fora de escopo
- Mudar a hora da ronda do sentinela para fugir das sessões abertas: contorna em vez de consertar e ainda falharia em sessão madrugada adentro.
- Os outros itens da lista D10 também poderiam estar abertos para escrita; nenhum apareceu nas falhas registradas.

## Em aberto
(nenhum)
