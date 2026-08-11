---
name: verificar
description: Use no estágio 'verificar' da esteira rainforest-mind — depois de 'executar' e 'revisar' fechados, roda o critério de cada tarefa do plano contra o artefato real e decide ok ou reprovado. Nunca redige critério novo, só executa o que o plano já definiu.
---

# Verificar

Abre sempre com:

```
node scripts/estado.cjs exigir --slug <slug> --estagio verificar
```

Exit 2 significa que `executar` ou `revisar` ainda não fecharam — pare e
rode o que falta antes, não force `marcar` por cima. A própria saída do
comando nomeia o estágio bloqueado.

Antes de aplicar a regra que sustenta esta skill, carregue
`Skill(rainforest-mind)` e leia a **regra 12** inteira (a elaboração —
incidentes, cuidados finos — fica atrás do `<!-- detalhe -->` e não vem na
injeção de abertura). Esta skill é a regra 12 virando estágio da esteira:
mesmo princípio, aplicado a um artefato específico em vez de a um agente.

## O que valida

Uma tarefa por vez, na ordem do plano (`docs/rainforest/` da esteira em
curso). O critério de cada tarefa **já veio pronto de lá** — comando exato
e saída esperada, definidos no estágio `plano`. Aqui ele é **executado**,
nunca redigido nem afrouxado: se o plano não deixou um critério
falsificável para alguma tarefa, isso é falha do estágio `plano`, não
licença para inventar um agora — registre a lacuna e trate como critério
não cumprido.

**Validação é rodar o artefato real e olhar a saída.** Suíte relatada
como verde não é evidência; relato de agente (o seu de uma rodada anterior,
ou o de um subagente) não é evidência. Rode o comando do critério, leia a
saída literal, e só então decida. **✅ sem o comando e a saída colados no
relatório = não feito** — vale para o relatório desta skill tanto quanto
para o de qualquer agente despachado.

Quem verifica não afrouxa a régua. Critério que não passou é **reprovado**,
nunca "passou com ressalva", "não afeta o essencial" ou renomeado para
observação. A régua é do plano; quem verifica só lê o resultado dela.

## Cuidado nomeado: exit code através de pipe não é exit code

`comando | tail`, `| grep`, `| head` devolvem o status do **último elo do
pipe**, não do comando que importa. `docker build ... | tail -5` pode sair
0 mesmo com o build quebrado, porque o 0 é do `tail`. Quando o exit code é
o próprio sinal do critério, não canalize — capture com
`${PIPESTATUS[0]}` (bash) ou rode sem pipe e leia a saída à parte.

## Fechamento

Todo critério passou:

```
node scripts/estado.cjs marcar --slug <slug> --estagio verificar --status ok \
  --json '{"comando":"...","saida":"..."}'
```

Algum critério falhou:

```
node scripts/estado.cjs marcar --slug <slug> --estagio verificar --status reprovado \
  --json '{"criterio":"...","comando":"...","saida":"...","faltou":"..."}'
```

`reprovado` devolve o trabalho ao estágio `executar` — é o mecanismo da
esteira, não uma anotação: a tarefa reprovada precisa ser corrigida e
reentrar em `revisar` antes de voltar aqui.

## Condição de parada

Critério que **não pode ser executado neste ambiente** — ferramenta
ausente, acesso que falta, dependência fora do ar — não é dado por
cumprido. Vira `reprovado` com o que faltou nomeado no `--json`, nunca
aprovação por falta de prova. "Não deu para testar, mas o código parece
certo" é exatamente o relato que a regra 12 existe para barrar.
