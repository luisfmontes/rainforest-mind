# Plano: gate-pergunta-memoria sem o canal do banco

Design: docs/rainforest/design/2026-10-29-gate-memoria-sem-banco.md

## O que não pode quebrar
- O canal dos arquivos de memória: P1 a P11, P14, P14b, P15 e P17 a P22, P24 e P24b de `hooks/testa-gate-pergunta-memoria.cjs` continuam verdes sem edição de asserção.
- `buscarPorAssunto` sem `soProjeto` devolve o mesmo que hoje: `hooks/testa-memoria-assunto-prompt.cjs` e `hooks/testa-peso-projeto-atual.cjs` verdes sem edição.
- Hook de Stop nunca derruba a sessão: qualquer falha sai com exit 0.

## Tarefas

### 1. Gate sem o canal do banco, biblioteca sem soProjeto [tipo: implementar]
atende: D2, D3, D4
arquivos: `hooks/gate-pergunta-memoria.cjs`, `hooks/testa-gate-pergunta-memoria.cjs`, `hooks/lib/memoria-assunto.cjs`, `hooks/testa-memoria-assunto.cjs`
depende de: nenhuma
busca:
- repo | rg "achadoNoBanco|conectarBancoLeitura|soProjeto|RFM_PERGUNTA_MEMORIA_ORCAMENTO_MS" | só o gate, a bateria dele, memoria-assunto.cjs e a bateria dela
- livro | pulado: remoção de canal próprio
desfecho: estender
prova-na-base: verde — a bateria da base afirma o canal do banco; o caso de regressão nasce com esta tarefa e é medido contra o hook da base na integração
mutacao: n/a
  motivo: a tarefa remove código; não sobra linha a inverter. A regressão é medida rodando a bateria nova contra o hook da base (o caso P12 tem de ficar vermelho lá), como diz o pronto quando
pronto quando: com um banco real do `memoria.cjs` (schema de `criarSchema`) contendo uma observação do projeto atual que casa a pergunta, e sem `memory/` que responda, o hook sai 0 (P12 reescrito). P13, P16, P16b e P23 saem da bateria, porque mediam o canal removido. O gate não abre o banco: `rg "memoria.cjs|buscarPorAssunto|ORCAMENTO_BANCO" hooks/gate-pergunta-memoria.cjs` não devolve nada. `soProjeto` não existe mais em `hooks/lib/memoria-assunto.cjs` e o caso dele sai de `hooks/testa-memoria-assunto.cjs`. Provado por `node hooks/testa-gate-pergunta-memoria.cjs` com `falhou: 0`, por `node hooks/testa-memoria-assunto.cjs`, `node hooks/testa-memoria-assunto-prompt.cjs` e `node hooks/testa-peso-projeto-atual.cjs` com zero falhas, e pela bateria nova rodada num worktree descartável de `origin/main` (só o arquivo da bateria trocado), onde o P12 tem de sair `FALHA`.

### 2. Documentação e versão 2.1.2 [tipo: docs]
atende: D1, D5
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `docs/travas-mecanicas.md`, `hooks/lib/config.cjs`
depende de: nenhuma
mutacao: n/a
  motivo: texto e versão; a falsificação é a coerência com o design e com a interface real
pronto quando: com o código da tarefa 1, o README e `docs/travas-mecanicas.md` deixam de dizer que o gate consulta o banco do `memoria.cjs` (nem prazo, nem filtro de projeto, nem `RFM_PERGUNTA_MEMORIA_ORCAMENTO_MS`), dizem que só os arquivos de memória do repositório principal contam e por quê (D2), e o CHANGELOG ganha a seção `2.1.2` com a medição (11 de 11). A versão sobe para 2.1.2 nos dois `plugin.json` e no selo do README. Provado por `bash scripts/testa-versao.sh` com `falhou: 0`, por `rg -n "ORCAMENTO_MS|soProjeto|antes do corte de 50|só com observações do projeto atual" README.md docs/travas-mecanicas.md` sem nenhuma linha (o texto pode citar o banco só para dizer que ele não é consultado), e pela leitura, no revisar, de cada frase nova contra o código.

## Rodada 2 (revisão 1 aprovada com achado [baixa], 2026-10-29)

A descrição da chave `gate-pergunta-memoria` em `hooks/lib/config.cjs` ainda citava o banco, e o `setup` a imprime em "O QUE ESTA LIGADO". A tarefa 2 passou a incluir o arquivo, e a descrição fala só do arquivo de memória. O "Desde a 2.1.1" removido do README (achado 2) é exigido pela `testa-versao`, que recusa outra versão no README além da atual depois do bump.
