# Onde moram os seus dados


Onde moram `FOCO.md` e `ideias.jsonl` sai de uma **cadeia de quatro níveis**, do
mais específico para o mais genérico — o projeto sobrescreve o global, e a
detecção automática cobre quem não declarou nada:

| # | Nível | Onde | Para quê |
|---|---|---|---|
| 1 | `RFM_ROOT` | onde a variável apontar | declaração explícita, vence tudo |
| 2 | **projeto** | `<repo>/.rainforest/` | **foco e ideias daquele repo** |
| 3 | global | `~/.rainforest/` | o seu estado, valendo em qualquer pasta |
| 4 | plugin | a raiz do próprio plugin | instalação auto-hospedada (desenvolvimento) |

O que faz uma pasta contar como raiz é ter `FOCO.md` **ou** `ideias.jsonl`
dentro: um `.rainforest/` vazio criado por engano não sequestra o seu foco — e
tem teste de mutação provando que é o marcador que decide.

**O nível 3 é o seu `HOME`, e não a pasta de config do Claude Code.** A
diferença parece detalhe e não é: dá para ter mais de uma config dir na mesma
máquina — uma de trabalho e uma pessoal, por exemplo —, e ancorar o estado nela
partiria o seu foco em dois sem avisar. O foco é da pessoa, não do perfil.

Um terceiro arquivo da pasta de dados é o **`projetos.json`**, o vocabulário
fechado de slugs de projeto (`slug → caminho + apelidos`). É ele que tira o
caminho de disco de dentro do dado — o campo `projeto` das ideias era texto
livre e guardava caminho do Windows dentro de string JSON, onde a barra
invertida seguida de `r` é escape de *carriage return*: quatro registros
tiveram o caminho comido, e 22 valores distintos para 7 projetos reais
deixaram o campo inagrupável. Slug não tem barra para escape nenhum comer, e a
pasta de cada projeto passa a ter um lugar só seu.

**O repositório é só código.** `FOCO.md`, `ideias.jsonl` e `projetos.json` não
moram aqui e não entram no git: quem instala o plugin recebe as regras, não o
foco nem as ideias de quem o publicou. Antes disso ser assim, um projeto novo herdava o estado
alheio pela cadeia — o nível 4 existe para desenvolvimento e é justamente onde
esse defeito nascia.

Criar `.rainforest/FOCO.md` num repositório é tudo o que é preciso para aquele
repositório ter foco próprio. Sem variável de ambiente, sem editar config.

### O FOCO.md tem teto, e quem o segura é um script

A seção **Avanços** é append-only por natureza: cada sessão que anda escreve
uma linha datada, e nenhuma sai. Em 2026-08-12 o arquivo estava com 15,4 KB, dos
quais 11,8 KB só de Avanços — e ele é lido **inteiro** por toda sessão que
precisa conferir prazo, marco ou avanço, porque é isso que a própria injeção
manda fazer. Pior: as três entradas de um único dia produtivo custaram mais que
os cinco dias anteriores somados, então teto em *contagem de entradas* não
segura nada.

```
node scripts/foco.cjs caminho                 # onde mora o foco desta raiz
node scripts/foco.cjs rotacionar              # ensaio: diz o que sairia
node scripts/foco.cjs rotacionar --aplicar    # move de verdade
```

O que passa do teto (5.000 B por padrão, em **bytes**) vai para o `AVANCOS.md`
ao lado, em ordem cronológica, e o FOCO.md ganha no topo do bloco uma linha
`- (histórico: N avanços de … a … em AVANCOS.md.)` — que o hook trata como
residente, para a injeção nunca dizer que as entradas antigas "continuam no
FOCO.md" quando elas já não estão. Nada é apagado: a igualdade entre o que sai
e o que entra é conferida **antes** de qualquer escrita, e sem `--aplicar` o
script não toca em disco. O `fechar` e o `/foco` chamam a rotação logo depois de
escrever o avanço.

- Fork à vontade: troque os arquivos de dado pelos seus e as regras pelo seu
  jeito de trabalhar. Nenhum caminho é cravado no código:

  | Variável | Resolve |
  |---|---|
  | `RFM_ROOT` | raiz dos dados — nível 1 da cadeia acima |
  | `CLAUDE_CONFIG_DIR` | pasta de config: a checagem de dependências e o nível 3 |
  | `WHATSAPP_API_BASE_URL` | host e porta do bridge, para os vigias e o hook |
  | `RFM_CLAUDE_EXE` | binário do Claude Code usado pelos vigias headless |

