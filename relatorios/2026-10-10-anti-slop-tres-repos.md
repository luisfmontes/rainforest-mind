# Três repos contra texto de IA — 2026-10-10

Indicados pelo Luís. Problema ancorado: mensagem, e-mail e post de LinkedIn escritos em
nome dele saem com os tiques de texto gerado, e a `linkedin-ghostwriting` pede uma
passada "humanizer" que não existia. Destino escolhido por ele: o `message-standards`.
Trilha declarada: **Instalar**, com **Enxertar** como degrau de baixo.

| Repo | Licença | Push (API) | Estrelas | Veredito |
|---|---|---|---|---|
| `petergyang/no-ai-slop` | MIT | 2026-09-02 | 12,1k | Instalar -> Enxertar: enxerta |
| `ItsssssJack/SlopMonster` | MIT | 2026-09-26 | 807 | Instalar -> Enxertar: enxerta |
| `jalaalrd/anti-ai-slop-writing` | sem arquivo | 2026-04-18 | 523 | Instalar -> Enxertar: nao enxerta |

Lidos inteiros, de clone raso: os `SKILL.md`, `eval.md` e `banned-words.md`, o
`deslop.py`, o `cleanse.sh`, o `prompts/cleanse.txt` e o CI do SlopMonster.

## Por que nenhum instala

Os três são para inglês. Lista de palavras e regex não atravessam idioma, e o texto do
Luís é em português. O SlopMonster é o único com código, e o código é justamente a parte
que não serve aqui: o `deslop.py` casa `delve`, `seamless`, `not just X, but Y`.

## no-ai-slop: o conteúdo que entrou

Descreve **estruturas**, e estrutura traduz. Entraram no `message-standards`, com
exemplos em português: contraste binário, lista negativa, abertura de pigarro, falso
insight, revelação com dois-pontos, gerúndio de análise (o equivalente português do
`-ing` de "highlighting"), importância inflada, metacomentário, atribuição vaga,
sinônimo rotativo, pergunta autorrespondida, fragmento dramático, fecho de efeito,
formatação de enfeite e travessão de ritmo. Mais o **teste da portabilidade** (frase que
serviria para qualquer empresa é enchimento) e o **modo detectar**: cita o trecho, nomeia
o padrão, sugere a correção, e não reescreve nem palpita autoria.

## SlopMonster: a melhor engenharia, e uma peça

Entrou a regra **não fabricar personalidade**: para soar humano não se acrescenta erro,
opinião, gíria ou número que o autor não deu. Ficam para revisita, se um dia o texto em
português pedir trava mecânica: o verificador que sai com exit 1 abaixo de 5/5 (serve de
gate em CI) e a segunda passada por **outra família de modelo**, com o argumento de que
o modelo não ouve o próprio sotaque. É a mesma tese do revisor cego da `regua`.

Cuidado de engenharia que vale anotar, lido no código: `read_utf8` existe porque o
Windows abria o arquivo em cp1252 e as regras de pontuação ficavam cegas sem errar
(issue #3 deles); e entrada vazia reprova em vez de passar.

## anti-ai-slop-writing: não enxerta

Sem arquivo de licença. As regras são cotas sem fonte ("um travessão a cada 500
palavras", "nunca três frases seguidas do mesmo tamanho", voz passiva proibida), e há
contradição interna: proíbe inventar anedota e manda incluir atrito, dúvida e "terça
passada, às 2h". É a fabricação de personalidade que o SlopMonster proíbe.

## O que mudou

- `message-standards`, PR #1 (merge `1c7b9e3`): seção "Padrões de texto de IA", modo
  detectar, item na auto-checagem, passo 4 do LinkedIn. O mesmo PR juntou os dois clones
  da skill (pessoal e trabalho), que tinham divergido.
- Dois defeitos de gate achados no caminho, abertos e consertados no PR deste relatório:
  #495 (`gate-repo-alheio`) e #496 (`gate-fechar-issue`).

## Observação

A prosa deste plugin está cheia dos padrões que entraram no `message-standards`,
"não é X, é Y" à frente. O enxerto vale só para texto que sai em nome do Luís; aplicar à
prosa do rainforest seria outra decisão.
