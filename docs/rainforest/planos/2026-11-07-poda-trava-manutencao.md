# Plano: a trava diária da manutenção poda as dos dias anteriores

Design: docs/rainforest/design/2026-11-07-poda-trava-manutencao.md

## O que não pode quebrar
- A trava do dia continua criada com `fs.openSync(trava, 'wx')`, e a segunda sessão do mesmo dia continua saindo sem disparar nada (casos 3 e 5 da bateria).
- O hook sai 0 em toda degradação (caso 7).
- Nenhum arquivo além de `manutencao-<AAAA-MM-DD>.lock` de data anterior a hoje é apagado da raiz de dados.

## Tarefas

### 1. Poda das travas antigas no hook [tipo: implementar]
atende: D1, D2
arquivos: `hooks/memoria-manutencao-session-start.cjs`, `hooks/testa-memoria-manutencao.sh`
depende de: nenhuma
busca:
- repo | rg -n "readdirSync.*raiz|unlinkSync" hooks/memoria-*.cjs | nenhuma poda na raiz de dados; construir
- livro | pulado: conserto interno de três linhas, sem mecanismo a enxertar
desfecho: construir
mutacao:
  arquivo: `hooks/memoria-manutencao-session-start.cjs`
  de: `podarTravasAntigas(raiz, hoje);`
  para: `void raiz;`
  bateria: `bash hooks/testa-memoria-manutencao.sh`
  fixture: `testa-memoria-manutencao.sh, seção "11. quem cria a trava do dia apaga as de dias anteriores, e só elas"`
prova: `bash hooks/testa-memoria-manutencao.sh`
pronto quando: com uma raiz de dados em `mktemp -d` que já tem `manutencao-2026-01-01.lock`, `manutencao-2026-01-02.lock`, `manutencao-2999-12-31.lock`, `manutencao.log`, `manutencao-x.lock` e `manutencao-2026-1-1.lock`, e o payload real de `SessionStart` no stdin do hook, o hook sai 0, cria `manutencao-<hoje>.lock`, e depois disso as duas travas de 2026 não existem e os outros quatro arquivos existem; numa segunda raiz em que a trava de hoje já existe (outra sessão ganhou a corrida), a trava de ontem continua lá — provado por `bash hooks/testa-memoria-manutencao.sh` saindo 0 com a seção 11 listando cada arquivo por nome, nenhum caso afirmando sobre o texto do fonte

Forma prescrita:
- Função `podarTravasAntigas(raiz, hoje)` no hook, chamada numa linha só, `podarTravasAntigas(raiz, hoje);`, **depois** do bloco do `spawn` (depois do `finally` que fecha o `fd`) e só no ramo que criou a trava (o `EEXIST` já saiu antes).
- Dentro dela: `fs.readdirSync(raiz)` num `try` que devolve em erro; para cada nome, `/^manutencao-(\d{4}-\d{2}-\d{2})\.lock$/` e, casando com a data menor que `hoje` (comparação de string), `fs.unlinkSync(path.join(raiz, nome))` num `try` próprio que engole o erro e segue.
- Comentário do cabeçalho ganha um parágrafo "PODA (D1, D2)" apontando o design.
- **Bateria:** seção 11 nova antes do resumo, no molde das seções existentes (`novo_sandbox`, `payload`, `esperar_filho`, `igual`/`afirma`). A segunda raiz cria a trava de hoje à mão antes de rodar o hook.

### 2. Versão 2.8.1, README e CHANGELOG [tipo: docs]
atende: D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pela tarefa 1
pronto quando: com o repositório deste worktree, `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` dizem `"version": "2.8.1"`, o selo do README diz `versão 2.8.1`, o CHANGELOG abre com `## 2.8.1 — 2026-11-07` descrevendo a poda pelo comportamento (que travas somem, que arquivos ficam), e o parágrafo **Manutenção diária** do README diz que a abertura que dispara a manutenção apaga as travas de dias anteriores — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n "2.8.1" README.md CHANGELOG.md; grep -n -A6 "Manutenção diária" README.md`
