# Bateria que monta caixa leva as libs que os scripts copiados exigem

## Objetivo
Um checador barato acusa, antes do CI de ~25 min, a bateria cuja caixa copia um script do repositório sem copiar o `.cjs` que ele carrega por `require` — a classe que derrubou o CI em 2026-09-12, 2026-10-05, 2026-10-19 e 2026-11-09, e que em outras baterias vira "pulada (erro de execução)" com a bateria verde.

Brainstorm conduzido em modo autônomo (autorização do Luís em 2026-11-11: "pode decidir e executar no automatico"). Toda decisão abaixo é **decidido pela sessão**, com a opção recomendada, aberta a veto no PR.

## Decisões fechadas
- **D1 — Checador estático `scripts/conferir-caixas.cjs`, sem executar bateria.** Para cada `hooks/testa-*.sh` e `scripts/testa-*.sh`, o conjunto copiado é o dos caminhos `$<VAR>/scripts/...cjs` e `$<VAR>/hooks/...cjs` que aparecem em linha com `cp`, mais a expansão do laço de uma linha `for <v> in a b c; do` cujas linhas de `cp` usam `$<v>` (a forma de 11 baterias: `for lib in raiz config ...; do cp "$SRC/hooks/lib/$lib.cjs" ...`). Bateria com `cp -r` da pasta `hooks` ou `scripts` inteira é pulada (7 baterias): a caixa tem tudo. — porquê: medido em 2026-11-11, os 4 episódios de CI vermelho da classe tinham o script copiado sem a lib; conferir pelo texto da bateria acusa em segundos o que o CI acusa em 25 min, e acusa também o caso que o CI não vê (bateria que degrada para "pulada" e fica verde).
- **D2 — Requires de topo e tardios, transitivos.** De cada `.cjs` copiado, o checador lê os `require` literais — `require(path.join(__dirname, 'a', 'b.cjs'))` e `require('./x.cjs')` / `require('../hooks/lib/x.cjs')` — no topo **e** dentro de função, resolve o caminho relativo ao arquivo e repete para o `.cjs` achado que também está no conjunto. — porquê: o episódio de 2026-10-19 foi um `require('./conferir-fluxo.cjs')` tardio do `estado.cjs` que derrubou o caso `(d)` de uma bateria; restringir a `require` de topo deixaria passar 1 dos 4 episódios medidos.
- **D3 — Ausência intencional se declara na própria bateria:** linha `# caixa-sem: <caminho do repo> — <motivo>`. Sem motivo, a linha não vale e o achado continua. — porquê: há `require` tardio em `try/catch` que degrada de propósito (o `painel-fluxo.cjs` do `estado.cjs:2339` sai como "aviso: painel" em bateria verde hoje). Lista central de exceções esconde a decisão longe da caixa que a toma; a linha na bateria fica ao lado do `cp` que falta.
- **D4 — Onde roda:** `scripts/varrer-baterias.sh` chama o checador antes do laço das baterias e conta saída ≠ 0 como bateria vermelha (`conferir-caixas`), e a bateria `scripts/testa-conferir-caixas.sh` prova o checador com fixtures. — porquê: o `varrer-baterias` é o que o CI e a verificação local rodam; entrar ali põe o checador nos dois sem passo novo para lembrar.
- **D5 — Modelo de ameaça e parada.** Protege contra esquecimento ao acrescentar `require` a script que alguma bateria copia. Fica fora: `require` com caminho montado em variável, `cp` com origem montada por variável fora do laço de uma linha, laço de várias linhas, scripts em outra linguagem, e módulos do Node. O checador reimplementa um pedaço da gramática do bash, então achado de revisão nessas classes não reabre o fluxo — vira ideia.

## Avaliado e descartado
- **Detector de execução (procurar `Cannot find module` na saída de cada bateria):** pega tudo que o Node imprime, mas só depois de rodar as baterias, que é o custo que se quer evitar, e o "aviso: painel" das baterias verdes vira ruído sem um lugar para declarar a intenção.
- **Helper que copia o script com as dependências (reescrever a montagem das 43 caixas):** elimina a classe na raiz, mas mexe em 43 baterias longas de uma vez para um problema que custou 4 CIs em 2 meses; o checador resolve com raio pequeno e deixa o helper como evolução se a classe voltar.

## Fora de escopo
- Corrigir as caixas que hoje degradam para aviso de propósito: elas ganham a linha `caixa-sem` (D3), não `cp` novo.

## Varredura
docs/rainforest/varredura/caixa-confere-requires.txt — só a própria ideia `caixa-de-bateria-confere-requires` trata da classe; as outras ideias casadas são da catraca de mutação (duração, pycache, cmd.exe, teto de 20%) e não se sobrepõem. Nenhuma Issue ou branch aberta sobre o tema.

## Em aberto
