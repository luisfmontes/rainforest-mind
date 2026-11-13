## Resumo

Reuso antes de criar: o plano procura função existente antes de mandar criar outra, e o revisar confere o que o diff criou.

```
catalogo-funcoes.cjs
  listar  ── passa a ler Method x(...) [as T [Of U]] Class Y[.Z]  →  "Y:x"
              (assinatura quebrada com ; é juntada só em linha que abre definição, até 50 linhas)
  novas   ── NOVO: funções que o diff cria em relação a --base

conferir-busca.cjs (no marcar plano)
  tarefa implementar que cria OU edita código
    └─ busca: exige canal catalogo  (- catalogo | listar --raiz <pasta> | reaproveito X de arq:linha | nada equivalente | pulado: <motivo>)
         └─ cada arq:linha da linha: existe? dentro do repo? extensão lida? começa definição?
            fora de crase, .ext:N não lida por inteiro → recusa pedindo crase (nunca pulada)

revisar
  └─ (b2) novas --base <base> × catálogo do repo: duplicata HIGH reprova
```

Versão 2.14.0 (MINOR: contrato novo do `busca:`).

## Evidência

- **Antes:** `node scripts/catalogo-funcoes.cjs listar` num `.tlpp` com `Method calcular(...) Class SaldoProjeto` não devolvia o método; no template Protheus medido, 142 métodos ficavam de fora.
  **Depois:** o mesmo `listar` devolve `lib/saldo.tlpp:4:SaldoProjeto:calcular`, e também `Foo:Baz` (parêntese aninhado), `Foo:Qux` (`as Array Of Object`), `Foo.Sub:Corge` e `Foo:Quux` (assinatura com `;`).
- **Antes:** um plano com tarefa que só edita código existente, sem `busca:`, fechava o `marcar plano`.
  **Depois:** `node scripts/conferir-busca.cjs plano --slug zerar-issues-9` sai 2. Este plano sai 0 com `ok: 9 tarefa(s) com caminho de código, todas com busca: e desfecho:`.
- **Referência inventada:** `reaproveito soma de src/x.js:4` (linha que não é definição) → exit 2. `pages/[nada].tsx:99` sem crase → exit 2 pedindo crase. `` `Ponto de Entrada/69 - Gestão de Contratos/MT100.prw:1` `` entre crases → conferida inteira.
- **Catraca de mutação:** vermelha nas 9 tarefas com alvo, rodada de novo pela integração e pelo `marcar verificar ok`.
- **Baterias:** as 48 que o `baterias-do-diff` listou antes da tarefa 16 saíram 0, entre elas `testa-saude` (94 ok), `testa-estado-reabrir` (97 ok), `testa-conferir-busca` (total=68 vermelhas:[]) e `testa-catalogo-funcoes` (206 ok). A `testa-estado.sh` (337 ok) rodou à parte, porque o `marcar plano` dela chama o `conferir-busca`.
- **CI:** a primeira rodada deste PR ficou vermelha em `testa-plugin-codex.sh`, porque a âncora binária do corpo de `skills/modo-dev/SKILL.md` não acompanhou a tarefa 10. A tarefa 16 re-mediu a âncora (+233 bytes, só o Degrau 2b), e a bateria sai 0.
- Seis revisões independentes, todas `VEREDITO: ok`. Os achados de cada uma foram consertados neste PR (tarefas 8 a 16).

## Perigo de merge

**Porta:** mão dupla. É código de checador e doc, e um revert desfaz.
**Raio de impacto:** médio. Plano em andamento com tarefa `implementar` que só edita código passa a precisar da linha `catalogo` (ou `- catalogo | pulado: <motivo>`) para fechar o `marcar plano`. Planos já fechados não são reconferidos.

## Decidido sem você

- A revisão 4 marcou `[design]` o falso verde de referência com colchete sem crase. Não parei o fluxo: o design não fixa a regex, só o D3 (conferir cada `arquivo:linha`), e a correção (tarefa 14) cumpre o D3. Toda ocorrência `.ext:N` fora de crase é conferida ou recusada, nunca pulada.

## Deixado para depois

nada ficou para depois

Achado preexistente da revisão 5, fora deste diff: #709. Uma referência escrita na linha de continuação de um item do `busca:` escapa da conferência.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
