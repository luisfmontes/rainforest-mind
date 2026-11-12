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
pronto quando: com um transcript no formato real cuja última mensagem soma 320000 tokens, `node scripts/estado.cjs exigir --slug caixa --estagio limpar` sai 0 e imprime em stderr exatamente `aviso: contexto em 320 mil tokens (limiar 310 mil). Antes de abrir 'limpar', peça ao usuário um /compact e siga o fluxo depois dele: o estado está gravado e sobrevive à compactação. Não pare o fluxo nem proponha sessão nova por causa deste aviso.`, sem `sessão nova` como sugestão — provado por `bash scripts/testa-uso-contexto.sh` devolvendo `falhou: 0`, com o caso da linha 71 afirmando o texto inteiro da D1.

Forma prescrita: só a string devolvida por `avisoDeContexto` muda; assinatura, limiar e retorno `null` ficam como estão.

### 2. Notas e versão 2.13.1 [tipo: docs]
atende: D1
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: tarefa só descreve a mudança e sobe a versão; o comportamento está na tarefa 1
pronto quando: com a versão 2.13.1 nos dois `plugin.json` e no selo do README, o CHANGELOG ganha a entrada `## 2.13.1 — 2026-11-12` dizendo que o aviso pede um `/compact` ao usuário e que o fluxo segue depois dele, sem parar nem propor sessão nova, coerente com a D1 — provado por `node scripts/conferir-versao.cjs` saindo 0 e `grep -c "2.13.1" .claude-plugin/plugin.json .codex-plugin/plugin.json README.md` devolvendo 1 em cada.
