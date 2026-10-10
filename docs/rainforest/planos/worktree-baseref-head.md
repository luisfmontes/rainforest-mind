# Plano: worktree do agente nasce do HEAD da sessão (`worktree.baseRef: "head"`)

Design: docs/rainforest/design/worktree-baseref-head.md

## O que não pode quebrar
- A conferência de base (`preparar-worktree.cjs --hash`, `conferir-entrega.cjs --base`) continua obrigatória nos dois modos (D3).
- O texto do modo `fresh` (`origin/main` + `--ff-only`) continua descrito para quem instala o plugin sem a chave (D2).
- O núcleo injetado da regra 11 cabe no orçamento do SessionStart (baterias do núcleo verdes).

## Tarefas

### 1. Regra 11 descreve os dois modos [tipo: docs]
atende: D2, D3, D4
arquivos: `skills/rainforest-mind/references/regra-11.md`, `skills/rainforest-mind/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa só reescreve texto normativo; não há comportamento executável a inverter
pronto quando: com a regra 11 como a sessão a lê (elaboração e núcleo), toda menção à ponta de `origin/main` como base do agente vem condicionada ao modo `fresh`/padrão, e a elaboração diz por que a conferência vale também em `head` — provado por `for f in skills/rainforest-mind/references/regra-11.md skills/rainforest-mind/SKILL.md; do n=$(grep -c "ponta d[ae] \`origin/main\`" $f); c=$(grep -B4 "ponta d[ae] \`origin/main\`" $f | grep -c "fresh\|baseRef"); [ "$c" -ge "$n" ] || exit 1; done; grep -q "outro escopo de settings pode sobrepor a chave" skills/rainforest-mind/references/regra-11.md` saindo 0 (na base sai 1: condicionadas=0)

### 2. `executar` despacha conforme a chave [tipo: docs]
atende: D2, D4
arquivos: `skills/executar/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa só reescreve texto normativo; não há comportamento executável a inverter
pronto quando: com o parágrafo "Antes de despachar" do `executar`, o modo `head` manda despachar de dentro do worktree do fluxo com o hash de `git rev-parse HEAD` dali, e o modo `fresh` mantém o `--ff-only` — provado por `grep -n "Antes de despachar" skills/executar/SKILL.md | grep -q "despache de dentro do worktree do fluxo" && grep -n "Antes de despachar" skills/executar/SKILL.md | grep -q "merge --ff-only origin/main"` saindo 0

### 3. Glossário acompanha [tipo: docs]
atende: D5
arquivos: `GLOSSARIO.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa só reescreve verbete; não há comportamento executável a inverter
pronto quando: com o verbete "worktree de agente", a definição nomeia os dois modos e o "Onde mora" deixa de dizer que a regra 11 manda criar a partir de `origin/main` — provado por `awk '/^## worktree de agente/,/^Cenário/' GLOSSARIO.md | grep -c "baseRef\|fresh"` devolvendo 1 ou mais e `awk '/^## worktree de agente/,/^Cenário/' GLOSSARIO.md | grep -c "que manda criar o worktree a partir de"` devolvendo 0

### 4. Chave gravada nas settings do usuário [tipo: configurar]
atende: D1
arquivos: `~/.claude/settings.json`, `~/.claude-personal/settings.json` (fora do repo; gravado pela janela principal com autorização do Luís, Q3 de 2026-10-09)
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: configuração do usuário fora do repo; o efeito foi medido pela sonda descrita no design
pronto quando: com as duas settings como o harness as lê, `worktree.baseRef` vale `head` nas duas — provado por `node -e "for (const p of [process.env.USERPROFILE+'/.claude/settings.json', process.env.USERPROFILE+'/.claude-personal/settings.json']) { if (require(p).worktree?.baseRef !== 'head') process.exit(1) }"` saindo 0
