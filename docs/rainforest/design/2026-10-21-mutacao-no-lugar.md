# Mutação no lugar para runtime vivo (#527, #569)

## Objetivo
O `conferir-mutacao.cjs` copia a raiz inteira para o temporário e roda baseline e mutação na cópia
(#266). Projeto cujo runtime é um processo vivo sobre a árvore real (editor Unity aberto, Godot,
Unreal) não mede assim: o editor trava `Temp/` e a cópia sai `EBUSY` (exit 69), e mesmo copiando, a
bateria (`unity command run_tests`) só fala com o editor da pasta original. Com toda tarefa `pulada
(exit 69)`, o `verificar` nunca fecha `ok`.

## Decisões fechadas
- **D1 — Modo no lugar, pedido explicitamente** (Q1 A do usuário): com `--no-lugar`, o
  `conferir-mutacao.cjs` não copia a árvore nem materializa o git. Baseline, mutação e bateria
  pós-mutação rodam na própria `--raiz`, e o arquivo-alvo volta aos bytes originais em toda saída
  (veredito, exceção, estouro de tempo, sinal), conferido byte a byte depois da restauração.
  Restauração que não confere é exit 1 com o caminho do backup no stderr, nunca veredito. Sem a flag,
  nada muda: a cópia da #266 segue o padrão.
- **D2 — Declarado por tarefa no plano** (Q2 A): o bloco `mutacao:` aceita o campo `no-lugar: sim`.
  O `conferir-fluxo.cjs mutacoes` repassa `--no-lugar` ao `conferir-mutacao.cjs`, e a `cobertura`
  recusa valor diferente de `sim`. A flag também vale na linha de comando.
- **D3 — Guarda-corpo** (Q3 A):
  - Recusa (exit 4, nada mutado) quando o arquivo-alvo tem mudança não commitada no git, para que
    `git checkout -- <arquivo>` sempre desfaça. Fora de repo git não há essa conferência, e o stderr
    avisa.
  - Antes de mutar, grava um backup no temporário (`conferir-mutacao-nolugar-<hash do caminho>.json`)
    com o caminho absoluto, os bytes originais, o hash dos bytes mutados e o PID. Com backup vivo
    (PID ativo) para o mesmo arquivo, recusa (exit 4). Na abertura, backup de PID morto cujo arquivo
    ainda tem o hash mutado é restaurado (e avisado no stderr); arquivo que mudou depois fica
    intocado, e o backup permanece com aviso.
  - O stderr avisa, antes da bateria pós-mutação, que o fonte real fica mutado até ela acabar.
  - *Emenda do alerta de segurança (antes da revisão):* a abertura só restaura o backup do
    próprio alvo desta execução, cujo `caminho` resolve para ele, e só se o backup for arquivo
    comum do usuário corrente. O backup é gravado com `wx` e modo 0600. Num temporário
    compartilhado, varrer qualquer backup seria escrever onde um JSON plantado mandasse.
  - *Emenda da rodada 1 da revisão:* o alvo ignorado pelo git também recusa (`status
    --ignored`), e `git status` que falha dentro de repositório recusa (exit 4) em vez de
    contar como "fora de repo". O arquivo relido antes de mutar precisa ser o original (editado
    durante o baseline recusa, exit 4). Na restauração, arquivo que já é o original só apaga o
    backup; arquivo que não é o mutante nem o original (editado durante a bateria) não é
    sobrescrito: sai 1 com o backup preservado. O backup órfão de arquivo já original sai sem
    aviso.
  - *Emenda da rodada 2 da revisão:* `git rev-parse` que falha, ou que diz "not a git
    repository" com um `.git` existente em alguma pasta acima (`.git/HEAD` corrompido), recusa
    (exit 4), como o `git status` que falha. A falha de restauração chega ao `conferir-fluxo
    mutacoes` com o rótulo `FALHA AO RESTAURAR` e o caminho do backup.
  - *Emenda da rodada 3 da revisão (aprovada, achados que cabem no PR):* o `git status` leva
    `--untracked-files=normal`, porque repo com `status.showUntrackedFiles=no` escondia o alvo não
    rastreado. A linha de sucesso deixa de dizer que o fonte foi restaurado: a restauração roda na
    saída, depois dela, e pode falhar.
  - Limite aceito (Q1 A do usuário, rodada 1): o dono do backup é conferido só pelo PID. PID
    reutilizado depois de reiniciar faz um backup morto parecer vivo, e o arquivo fica mutado
    até alguém apagar o backup à mão (a recusa nomeia o caminho). Não perde dado: o backup
    guarda os bytes originais e o alvo está sempre commitado.
- **D4 — Baterias**: casos novos em bateria própria do `conferir-mutacao` no modo no lugar:
  vermelho (exit 0) e verde (exit 2) com o arquivo restaurado byte a byte; recusa com o alvo sujo;
  recusa com backup vivo; restauração de backup órfão na abertura; restauração depois de estouro de
  tempo; o fonte não é copiado (pasta com arquivo travado ou `EBUSY` simulado não impede a medição);
  o caso vizinho sem a flag continua copiando. No `conferir-fluxo`, o campo `no-lugar: sim` vira
  `--no-lugar` e valor inválido é recusado na `cobertura`.
- **D5 — Docs e versão**: README, CHANGELOG `1.72.0` (MINOR: opção nova no contrato), `plugin.json`
  das duas plataformas, e a seção `mutacao:` da skill `plano` com o campo `no-lugar:` e o risco que
  ele traz de volta (outra sessão lê o fonte mutado durante a bateria).

## Avaliado e descartado
- Lista de exclusão da cópia (`Library/`, `Temp/`): só serve com o editor fechado e Unity em batch,
  o caso caro (Q1 B). A bateria barata é a do editor aberto, que a cópia não alcança.
- Chave de projeto em `.rainforest/config.json` (Q2 B): valeria para toda tarefa, inclusive as que
  medem bem na cópia, e some da vista de quem revisa o plano.

## Fora de escopo
- Detectar sozinho que o projeto é Unity, Godot ou Unreal e ligar o modo: o modo traz de volta o
  risco da #266, então só vale pedido.
- Isolar quem lê o fonte durante a bateria (outra sessão, outro agente): o aviso no stderr e o
  campo visível no plano são a defesa.

## Varredura
docs/rainforest/varredura/2026-10-21-mutacao-no-lugar.txt — a #569 (aberta por quem usa o plugin) é o mesmo
defeito da #527 e sugere o mesmo `--no-lugar`; as duas fecham juntas. Histórico: #266 (a cópia nasceu ali),
#378 (junction na cópia), #281 (pulada conta como falha).

## Em aberto
- (vazio)
