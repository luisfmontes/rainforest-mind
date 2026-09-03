# Pontes: Codex e Gemini CLI


O plugin é do Claude Code — os **10 hooks** (quatro deles as travas
`PreToolUse`), os **11 slash commands**, as **16 skills** e os **9 subagentes**
são API dele e não têm equivalente nos outros hosts. Mas o **método**
não precisa ficar preso a um agente, e a pasta de dados não sabe quem a escreveu.

Quais agentes você usa é **configuração**, e mora no `/setup` (`ponte-claude`,
`ponte-codex`, `ponte-gemini`, desligadas por padrão). Qual repositório recebe o
arquivo **não é**: é alvo explícito, com ensaio, porque o gerado vai ser commitado
no repo de outra pessoa.

```
node scripts/setup.cjs --ligar ponte-codex             # declara o que esta máquina usa
node scripts/ponte.cjs --alvo <dir-do-repo>            # ensaio: mostra e não grava
node scripts/ponte.cjs --alvo <dir-do-repo> --aplicar  # só os alvos declarados
```

São **três** alvos: `CLAUDE.md` também é ponte — para quem usa Claude Code **sem o
plugin**, que não tem regra nenhuma. É o caminho de quem recebe o convite antes de
instalar. E o texto muda com o alvo: lá a falta das travas se explica pelo plugin
ausente; nos outros dois, por o host não ter `PreToolUse`.

O arquivo é **gerado**, nunca escrito à mão, e o comando que o gera está escrito
dentro dele. O motivo é um incidente: nesta máquina existem duas `CLAUDE.md` de
escopo usuário — uma por config dir — que eram sincronizadas à mão. Em 2026-08-10
uma foi editada e a outra divergiu **em silêncio**; metade do setup passou a valer
o contrário da outra metade. Regra duplicada não fica errada com aviso: fica
errada calada.

E a ponte diz o que ela **não** entrega, porque prometer trava que não existe é
pior que não ter ponte:

| No Claude Code | Na ponte |
|---|---|
| gate de worktree e gate de `git add -A` (hook `PreToolUse`, exit 2) | **texto** — não existe `PreToolUse` nesses hosts, então é combinado, não trava |
| injeção de SessionStart | o próprio arquivo gerado, que o host lê a cada sessão |
| `estado.cjs exigir` (gate do fluxo, exit 2) | **igual** — é comando de shell |
| `conferir-entrega.cjs` (regra 12, exit 1) | **igual** |
| `conferir-publicacao.cjs` (anonimização, exit 2) | **igual** |
| `/ideia`, `/foco`, `/semear` | os CLIs `ideias.cjs`, `foco.cjs`, `semear.cjs` |

O gerado **não chumba caminho de home** — ele ensina a descobrir a pasta de dados
com `ideias.cjs conferir`, porque nasce para ser commitado no repo de outra
pessoa. Se o arquivo já existir escrito à mão, o bloco entra delimitado e nada do
que estava lá é apagado; regenerar substitui só o bloco.

