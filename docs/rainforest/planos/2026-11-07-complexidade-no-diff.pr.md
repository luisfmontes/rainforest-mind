## Resumo

O `enxugar --diff` passa a abrir pela função que a mudança deixou mais confusa.

```
catalogo-funcoes.cjs variacao [--raiz <dir>] [--base <ref>]
  base padrão = merge-base(HEAD, origin/<padrão>)   (baseDoDiff, a mesma do revisor)
  arquivos    = git diff --name-only <base> -- + não rastreados, com os filtros do complexas
  por arquivo: mede base (git show) e disco com a mesma medida do complexas
               função tocada = faixa [linha, fim] cruza linha nova (disco) ou removida (base)
               pareia por nome e ordem; sem par → nova / removida
  saída: maior subida primeiro, (=) no fim, lacunas (base)/(atual), linha de aproximação
```

- `scripts/catalogo-funcoes.cjs`: subcomando `variacao` e ajudantes. `definicoesDoArquivo` passa a usar `definicoesDoTexto`, que mede o lado da base sem gravar arquivo.
- `hooks/lib/achados-revisor.cjs`: só exporta `baseDoDiff`.
- `skills/enxugar/SKILL.md`: o modo 1 abre com `variacao`, como contexto que não vira tag nem entra no `líquido:`. "cinco tipos" foi corrigido para "seis tipos".
- Versão 2.7.0, com README e CHANGELOG.

Design: `docs/rainforest/design/2026-11-07-complexidade-no-diff.md` (D1 a D7). Plano: `docs/rainforest/planos/2026-11-07-complexidade-no-diff.md`. Segundo recorte da avaliação do `lboel/untangle`; nada do código dele foi copiado (AGPL).

## Evidência

- **Entrada real, este repositório contra a base `1d5782b9`:**
  **Antes:** `node scripts/catalogo-funcoes.cjs variacao` sai 1 com o uso, porque o subcomando não existe.
  **Depois:**
  ```
  nova → 20 cognitiva (+20)  nova → 17 ciclomática  scripts/catalogo-funcoes.cjs:L326 tocadasDoArquivo
  nova → 15 cognitiva (+15)  nova → 13 ciclomática  scripts/catalogo-funcoes.cjs:L393 variacao
  26 → 35 cognitiva (+9)  20 → 26 ciclomática  scripts/catalogo-funcoes.cjs:L513 principal
  ...
  7 → 0 cognitiva (-7)  5 → 1 ciclomática  scripts/catalogo-funcoes.cjs:L157 definicoesDoArquivo
  medida aproximada (leitura de texto, sem parser): confira no código antes de concluir
  ```
  Na primeira versão, a própria `variacao` tinha cognitiva 92. A ferramenta apontou isso, e ela foi partida em funções menores antes da revisão.
- **Baterias:** `testa-catalogo-funcoes.sh` dá `ok: 180 falhou: 0`; as seções 17 e 18 são novas. `testa-enxugar-estrutura.sh` dá 33/33. `testa-teto-skills`, `testa-versao` e `testa-plugin-codex` ficam verdes, e `conferir-versao` sai 0.
- **Mutação, com a catraca `conferir-mutacao.cjs` vermelha nas duas rodadas de cada uma:**
  - `tocadaBase` sem `cruza(removidas, m)` derruba a remoção pura (caso 17).
  - O `--` depois da base derruba a base com nome de pasta.
  - Tirar `semPar` derruba a lacuna `(base)`.
  - Trocar o `throw` da falha de git derruba o índice corrompido.
  - Tirar `depoisDe` derruba a lacuna nova `(atual)`.
  - No `SKILL.md`, tirar o `variacao` derruba o caso D6.
- **Plano:** o leitor cego (o passo da 2.6.0, usado aqui pela primeira vez) achou 4 lacunas maiores, corrigidas antes do `ok`.
- **Revisão:** três rodadas, todas `VEREDITO: ok`.
  - A 1 achou a base ambígua com pasta de mesmo nome, que dava "nenhuma função" com exit 0, e a lacuna da base escondida atrás de uma `nova`.
  - A 2 achou dois ramos sem caso de teste.
  - Todos esses achados foram consertados neste PR.

## Perigo de merge

**Porta:** mão dupla. O subcomando é novo, e o código existente só ganha o `definicoesDoTexto` e um export; um revert desfaz tudo.
**Raio de impacto:** pequeno. `listar`, `maiores` e `complexas` saem como antes (casos 1 a 16 verdes), e a `variacao` é contexto: sai 0 com qualquer variação e não barra nada.

## Deixado para depois

nada ficou para depois

Dois achados baixos da revisão 3 ficaram como limite declarado, sem conserto:
- `git show` que falha por motivo diferente de "arquivo não existe na base" faz o arquivo sair inteiro como `nova`;
- a guarda de erro do diff por arquivo não tem caso próprio na bateria (a guarda do diff de arquivos tem).

São raros, porque a base já passou pelo `rev-parse` e os arquivos pela listagem do diff, e a saída continua dizendo que a medida é aproximada.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
