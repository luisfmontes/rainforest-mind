# Impasse — contrato-de-veredito, 3ª reprovação (2026-09-24)

## O que ficou em aberto
`scripts/estado.cjs` (`transcritoEmPastaDeSessaoReal`): a pasta de conta aceita
`/^\.claude(-[^/]+)?$/`, ou seja qualquer `~/.claude-<qualquer>/`. O revisor
fabricou `$HOME/.claude-x/projects/p/s/subagents/agent-BYP1.jsonl` + `.meta.json`
numa caixa de areia e `estado.cjs veredito --transcrito` gravou `ok` (exit 0).

## Ponto (revisor)
D14 prometeu "forjar exige escrever entre os transcritos reais"; uma árvore
paralela inventada no home não é "entre os reais" — a promessa do design não
se cumpre.

## Contraponto
O hook real não é afetado (o harness entrega o caminho). O vetor é chamar
`estado.cjs veredito` à mão com árvore fabricada de propósito — o próprio D14
declara que o contrato barra hábito, não forja deliberada com acesso ao disco.
Criar `~/.claude-x/` também deixa o caminho gravado no veredito, visível.

## Opções
1. Restringir a conta às pastas de config reais: `CLAUDE_CONFIG_DIR` em uso, ou
   `.claude`/`.claude-*` que contenham `settings.json`. Fecha a árvore
   inventada; forjar volta a exigir escrever dentro de uma conta real.
2. Aceitar como risco residual e emendar D14 para dizer "qualquer pasta
   `.claude*` no home", sem código novo.

## Decisão do usuário
(pendente — registrada via `liberar --estagio revisar --rodada-extra`)
