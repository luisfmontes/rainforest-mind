# Régua 3 do auditor-de-seguranca — técnicas de ataque (detecção defensiva)

Data: 2026-09-13. Base: origin/main ba7c67c4.

## Decisão
Adicionar ao `auditor-de-seguranca` uma **Régua 3** num arquivo de referência
externo (`referencias/reguas-tecnicas-ofensivas.md`), que o agente lê e aplica —
uma lente de DETECÇÃO por classe de técnica de ataque, derivada do repo
`SnailSploit/claude-red` (MIT), reescrita em formato defensivo report-only.

Porque: o Luís trouxe o claude-red como "visão de um agente de revisão", mas ele
é ofensivo (red team operator). O valor para um gate pré-publicação é inverter as
técnicas em lentes de revisão. Empacotar como referência externa (não inline)
mantém o agent md enxuto e é o "recomendado" escolhido (Q1a, Q2a).

## Escopo
Só as 9 categorias que revisam código-fonte: web, api, auth, cicd, supply-chain,
crypto, container, cloud, ai (~31 skills). Fora: wireless, exploit-dev,
post-exploitation, C2/EDR, forensics, recon, social-engineering — atacam sistema
em execução/pessoa/RF, não revisam repositório.

## Anti-duplicação
Réguas 1/2 já cobrem as CATEGORIAS OWASP. A Régua 3 afia no nível-de-técnica e
cada lente marca a categoria que sharpen. Classes já cobertas (sqli/xss/idor/
ssrf) entram leves, como referência cruzada.

## Licença
claude-red é MIT: derivar é permitido, com crédito na linha "Derivada de".
OWASP continua citada por URL, reescrita (repo MIT, OWASP CC BY-SA).

## Verificação (falsificável)
- `scripts/testa-auditor-de-seguranca.sh` continua verde.
- Nova referência existe e tem 1 lente por classe, cada uma com as 5 partes.
- grep não acha payload/exploit funcional no arquivo (report-only).
- Agent md aponta para a Régua 3 e instrui a lê-la.
