# Plano: aviso de contexto alto manda compactar, não parar

Design: docs/rainforest/design/aviso-contexto-compactar.md

## O que não pode quebrar
- O limiar, a medição e o lugar do aviso (stderr do `exigir`): o exit e o stdout do `exigir` ficam iguais.
- Os demais casos de `scripts/testa-uso-contexto.sh` (o `Antes de abrir 'verificar'` do caso do `exigir` recusado segue valendo).

## Tarefas

### 1. Texto novo do aviso [tipo: implementar]
atende: D1
arquivos: `scripts/lib/uso-contexto.cjs`, `scripts/testa-uso-contexto.sh`
depende de: nenhuma
busca:
- repo | rg "considere /compact" scripts hooks skills | só scripts/lib/uso-contexto.cjs:81 e o caso de scripts/testa-uso-contexto.sh:71
desfecho: estender
mutacao:
  arquivo: `scripts/lib/uso-contexto.cjs`
  de: `peça ao usuário um /compact e siga o fluxo depois dele`
  para: `registre o estado e considere /compact ou uma sessão nova`
  bateria: `bash scripts/testa-uso-contexto.sh`
  fixture: `testa-uso-contexto.sh, caso "uso acima do limiar avisa com tokens, limiar e estagio"`
prova: `grep -q "peça ao usuário um /compact" scripts/lib/uso-contexto.cjs`
pronto quando: com o transcript de 320000 tokens que a bateria monta, o `exigir --slug caixa --estagio limpar` do caso "uso acima do limiar avisa com tokens, limiar e estagio" sai 0 e imprime em stderr exatamente `aviso: contexto em 320 mil tokens (limiar 310 mil). Antes de abrir 'limpar', peça ao usuário um /compact e siga o fluxo depois dele: o estado está gravado e sobrevive à compactação. Não pare o fluxo nem proponha sessão nova por causa deste aviso.` — provado por `bash scripts/testa-uso-contexto.sh` devolvendo `falhou: 0`, com o caso da linha 71 afirmando o texto inteiro da D1.

Forma prescrita:
- Em `scripts/lib/uso-contexto.cjs`, só a string devolvida por `avisoDeContexto` muda; assinatura, limiar e retorno `null` ficam como estão. O literal continua em linhas concatenadas por `+`, e a segunda linha começa exatamente com `` `Antes de abrir '${estagio}', peça ao usuário um /compact e siga o fluxo depois dele: `` (o trecho do `de:` da mutação fica inteiro nessa linha). A terceira linha leva `o estado está gravado e sobrevive à compactação. Não pare o fluxo nem proponha sessão nova por causa deste aviso.`.
- Em `scripts/testa-uso-contexto.sh`, linha 71: o terceiro argumento de `com_aviso` passa a ser o texto exato do `pronto quando` acima, com o estágio `'limpar'` (não `'plano'`, que é só o exemplo do design). O caso da linha 136 (`Antes de abrir 'verificar'`) não muda.

### 2. Notas e versão 2.13.1 [tipo: docs]
atende: D1
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: tarefa só descreve a mudança e sobe a versão; o comportamento está na tarefa 1
pronto quando: com a versão 2.13.1 nos dois `plugin.json` e no selo do README, o CHANGELOG ganha a entrada `## 2.13.1 — 2026-11-12` dizendo que o aviso pede um `/compact` ao usuário e que o fluxo segue depois dele, sem parar nem propor sessão nova, coerente com a D1 — provado por `node scripts/conferir-versao.cjs --sem-fetch` saindo 0 e `grep -c "2.13.1" .claude-plugin/plugin.json .codex-plugin/plugin.json README.md` devolvendo 1 em cada.

Onde editar: `"version"` na linha 3 de `.claude-plugin/plugin.json` e de `.codex-plugin/plugin.json`; no `README.md` linha 7, o `2.13.0` da URL do selo e do `alt`; no `CHANGELOG.md`, a entrada nova vai logo acima de `## 2.13.0 — 2026-11-12`, no estilo dela (item com negrito curto e a descrição). Não edite entradas antigas do CHANGELOG nem o design `2026-11-09-aviso-contexto-alto`: são registro histórico.
