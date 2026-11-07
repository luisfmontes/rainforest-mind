# Diagnóstico cego

Detalhe do passo de diagnóstico cego da Fase 3 do `skills/depurar/SKILL.md`.

## Por que existe

A Fase 3 pede de 3 a 5 hipóteses para não ancorar na primeira. Mas quem gera e quem ranqueia
as hipóteses é a mesma sessão, que já leu código, já ouviu o palpite do usuário e já tem uma
favorita. Um segundo diagnóstico que recebe **só o sintoma e o repro**, nunca a hipótese, não
herda essa âncora. Quando os dois discordam, a discordância é informação: aponta o lugar em que
a sessão deixou de olhar.

## Quando e como

No começo da Fase 3, com o loop da Fase 1 e o repro mínimo da Fase 2 em mãos (no caminho do
subagente `depurador`, abaixo, o repro pode ainda não existir):

1. Despache o diagnóstico em background: `subagent_type: "general-purpose"`, com
   `model: "sonnet"`, sem `isolation` (ele não edita).
2. **Enquanto ele roda, escreva as suas hipóteses** ranqueadas, do jeito que a Fase 3 manda.
   Escrever antes de ler o dele é o que torna a comparação honesta.
3. Só então leia o dele e compare (abaixo).

Bug trivial já está fora da skill, e o passo vale para todo o resto.

**Rodando dentro do subagente `depurador`**, que não tem a ferramenta Agent, pule o passo e diga
no relato: "diagnóstico cego não rodou: sem Agent neste contexto". Nesse caminho, o diagnóstico
cego é de quem despachou: a janela principal despacha o `depurador` e o diagnóstico cego juntos,
e compara os dois relatos pelo procedimento abaixo. No despacho conjunto, as Fases 1 e 2 ainda
não rodaram, porque são trabalho do `depurador`. Então o `Repro:` do prompt leva o que o usuário
descreveu, ou `nenhum ainda: o sintoma é tudo o que se sabe`. Nunca invente um repro para
preencher o campo. As hipóteses que entram na comparação são as do relato do `depurador`.

## Prompt

Preencha as duas linhas e mande o resto como está. **Não ponha a sua hipótese, a área suspeita
nem o palpite do usuário**: é essa ausência que faz o passo valer.

```
Diagnóstico independente de um defeito neste repositório: <caminho absoluto da raiz>.
O arquivo de instruções do projeto na raiz (CLAUDE.md ou AGENTS.md), se existir, descreve a
arquitetura.

Sintoma: <o que se observa, com a saída real colada>
Repro: <o comando ou os passos que reproduzem, como a Fase 1 e a Fase 2 deixaram; no despacho
conjunto com o depurador, o que o usuário descreveu, ou "nenhum ainda: o sintoma é tudo o que se sabe">

Investigue. Onde o defeito mais provavelmente mora? Cite `arquivo:linha`. Liste de 1 a 3 causas
candidatas, da mais para a menos provável. Para cada uma, dê:
- a evidência no código que a sustenta;
- uma checagem concreta que prova ou derruba essa causa (teste, asserção, linha de log,
  comando) e o resultado que cada desfecho mostraria.

Não proponha conserto. Não edite arquivo e não rode comando que escreva. Não leia mensagens de
commit nem o histórico do git: o diagnóstico tem que sair do código e do repro.

Termine com a linha: diagnóstico completo
```

## Comparar e desempatar

- **Concordam** (a candidata nº 1 dele é a sua hipótese nº 1): siga para a Fase 4 e registre que
  a concordância é fraca, porque os dois são o mesmo modelo.
- **Discordam:** reler código não desempata. Para a sua hipótese nº 1 e para a candidata nº 1
  dele, use a checagem que ele deu, ou escreva a menor checagem cujo resultado **muda conforme
  qual das causas é a real**. Rode as duas e monte a tabela:

  | Candidata | Checagem | Resultado | Veredito |
  |---|---|---|---|

  A checagem que capturar o defeito vira o teste da Fase 5. As outras saem na limpeza da Fase 6.
- **Inconclusivo:** leve a escolha ao usuário, com a tabela, antes de qualquer conserto.

Diga ao usuário, no fim, se a causa confirmada era a sua primeira hipótese.

Origem: comando `eg-fix-bug` do `Raj9914/elephant-goldfish` (MIT), Step 2 e o procedimento
`settle-disagreement`, reescritos para o fluxo daqui; o crédito está no design
`2026-11-07-leitores-cegos`.
