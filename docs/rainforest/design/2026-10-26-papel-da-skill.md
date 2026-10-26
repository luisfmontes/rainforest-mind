# Papel da skill: apoio ao desenvolvimento

## Objetivo
Fechar a ponta que a 2.0.0 deixou aberta (PR #600, "Fica para depois"): o parágrafo de abertura de
`skills/rainforest-mind/SKILL.md:11` ainda diz que o papel do assistente é ser **memória de trabalho externa e radar
de escopo**, quando desde a 2.0.0 o plugin abre como apoio ao desenvolvimento e o foco nasce desligado. Decidido pelo
Luís em 2026-10-26 ("pode fazer", sobre a recomendação de um lote pequeno separado).

Brainstorm conduzido sob a delegação do Luís ("faça o brainstorm de tudo com a opção recomendada"). Cada `D<n>` é a
resposta recomendada e fica aberta a veto no PR. Citações conferidas contra `d92f98ff` (main depois do PR #600).

## Decisões fechadas
- **D1 — A frase do papel diz o padrão e o opcional.** `skills/rainforest-mind/SKILL.md:11-12` passa a dizer que o papel é **apoio ao desenvolvimento** e, com o foco ligado (`foco: true`), também memória de trabalho externa e radar de escopo; "nunca tutor" fica. O resto do parágrafo (mente-floresta, profissional sênior, "o aviso, não a terapia") não muda. — porquê: o parágrafo descreve o plugin que a 2.0.0 entrega por padrão; o foco continua existindo e a frase antiga continua verdadeira para quem o liga.
- **D2 — A frase antiga sobrevive uma vez, fora do bloco das regras.** `scripts/testa-conferir-invariantes.sh:899-910` usa "memória de trabalho externa e radar de escopo" como frase que existe exatamente 1 vez no SKILL.md, antes de `## As regras`; o D1 a mantém nessas condições e a bateria não muda. — porquê: trocar a fixture custaria reescrever a justificativa do caso sem ganho.
- **D3 — `Última revisão: 2026-10-05` fica.** A data alimenta o aviso de revisão bimestral das 17 regras (`hooks/foco-session-start.cjs:260-262`); trocar um parágrafo de apresentação não é a revisão. — porquê: a data mentiria sobre uma revisão que não houve.
- **D4 — A abertura com o foco ligado não muda.** O cabeçalho `RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do usuario (perfil 2e).` (`hooks/lib/contexto-sessao.cjs:1155`) é o lado ligado, que a 2.0.0 prova byte a byte contra `dc88603a`; o parágrafo do SKILL.md não entra na abertura nem no núcleo (`extrairNucleo` lê só as regras). — porquê: a promessa da 2.0.0 para quem liga o foco é "como na 1.80.1".
- **D5 — Versão 2.0.1, e a ponte não precisa ser regenerada.** O hash do marcador da ponte é do SKILL.md inteiro (`scripts/ponte.cjs:525`, `hashDoArquivo`) e muda, mas o `conferir-ponte` compara primeiro o conteúdo do bloco com o que a geração atual produziria e só olha o hash quando o conteúdo diverge (`scripts/conferir-ponte.cjs`, CASO 1); a ponte carrega o núcleo das regras, não o parágrafo de abertura, então a ponte gerada com a 2.0.0 continua `CONFERIDO`. A entrada do CHANGELOG diz isso. Nenhuma bateria fixa o hash atual (`6b78cdf6b2d528ee`, busca sem resultado). — porquê: quem gerou ponte com a 2.0.0 não precisa fazer nada, e o CHANGELOG não pode prometer um aviso que não vem. (Premissa corrigida na revisão 1: a primeira versão deste D5 dizia que a ponte sairia desatualizada; o revisor gerou a ponte com a 2.0.0 e conferiu com a 2.0.1, saída `CONFERIDO`, exit 0.)

## Avaliado e descartado
- **Tirar a frase antiga de vez**: quebra a fixture do D2 e apaga o que o foco ligado ainda é.
- **Mudar também o cabeçalho da abertura com foco ligado**: quebra a prova byte a byte da 2.0.0 (D4).
- **Esperar outra mudança de SKILL.md para juntar**: o parágrafo não entra na ponte nem na abertura (D4, D5), então juntar não economiza nada para quem usa.

## Fora de escopo
- `skills/rainforest-mind/SKILL.md:22` ("Guarda-corpo de jornada, freio de perfeccionismo e radar de escopo são avisos operacionais"): descreve o limite dos avisos quando existem, não o padrão.
- `hooks/lib/config.cjs:181-188`, `skills/setup/SKILL.md:99,178` e `README.md:26,387`: já falam do radar de escopo como parte do foco opcional.

## Varredura
docs/rainforest/varredura/2026-10-26-papel-da-skill.txt — termos "radar de escopo", SKILL.md, "ponte hash", papel. Nenhuma Issue aberta. As que pesam: #77 e o PR #102 (a catraca da ponte por hash, que o D5 aciona), o PR #306 (invariantes de frase nos SKILL.md: a frase do D1 não é invariante, `skills/rainforest-mind/invariantes.json` não a cita) e a #450 (o `conferir-ponte` manda regenerar por caminho relativo, já fechada).

## Em aberto
