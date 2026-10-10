# Reprovado: o laço

Design: `docs/rainforest/design/2026-10-10-laco-executor-revisor.md`
(enxerto do `execute` do plugin `wildz-data`, de Rafael Siqueira).

Revisor que reprova devolve o trabalho ao executor **sem esperar o usuário e
sem a mão da janela na crítica**. A janela principal gira o laço até o
revisor dar `ok`, até o teto, ou até um achado de design (D1).

## Cada volta

1. `marcar --estagio revisar --status reprovado` como sempre — ele exige o
   veredito `reprovado` gravado pelo hook e reabre o `executar`.
2. Extraia a crítica:

   ```
   node scripts/critica-do-revisor.cjs --slug <slug>
   ```

   | exit | o que fazer |
   |---|---|
   | `0` | segue para o passo 3 com a saída como está |
   | `3` | achado `[design]`: **pare o laço** e leve a crítica ao usuário — o executor não pode mudar decisão (D5) |
   | `4` | não há `reprovado` gravado, ou ele veio sem achado: o laço não tem o que ler; o revisor não fechou o contrato de veredito |
   | `69` | transcrito sumiu: bloqueio de ambiente (regra 14), anuncie e pare |

3. `node scripts/estado.cjs exigir --slug <slug> --estagio executar` — é ele
   que aplica o teto; exit 2 encerra o laço (veja **Teto**). Passando,
   redespache o executor: **despacho novo** (`isolation: "worktree"`, nunca
   `SendMessage` — regra 11), base = HEAD do worktree do fluxo, briefing
   original **mais** um bloco `## Achados do último revisor` com a saída do
   passo 2 colada **literal**. Só a última crítica, nunca o histórico das
   voltas anteriores; nenhuma paráfrase sua (D3).
4. Integre e confira como em qualquer entrega (`conferir-entrega`, critério,
   catraca de mutação), feche o `executar` e rode o revisor de novo.

## Teto

O laço não conta nada: quem conta é o `estado.cjs` (`TETO_TENTATIVAS = 3`).
Depois da 3ª reprovação, o `exigir --estagio executar` do passo 3 recusa
(exit 2); a próxima volta só com
o impasse escrito em `docs/rainforest/portoes/<slug>-impasse.md`, a palavra do
usuário e `liberar --estagio revisar --rodada-extra "<o que ele disse>"` (D2).

## O que o laço não protege

Revisor errado. Achado falso gasta voltas até o teto — o teto é o limite
desse custo, não um juiz do revisor (D4).
