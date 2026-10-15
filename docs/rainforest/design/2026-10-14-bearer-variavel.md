# conferir-publicacao: `Authorization` com template JS ou concatenação de variável não é credencial (#494)

## Objetivo
A regra `credencial` de `scripts/conferir-publicacao.cjs` barra `` Authorization: `Bearer ${token}` `` e `authorization: 'Bearer ' + tok`, as duas formas mais comuns de montar header OAuth em JavaScript, embora nenhuma carregue segredo. O agente fica sem saída honesta e a tarefa precisa de redespacho (fluxo `2026-10-10-troca-de-conta`, tarefa 3). O conserto estende a isenção da #410 a essas formas, sem soltar literal.

## Decisões fechadas
- **D1 — Template literal JS (crase) conta como forma do esquema** — porquê: `` `Bearer ${token}` `` é o par exato de `"Bearer ${VAR}"`, que a #410 já isenta; só a crase ficou de fora do reconhecimento do esquema. Vale a mesma régua: a próxima palavra tem de ser INTEIRA referência (`${ident}`), sem literal colado.
- **D2 — Concatenação `'<esquema> ' + <expr>` passa quando `<expr>` é identificador, acesso a membro ou chamada sem argumento literal** — porquê: cobre `tok`, `this.token`, `process.env.X`, `getToken()`, `obterToken(conta)`; literal entre aspas no lado direito (`'Bearer ' + 'sk…'`) continua barrado, e é a forma em que um segredo apareceria. (Luís, Q1: recomendado.)
- **D3 — A isenção da concatenação vale só para `Authorization` com esquema (Bearer/Basic/Token)** — porquê: mesma estreiteza da #410; alargar para `password: 'x' + y` abriria fresta que nenhum caso real pediu. (Luís, Q2: recomendado.)
- **D4 — Bateria de dois lados com mutação** — porquê: critério de pronto da #494. Na seção 10c de `scripts/testa-conferir-publicacao.sh`: passam template com `${token}`, concatenação com identificador, membro e chamada; continuam barrados template com literal colado depois do `${}`, template com literal no lugar da referência, concatenação com literal entre aspas, e `password: 'x' + y`.

## Avaliado e descartado
- Isentar qualquer valor que contenha `${` ou `+`: solta literal colado (`'Bearer abc' + x`), que é segredo.

## Fora de escopo
- Concatenação em outras chaves de credencial (D3).
- Header montado em várias linhas (`h.set('Authorization', 'Bearer ' + tok)` já passa por não casar `authorization:`/`=`).

## Varredura
docs/rainforest/varredura/2026-10-14-bearer-variavel.txt — só o ramo da #410 trata esquema; crase e `+` nunca foram cobertos. Mudou: confirmou que é extensão do ramo da #410, não regra nova.

## Em aberto
