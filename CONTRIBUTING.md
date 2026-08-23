# Como mexer neste repositório

O plugin é o **código**; o `FOCO.md`, o `ideias.jsonl` e o `projetos.json` são
**dados do usuário** e moram em `~/.rainforest`, fora daqui. Nada neste repo deve
ler o seu acervo para funcionar, e nada dele deve escrever caminho de máquina
nenhuma dentro de arquivo versionado.

## Antes de abrir PR

```
for t in scripts/testa-*.sh hooks/testa-*.sh; do bash "$t"; done
CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh
```

Todas verdes, sem exceção. **Node é a única dependência**: as baterias não usam
outra linguagem — nem para montar fixture, nem para conferir JSON. Isso vale para
quem contribui, não só para quem instala; promessa de runtime que não alcança o
caminho de teste deixa de fora quem quer validar a própria mudança.

A última linha roda o **gêmeo** em Python de `conferir-entrega.cjs` (o de
`ideias.cjs` foi aposentado em 2026-08-22, depois que a bateria gêmea parou de
provar equivalência). Ela é a exceção que confirma a regra: ali o Python **é o
teste**, não o meio — a mesma bateria roda contra as duas implementações, e é
isso que prova que o port não perdeu garantia. Apagar um gêmeo é apagar a
prova; escrever teste novo em Python é adicionar dependência sem precisar.

Bateria nova entra com pelo menos um caso de **mutação** — sabota o mecanismo e
exige que ele reprove. Trava que nunca foi vista travando não é evidência de nada.

## Campo obrigatório novo vem com o passado resolvido, no mesmo commit

Esta é a regra que este repo aprendeu do jeito caro, e ela vale para qualquer
esquema de dado (o `ideias.jsonl` hoje, o `projetos.json` amanhã).

Quando um campo passa a ser **cobrado**, o mesmo commit resolve o acervo que já
existe, de um destes três jeitos — e diz qual escolheu:

| Caminho | Quando serve |
|---|---|
| **backfill** | o valor é derivável (do git, de outro campo, de convenção) |
| **anistia por data**, em constante declarada | o valor é autoral e não há de onde inferir |
| **opcional para quem nasceu antes** | o campo só faz sentido no fluxo novo |

E a bateria tem que provar as duas metades: **linha herdada não derruba o gate, e
linha nova derruba.**

> 2026-08-11: `gancho` virou campo obrigatório das ideias abertas sem nenhuma das
> três coisas acima. O `conferir` — que é o gate de saúde do acervo — ficou
> vermelho no mesmo commit, com 35 problemas em linhas que nenhuma sessão tinha
> causado, e ficou assim por um dia inteiro. Gate permanentemente vermelho não é
> gate: a sessão que o encontra assim aprende a ignorá-lo, e aí ele para de pegar
> o problema **novo**, que é a única coisa que ele existe para pegar. Corrigido na
> Issue #3 com anistia por data (`GANCHO_EXIGIDO_DESDE`), e a dívida continua
> impressa em toda execução, porque anistia que esconde vira esquecimento.

## Duas irmãs da mesma regra

- **Contagem diz de qual conjunto saiu.** `35 de 55 abertas` e nunca `35`. O mesmo
  arquivo mostrou 35 num comando e 72 em outro, sem nenhum dos dois dizer o
  universo — e o que estava errado era o segundo.
- **Varredura não aborta por causa de uma linha.** Comando que varre o acervo
  conserta o que consegue inferir, **relata** o que precisa de texto humano, e sai
  com código ≠ 0 porque parcial não é pronto. Abortar na primeira linha
  irreparável deixa o comando inútil para todas as outras.

## Arquivo novo na pasta de dados nasce com três portas

Quem **escreve** (o comando dono), quem **mostra** (o `/setup`) e quem **checa** (o
`/saude`, quando houver como falhar em silêncio). Enquanto as três não existirem, a
entrega está pela metade.

A porta do meio é mecânica: os arquivos que o plugin possui na pasta de dados vivem
em **uma** lista no `scripts/setup.cjs` (`ARQUIVOS`), lida por quem semeia e por
quem mostra. `scripts/testa-setup.sh` compara o que existe no disco depois do
`--criar` com o que a saída do estado **nomeia**, e a mutação tira um item da lista
para exigir que ele desapareça do estado.

> 2026-08-12: o `projetos.json` nasceu, o `--criar` aprendeu a semeá-lo, e o estado
> nunca soube que ele existia — quem instalasse não tinha onde ver a configuração
> nova. Horas depois, no mesmo dia, a mesma coisa com as pontes de Codex/Gemini:
> capacidade nova exposta só pelo comando que a criou. Nas duas vezes quem apontou
> foi o usuário, e nas duas a regra já estava escrita — como observação plantada,
> que não trava nada. Daí a lista única e o teste com mutação.

## Dependência externa nasce desligada

Recurso que precisa de PowerShell agendado, bridge, plugin de terceiro ou serviço
entra como chave em `hooks/lib/config.cjs` com padrão **falso**, e quem lê a chave
trata falha de leitura como desligado. Quem instalou o plugin não deve descobrir
dependência por mensagem de erro — e a abertura de sessão só reporta o que a
instalação **declara**.

## Regra e injeção

As regras vivem em `skills/rainforest-mind/SKILL.md`. O que fica **antes** da
marca `<!-- detalhe -->` é injetado em toda sessão e paga token; o resto carrega
sob demanda. Incidente datado vai em **blockquote** — o hook o remove da injeção,
e ele continua no arquivo ao lado da regra que fundamenta.

O bloco de núcleos tem teto em bytes (`NUCLEOS_MAX_BYTES`), e é catraca: crescer
regra dói na hora de escrever, não na hora de ler. Se o seu texto não couber,
a saída é **subtrair**, não aumentar o teto.

## Issue e PR

Issue com o comando exato e a saída colada vale dez vezes uma descrição. Se o
relato vier de uma sessão sua com o próprio plugin, rode
`node scripts/conferir-publicacao.cjs <arquivo>` antes de publicar: ele **sai com
código 2** se houver telefone, JID, e-mail, caminho de home ou credencial no
texto.

`main` é protegida: toda mudança entra por PR, inclusive a do dono do repo.
