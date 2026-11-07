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
  fixture: `testa-memoria-manutencao.sh, seção "11. quem cria a trava do dia apaga as de dias anteriores, e so elas"`
prova: `D=$(mktemp -d) && : > "$D/manutencao-2026-01-01.lock" && RFM_ROOT="$(cygpath -m "$D")" node hooks/memoria-manutencao-session-start.cjs < /dev/null && test ! -e "$D/manutencao-2026-01-01.lock"`
pronto quando: com uma raiz de dados em `mktemp -d` que já tem `manutencao-2026-01-01.lock`, `manutencao-2026-01-02.lock`, `manutencao-2999-12-31.lock`, `manutencao.log`, `manutencao-x.lock` e `manutencao-2026-1-1.lock`, e o payload real de `SessionStart` no stdin do hook, o hook sai 0, cria `manutencao-<hoje>.lock`, e depois disso as duas travas de 2026 não existem e os outros quatro arquivos existem; numa segunda raiz com `manutencao-2026-01-02.lock` e a trava de hoje já existente (outra sessão ganhou a corrida), `manutencao-2026-01-02.lock` continua lá — provado por `bash hooks/testa-memoria-manutencao.sh` saindo 0 com a seção 11 listando cada arquivo por nome, nenhum caso afirmando sobre o texto do fonte

Forma prescrita:
- Função `podarTravasAntigas(raiz, hoje)` no hook, definida logo depois de `dataLocalHoje` e antes de `main`, chamada numa linha só, `podarTravasAntigas(raiz, hoje);`, **depois** do bloco do `spawn` (depois do `finally` que fecha o `fd`) e só no ramo que criou a trava (o `EEXIST` já saiu antes).
- Dentro dela: `fs.readdirSync(raiz)` num `try` que devolve em erro; para cada nome, `/^manutencao-(\d{4}-\d{2}-\d{2})\.lock$/` e, casando com a data menor que `hoje` (comparação de string), `fs.unlinkSync(path.join(raiz, nome))` num `try` próprio que engole o erro e segue.
- Comentário do cabeçalho ganha um parágrafo "PODA (D1, D2)" apontando o design, sem repetir a chamada com `;` (o `de:` da mutação tem de aparecer uma vez só no fonte).
- **Bateria:** seção 11 nova antes do `== resumo ==`, aberta por `echo "== 11. quem cria a trava do dia apaga as de dias anteriores, e so elas =="` (ASCII, como as outras). Primeira raiz: `RAIZ11A="$(novo_sandbox)"`, `RFM_ROOT="$RAIZ11A" $MEMORIA iniciar > /dev/null 2>&1` (como a seção 10), os seis arquivos criados vazios com `: > "$RAIZ11A/<nome>"`; roda o hook com `RFM_ROOT="$RAIZ11A"` e `payload "$RAIZ11A"` no stdin; `esperar_filho "$RAIZ11A/manutencao-$(date +%F).lock" > /dev/null` antes de conferir, porque o filho escreve na raiz; um `afirma` de existência ou ausência por arquivo, pelo nome (o `manutencao.log` só por existência, o filho acrescenta linhas nele). Segunda raiz: `RAIZ11B="$(novo_sandbox)"`, `: > "$RAIZ11B/manutencao-2026-01-02.lock"` e `: > "$RAIZ11B/manutencao-$(date +%F).lock"`, roda o hook (sai no `EEXIST`, sem filho) e afirma que `manutencao-2026-01-02.lock` existe.

### 2. Versão 2.8.1, README e CHANGELOG [tipo: docs]
atende: D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pela tarefa 1
Forma: o selo do README (linha com `vers%C3%A3o-2.8.0` na URL e `versão 2.8.0` no `alt`) muda nos dois lugares; a frase da poda é acrescentada ao fim do item **Manutenção diária**, depois de "...sessão seguinte."; o `README.en.md` fica intocado (congelado desde a 2.5.2).
pronto quando: com o repositório deste worktree, `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` dizem `"version": "2.8.1"`, o selo do README diz `versão 2.8.1`, o CHANGELOG abre com `## 2.8.1 — 2026-11-07` descrevendo a poda pelo comportamento (que travas somem, que arquivos ficam), e o parágrafo **Manutenção diária** do README diz que a abertura que dispara a manutenção apaga as travas de dias anteriores — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n "2.8.1" README.md CHANGELOG.md; grep -n -A6 "Manutenção diária" README.md`
