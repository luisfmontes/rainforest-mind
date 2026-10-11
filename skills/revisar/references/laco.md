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

## Flaky

Design: `docs/rainforest/design/2026-10-10-flaky-teto.md` (D2 a D17).
Bateria instável aprova ou reprova entrega por acaso. Por isso, no passo 4
da volta, a integração **não** roda o critério nem a catraca à mão:

- o critério de cada tarefa roda por
  `node scripts/rodar-gate.cjs --comando '<bateria>' --slug <slug> --tarefa <n>`;
- a catraca de mutação roda por `node scripts/conferir-mutacao.cjs ...`
  com `--slug <slug> --tarefa <n>` (os dois ou nenhum).

A nova tentativa mora nesses scripts, nunca na sua prosa (D4): o exit de
cada um **vale depois dela**. Bateria verde só na nova tentativa sai 0 e
grava um flake no estado (`node scripts/estado.cjs registrar-flake`);
vermelha nas duas sai 2. Falha ao gravar o flake é só aviso e não muda o exit.

O mesmo gate (tarefa mais bateria) que só passa na nova tentativa em duas
voltas seguidas é terminal. O `registrar-flake` imprime `FLAKY TERMINAL` e o
comando que fecha o estágio:

```
node scripts/estado.cjs marcar --slug <slug> --estagio executar --status flaky
```

Feche assim e **suba ao usuário**: `flaky` não é reprovação e não consome
`TETO_TENTATIVAS` (D6). O `exigir --estagio executar` recusa até a palavra
dele e o `estado.cjs liberar --slug <slug> --estagio executar`, que vale uma
rodada. Flake de uma volta só fica gravado e o laço segue.

## Teto de despachos

O hook `hooks/gate-teto-despachos.cjs` conta todo despacho de agente do
fluxo ativo (inclusive o que a portaria nega) e nega, com exit 2, o despacho
que passa do teto. O teto padrão de 40 despachos vale quando o plano não
declara outro; o plano declara com `teto-despachos: N` no cabeçalho (veja
`skills/plano/references/teto-despachos.md`). Não há liga/desliga nem
variável de escape (D15). A única porta acima do teto, com a palavra do
usuário:

```
node scripts/estado.cjs liberar-teto --slug <slug> --motivo "<o que ele disse>"
```

Cada liberação soma +10 despachos ao teto e grava o motivo no estado; o
`--motivo` vazio é recusado. Subagente com despacho negado não pede liberação:
pare e reporte à janela principal.

**Não protegem**, na ordem do D3: bateria **determinística** que mede a coisa
errada (é da catraca de mutação, não do flaky) e agente despachado **fora de
fluxo** (é da portaria; o teto nem o conta).
