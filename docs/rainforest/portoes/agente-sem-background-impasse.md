# Impasse: agente-sem-background — 3 reprovações no `revisar`

## Histórico
- **Revisão 1** (reprovada): caminho direto sem interpretador (`scripts/testa-estado.sh`, MSYS, Windows), `scripts/varrer-baterias.sh` direto, continuação `\`+quebra, subshell `( … )` e `$( … )` passavam com exit 0.
- **Revisão 2** (reprovada): a segmentação cortava dentro de aspas, o que barrava commit e corpo de PR com `&&`, `;` ou crase ao lado do nome de uma bateria. Envoltório com flag (`nice -n 10`, `timeout -k 5 300`, `env -i`) escondia a bateria.
- **Revisão 3** (a primeira tentativa caiu por ECONNRESET sem veredito; o redespacho reprovou). O revisor não achou falso positivo em leitura ou manipulação, nem crash. Restaram três pontos de borda:
  1. `find hooks -name 'testa-*.sh' -exec bash {} \;` e `find … | xargs -I{} bash {}` passam: o nome do script só existe em runtime.
  2. `stdbuf -oL bash hooks/testa-x.sh` passa: `stdbuf` não está na lista de envoltórios.
  3. `bash -n hooks/testa-x.sh` e `node --check hooks/testa-x.cjs` são barrados, mas só checam sintaxe.

## Decisão do usuário (2026-09-27, Q1 opção a)
Haverá uma 4ª rodada pequena e fechada:
- `stdbuf` entra nos envoltórios;
- `bash -n` e `node --check` deixam de ser barrados;
- o design declara `find -exec {}` e `xargs … {}` fora de escopo, porque o nome só aparece em runtime (mesma classe do `for f in …; do bash $f`).

O revisor 4 confere só isso. Se achar outro buraco, ele vira issue e a entrega segue.
