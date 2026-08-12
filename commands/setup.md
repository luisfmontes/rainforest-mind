---
description: Monta a pasta de dados do rainforest e liga/desliga o que é opcional — por projeto ou para tudo
argument-hint: [vazio mostra o estado; ou "desliga o gate de staging aqui"]
---

Carregue `Skill(setup)` e conduza `$ARGUMENTS` — ou, se vazio, mostre o estado.

Comece **sempre** por `node scripts/setup.cjs`, que não escreve nada: ele diz
onde está a pasta de dados, o que está ligado e **de onde veio cada valor**. Leia
isso ao usuário antes de propor mudança.

Dois pontos param e esperam a palavra dele, e não são formalidade:

- **`nivel: plugin`** na pasta de dados significa que o foco e as ideias que
  aparecem na abertura são **de quem publicou o plugin**, não dele. Diga assim.
- **`--escopo projeto`** grava dentro do repositório e pode acabar no commit de
  outra pessoa. A pergunta é "só aqui ou em tudo?", e o padrão é `usuario`.

**Caminho de projeto também é setup.** A seção `PROJETOS` do estado mostra o
vocabulário de slugs (`slug -> pasta`), que é o que vai no campo `projeto` das
ideias e o que o `semear` usa para traduzir pasta em slug:

```
node scripts/setup.cjs --projeto <slug> --caminho <dir> [--apelido a,b]
node scripts/setup.cjs --remover-projeto <slug>
```

Duas coisas que o estado já denuncia e você deve ler em voz alta quando
aparecerem: caminho marcado **`<- NAO EXISTE nesta maquina`** (o `semear` nunca
vai casar aquela pasta com o slug, e o erro é silencioso), e **um slug por
repositório** — frente, cliente ou branch dentro do repo vão no `projeto_nota`,
não em slug novo.

**As pontes também são setup.** A seção `PONTES` diz quais agentes recebem as
regras deste plugin (`ponte-claude`, `ponte-codex`, `ponte-gemini`, todas
desligadas por padrão) — e é o que o `/ponte` usa como alvo quando ninguém passa
`--agente`. O que o `/setup` **não** guarda, de propósito: em quais repositórios a
ponte já foi gerada. Isso é estado que envelhece sem ninguém conferir, e o arquivo
no repo (com o marcador `rainforest-mind:inicio`) é a fonte da verdade.

**Os vigias nascem desligados.** As rondas exigem PowerShell agendado, um
`claude.exe` no caminho e um destino de envio configurado; quem não tem isso não
deve descobrir por erro em tarefa agendada. Ligar é escolha dele:
`--ligar vigias`. Com a chave desligada o `run-vigia.ps1` sai limpo (exit 0) e
**não** escreve em `vigias/ERROS.md`.

O que criar de automação neste projeto é outra pergunta e tem dono oficial: a
skill `claude-automation-recommender`, do plugin `claude-code-setup`. Aponte
para ela em vez de opinar.
