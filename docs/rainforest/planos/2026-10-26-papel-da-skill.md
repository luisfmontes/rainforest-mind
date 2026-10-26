# Plano: Papel da skill, apoio ao desenvolvimento

Design: docs/rainforest/design/2026-10-26-papel-da-skill.md

## O que não pode quebrar
- A abertura com `foco: true` sai como na 1.80.1, byte a byte (`hooks/testa-foco-opcional.sh`).
- A frase "memória de trabalho externa e radar de escopo" segue existindo exatamente 1 vez no SKILL.md, antes de `## As regras` (`scripts/testa-conferir-invariantes.sh`).
- O núcleo das regras não muda (`hooks/testa-contexto-sessao.sh`, `scripts/testa-orcamento.sh`).

## Tarefas

### 1. Frase do papel, CHANGELOG e versão 2.0.1 [tipo: docs]
atende: D1, D2, D3, D4, D5
arquivos: `skills/rainforest-mind/SKILL.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `docs/rainforest/estado/2026-10-25-versao-2-0-0.json`
depende de: nenhuma
busca:
- repo | grep -n "papel do assistente\|Última revisão" skills/rainforest-mind/SKILL.md | a frase de hoje (:11-12) e a data que fica (:25)
- repo | grep -n "memória de trabalho externa" scripts/testa-conferir-invariantes.sh | a fixture que exige a frase 1 vez fora das regras (:899-910)
- repo | grep -n "2\.0\.0" README.md .claude-plugin/plugin.json .codex-plugin/plugin.json | os lugares da versão
desfecho: estender
prova: `bash scripts/testa-conferir-invariantes.sh`
mutacao: n/a
  motivo: texto de apresentação da skill e metadado de versão, sem comportamento de produção a inverter
pronto quando: `skills/rainforest-mind/SKILL.md:11-12` diz que o papel é apoio ao desenvolvimento e, com `foco: true`, também memória de trabalho externa e radar de escopo, mantendo "nunca tutor" e a data `Última revisão: 2026-10-05`; os dois `plugin.json` e o badge do README dizem `2.0.1`, e as menções "desde a 2.0.0" do README (`:27`, `:384`) passam a "desde a 2.0", porque `scripts/testa-versao.sh:73-86` exige que todo semver de três partes do README seja a versão corrente; o CHANGELOG tem a entrada `2.0.1` dizendo que a frase mudou e que a ponte gerada com a 2.0.0 continua conferida (só o hash do marcador difere), o que se prova gerando a ponte com o `scripts/ponte.cjs` de `d92f98ff` numa caixa `mktemp -d` e rodando o `scripts/conferir-ponte.cjs` da branch sobre ela (`CONFERIDO`, exit 0) — provado por `bash scripts/testa-conferir-invariantes.sh`, `bash hooks/testa-foco-opcional.sh`, `bash scripts/testa-versao.sh` e `node scripts/conferir-versao.cjs` verdes.
