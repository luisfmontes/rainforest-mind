---
description: Monta a pasta de dados do rainforest e liga/desliga o que é opcional — por projeto ou para tudo
argument-hint: [vazio mostra o estado; ou "desliga o gate de staging aqui"]
---

Carregue `Skill(setup)` e conduza `$ARGUMENTS` — ou, se vazio, mostre o estado.

Comece **sempre** por `node scripts/setup.cjs`, que não escreve nada: ele diz
onde está a pasta de dados, o que está ligado e **de onde veio cada valor**. Leia
isso ao Luís antes de propor mudança.

Dois pontos param e esperam a palavra dele, e não são formalidade:

- **`nivel: plugin`** na pasta de dados significa que o foco e as ideias que
  aparecem na abertura são **de quem publicou o plugin**, não dele. Diga assim.
- **`--escopo projeto`** grava dentro do repositório e pode acabar no commit de
  outra pessoa. A pergunta é "só aqui ou em tudo?", e o padrão é `usuario`.

O que criar de automação neste projeto é outra pergunta e tem dono oficial: a
skill `claude-automation-recommender`, do plugin `claude-code-setup`. Aponte
para ela em vez de opinar.
