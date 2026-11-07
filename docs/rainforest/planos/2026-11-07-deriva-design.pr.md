## Resumo

Responde a pergunta "este design ainda vale?" para os designs já mergeados.

```
conferir-fluxo.cjs deriva [--slug <slug>] [--arquivo <caminho>]
  para cada plano (pasta pela configuração do projeto):
    decisões      = D<n> do design da linha Design:   (ou dos atende:, sem design legível)
    âncora da D<n> = arquivo + de: literal da mutação das tarefas que a atendem
    estado         = intacta | sumiu em <commit> | arquivo sumiu em <commit>
                     (git log -1 --first-parent -m -S<de>: pega também a remoção feita por merge)
  saída: só as perdidas (com --arquivo, também as intactas daquele arquivo)
         + "decisões: N com âncora (I intactas, P com âncora perdida), S sem âncora medível"
```

- `scripts/conferir-fluxo.cjs`: subcomando `deriva`, que reaproveita o `extrairTarefas` e o `extrairDecisoes` já existentes.
- `skills/brainstorm/SKILL.md`: antes da primeira rodada, roda `deriva --arquivo` em cada arquivo que a demanda vai tocar. Decisão intacta é restrição herdada; âncora perdida é deriva.
- Versão 2.8.0, com README e CHANGELOG.

Design: `docs/rainforest/design/2026-11-07-deriva-design.md` (D1 a D6). Plano: `docs/rainforest/planos/2026-11-07-deriva-design.md`. Origem: ideia `deriva-design-codigo-pos-merge`, vinda da skill `egm-drift-report` do `google/elephant-goldfish-model` (Apache-2.0). Só a ideia veio de lá; nada de código.

## Evidência

- **Entrada real, este repositório:**
  **Antes:** nada relia os designs depois do merge (`conferir-fluxo.cjs deriva` sai 1 com o uso).
  **Depois:** `deriva` sai 0 com 49 linhas e `decisões: 621 com âncora (508 intactas, 113 com âncora perdida), 759 sem âncora medível`. Exemplo:
  ```
  2026-08-24-orcamento-medida-estavel-e-folga D1, D2, D3, D4, D6, D7: scripts/testa-orcamento.sh — sumiu em cf1ad7689 Merge pull request #242 from luisfmontes/fluxo/zerar-issues
  2026-09-12-multihost-sobre-1-11 D3, D7: .codex-plugin/plugin.json — sumiu em c630a3e5 Merge pull request #347 from luisfmontes/fluxo/agente-sem-background
  ```
  Sem `--first-parent -m`, as duas linhas apontavam o commit que **pôs** o trecho (`3378f623e`, `070e55b4`). O defeito apareceu no executar e virou emenda do D3.
  `deriva --arquivo scripts/lib/complexidade.cjs` dá `complexidade-por-funcao D1, D2, D3, D4, D5, D6, D8: scripts/lib/complexidade.cjs — intacta`.
- **Bateria:** `testa-deriva.sh` dá `ok: 25 falhou: 0`, sobre uma fixture git com remoção por commit, arquivo apagado, remoção por merge, commit posterior que não mexe na âncora, decisão com âncora intacta e perdida, `de:` em prosa, `n/a`, `--slug`, `--arquivo` com `./`, caminho absoluto e contrabarra, aviso e erros de uso. `testa-conferir-fluxo.sh` segue com `ok: 142`.
- **Mutação:** com a catraca vermelha nas duas rodadas:
  - `intacta` sem o `includes(de)`, que é a mutação do plano;
  - sem `--first-parent -m`;
  - sem `-S`;
  - precedência intacta/perdida invertida;
  - filtro do `--arquivo` sem normalizar.
- **Plano:** o leitor cego achou 3 lacunas maiores, todas corrigidas antes do `ok`.
- **Revisão:** duas rodadas, as duas com `VEREDITO: ok`. Os achados da rodada 1 foram consertados neste PR: `--arquivo ./x` dava placar zero sem avisar, pasta de planos fixa, `Design:` com prosa e casos sem teste.

## Perigo de merge

**Porta:** mão dupla. O subcomando é novo, os antigos não mudam (142 ok), e o `brainstorm` ganha um parágrafo. Um revert desfaz tudo.
**Raio de impacto:** pequeno. É relatório: sai 0 e não barra nada.

## Deixado para depois

nada ficou para depois

Quatro achados baixos da revisão 2 ficam como limite declarado. Nenhum aparece na `main`; todos são borda de repositório de cliente:
- design que existe mas não usa `- **D<n> — ` deixa o placar zerado, com as linhas impressas;
- `Design:` apontando para uma pasta derruba o script com stack trace;
- o `RECUSADO` de `--slug` inexistente sugere `--plano`, que o `deriva` não aceita;
- `arquivo:` da âncora com `./` não casa com o filtro.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
