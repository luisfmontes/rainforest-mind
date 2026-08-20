---
name: analisar
description: >-
  Método para conduzir uma análise de dados em notebook como um analista de
  verdade pensaria — uma pergunta de cada vez, em células curtas, confirmando
  cada achado antes de interpretá-lo. Use sempre que for analisar dados,
  explorar um DataFrame, fazer EDA, investigar um dataset ou criar
  visualizações em Python/pandas.
---

# Como conduzir uma análise de dados

A diferença entre um notebook bom e um ruim não é o código — é o raciocínio.
Um notebook ruim tem outputs mas não tem conclusões. O ciclo abaixo é o coração
de uma boa análise.

## Antes de tocar no código: entender o problema

Análise sem pergunta de negócio é só estatística descritiva à toa. Antes de
criar o notebook você precisa de três coisas: **o que se quer decidir**, **quem
vai ler o resultado** e **o que significam as colunas ambíguas**.

A terceira quase nunca sobe: coluna ambígua se resolve olhando — `head()`,
dicionário de dados, README do dataset, os próprios `value_counts()`. Só vira
pergunta o que continuar ambíguo **depois** de você ter olhado.

O que sobrar sobe na **rodada numerada**, não numa lista solta de perguntas —
`Q1`, `Q2`, cada uma já com a resposta recomendada, e então pare e espere:

> ❓ **Q1 — A decisão por trás disso**: o que muda no negócio dependendo do que
> a análise mostrar?
> ➡️ **Recomendo:** ... (com o porquê, em uma linha)

Não invente o objetivo. Análise sem decisão do outro lado é relatório que
ninguém lê.

## O ciclo (obrigatório)

Para cada coisa que quiser descobrir, repita:

1. **Pergunta** — crie uma célula markdown com a pergunta que quer responder.
2. **Código** — crie a célula que responde *aquela* pergunta. Curta.
3. **Execute** — rode e leia o output de verdade.
4. **Confirme o resultado** — se a célula respondeu a uma pergunta (um achado:
   taxa, ranking, comparação, padrão), passe pela **revisão crítica** (seção
   abaixo) antes de interpretar. Se algo não fechar, **ajuste a própria célula**
   (mostre o `n`, troque absoluto por taxa, controle por exposição) até a
   conclusão aguentar.
5. **Reflita** — crie uma célula markdown curta interpretando o resultado *já
   confirmado*. Não repita os números — interprete.
6. **Próxima pergunta** — só então decida o que investigar em seguida, com base
   no que acabou de descobrir.

**Não escreva 10 células de uma vez para rodar depois.** Uma pergunta por vez.
Pular a reflexão (passo 5) ou a confirmação do resultado (passo 4) é o erro mais
comum e o mais grave.

Fechada cada etapa do arco (carregar, limpar, cruzar…), diga em uma linha onde
está e o que vem — o ciclo é longo e quem lê perde o fio sem isso.

## Como a célula nasce e roda

O passo 3 só existe se houver mecanismo. Antes da primeira célula, resolva os
dois lados — **ferramenta** e **ambiente** — e diga qual você está usando.

**Ferramenta.** Quem cria e edita célula é o `NotebookEdit`. Ele costuma vir
**diferido**: sem carregar o esquema primeiro, a chamada falha. Carregue com
`ToolSearch("select:NotebookEdit")` antes de tentar. E saiba o limite dele:
**`NotebookEdit` escreve a célula, não executa nada.** Célula escrita e não
executada é célula sem output — exatamente o notebook que esta skill existe
para evitar.

**Execução.** Rodar é um comando à parte:

```bash
jupyter nbconvert --to notebook --execute --inplace analise.ipynb
```

Depois releia o notebook e olhe o output da célula nova. Isso reexecuta tudo do
topo a cada pergunta: bom, porque o estado sempre bate com o que está escrito —
nada de variável viva que só existe na sua sessão; e caro, porque o custo cresce
com o tamanho do notebook. Quando o carregamento começar a dominar, congele-o
(`to_parquet` uma vez, `read_parquet` daí em diante) em vez de abandonar o
ciclo de uma pergunta por vez para economizar tempo.

**Ambiente.** Confira o que o projeto já usa (`venv`, `uv`, `poetry`) e use
aquilo. Faltando `pandas`, `matplotlib` ou `jupyter`, **pare e pergunte** — você
não instala nada no interpretador do usuário por conta própria.

**Sem ambiente de notebook**, o degrau abaixo é legítimo: um `.py` executado a
cada pergunta, com o output no terminal. O ciclo não muda — pergunta em
comentário, roda, lê a saída real, escreve a interpretação. Só **diga em voz
alta** que desceu para isso, porque o entregável deixa de ser um notebook
legível por quem pediu.

## Células curtas, outputs inspecionáveis

IAs tendem a gerar células enormes, cheias de comentários óbvios e lógica
empilhada. Não faça isso.

- **Cada célula responde UMA pergunta.** A maioria das células de análise tem
  1-3 linhas; plots ficam em torno de 5. Passou de 10 linhas, a célula mistura
  preparação com visualização — separe.
- **Sem comentários que repetem o código.** `# Calculando a média` em cima de
  `df["x"].mean()` é ruído. Use células markdown para raciocínio.
- **Outputs inspecionáveis, não dumps.** Prefira `.head()`, `.shape`,
  `.describe()`, `.value_counts()`. Nunca imprima DataFrames inteiros.
- **Series → DataFrame na hora de exibir.** Se o output for uma `Series`
  (ex: `value_counts()`), envolva para exibir: `serie.to_frame()`.
- **Transformou, verifique.** Toda célula que modifica o DataFrame termina
  exibindo uma amostra das colunas afetadas, para conferir que a transformação
  fez o que devia.
- **Sempre execute** as células. Se der erro, leia o traceback real antes de
  corrigir — não chute.

Bloco padrão de imports (só importe o que for usar; o resto, na célula que
precisar):

```python
import pandas as pd
import matplotlib.pyplot as plt

pd.set_option("display.max_columns", None)  # mostra todas as colunas, sem cortar com "..."
```

## Títulos de seção são perguntas, não rótulos técnicos

O título de uma seção markdown reflete O QUE se quer descobrir, não a técnica.
O notebook será lido por pessoas de negócio — zero jargão de data science.

- ❌ "Análise Univariada" → ✅ "Quantos pedidos tiveram atraso na entrega?"
- ❌ "Análise Bivariada" → ✅ "O frete influencia a nota da avaliação?"
- ❌ "Correlações" → ✅ "Quais variáveis andam juntas?"

## Markdown ANTES da célula: a intenção

Uma frase curta dizendo o que vai investigar e por quê. Sem jargão.

```markdown
## O estado do cliente influencia o tempo de entrega?
Vamos comparar o tempo médio de entrega por estado.
```

## Markdown DEPOIS da célula: o que o resultado significa

Depois de executar e ver o output, escreva o que aquilo significa no contexto
do problema. **Não repita os números — interprete.**

```markdown
**Resultado:** entregas no Norte levam ~2x mais que no Sudeste, provavelmente
por distância dos centros de distribuição. Vale investigar o custo de frete.
```

## Revisão crítica: confirmar o resultado antes de virar conclusão

Use **só nas células que respondem a uma pergunta** da análise — um achado de
verdade. Em import, carregamento ou transformação, não precisa. Antes de
escrever a interpretação, pare e percorra mentalmente:

- **O `n` está visível?** Toda taxa ou média vem com o tamanho da base do lado.
  Taxa sobre base pequena não é achado, é ruído — e num ranking por taxa, um
  único caso extremo pode liderar.
- **É share ou risco?** "X concentra 70% das mortes" mede o tamanho do grupo;
  "X tem 2,3× mais mortes por ocorrência" mede o risco. São coisas diferentes —
  se a pergunta é sobre risco, use a taxa, não o share.
- **Tem outra explicação?** Pergunte "o que mais explicaria isso?". Ex: "dias
  limpos têm mais mortes" pode ser só porque dia limpo é o mais comum — mais
  exposição, não mais risco. Quando a pergunta é risco, controle por exposição.
- **A janela é pequena?** Recortes curtos (um feriado de 3 dias, um único mês)
  são sensíveis a um evento extremo. Sinalize a fragilidade, não venda como
  tendência.
- **Estou afirmando causa sem base?** Os dados mostram associação, não causa.
  Não escreva que A "causa" B sem como isolar isso — e nunca cite uma variável
  que não existe no dataset.

Se algum ponto não fechar, não escreva a interpretação ingênua: ajuste a célula
e escreva a conclusão honesta — a que sobrevive a essas perguntas. Se o achado
não se sustenta, diga isso; é uma conclusão válida.

## Os dados foram lidos corretamente?

Faça esta checagem **uma vez**, logo após o `read_csv`/`read_excel`, antes de
analisar qualquer coisa. Dado lido errado contamina tudo o que vem depois.
Sintomas mais comuns:

- **Rótulos com caracteres estranhos** (`?`, `Ã`, caixas) → encoding errado.
  Teste `utf-8`, `latin-1`, `cp1252`.
- **Tudo numa coluna só** → separador errado (`,` vs `;` vs tab). Ajuste `sep`.
- **Número virou texto ou NaN** → separador decimal/de milhar incompatível.
  Ajuste `decimal` (e `thousands` se houver).
- **Linhas estranhas no topo** (título antes do cabeçalho) → `skiprows`.
- **Colunas a mais ou vazias no fim** → separador sobrando ou rodapé →
  `skipfooter`.
- **Datas como texto** → não é erro de leitura; anote para converter depois.

Confirme sempre olhando: `df.shape` (bate com o esperado?), `df.dtypes` (os
números são numéricos?) e um `df.head()` (os rótulos saíram legíveis?). Releia
com os parâmetros corrigidos até o `head()` ficar limpo.

> Atalho útil: dado de governo brasileiro (PRF, IBGE, DATASUS…) costuma ser
> `sep=";", encoding="latin-1", decimal=","`. Bom primeiro palpite — mas
> confirme com o `head()`, não assuma.

## Gráficos: claros primeiro, bonitos sempre

Um gráfico existe para tornar uma resposta óbvia. Comece pela pergunta, não
pelo gráfico:

- **Comparar categorias / ranking** → barra, **ordenada por valor** (horizontal
  se os rótulos forem longos).
- **Evolução no tempo** → linha; marque eventos relevantes com anotação direta.
- **Distribuição** → histograma; boxplot para comparar grupos.
- **Relação entre dois números** → dispersão.
- **Dois categóricos × uma métrica** → heatmap.
- **Parte do todo** → evite pizza; barra lê melhor.

Clareza — menos é mais: destaque o essencial com a cor de destaque e deixe o
resto neutro; tire o lixo gráfico (moldura superior/direita, legenda
redundante); rotule direto no gráfico quando der; título que diz o achado (sem
afirmar o que o dado não sustenta); barra começa no zero; escala justa. Nada de
figura espremida — use o espaço, fontes legíveis.

Logo abaixo dos imports, crie **uma célula de estilo** com as cores e os
parâmetros globais. Todo gráfico usa essas variáveis — mesma categoria, mesma
cor em todos os gráficos:

```python
COR_PRIMARIA   = "#0072B2"   # série principal
COR_SECUNDARIA = "#94A3B8"   # apoio / elementos neutros
COR_DESTAQUE   = "#E69F00"   # realçar o ponto-chave
PALETA = ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00"]

plt.rcParams.update({
    "figure.figsize": (10, 6),
    "figure.dpi": 110,
    "font.size": 12,
    "axes.titlesize": 15,
    "axes.titleweight": "bold",
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.alpha": 0.25,
    "axes.prop_cycle": plt.cycler(color=PALETA),
})
```

## Valores em reais (formatação PT-BR)

Quando a análise envolve dinheiro, `8497.0` é ilegível. Defina um helper no
começo do notebook e use **só na exibição** — não altere os dados originais:

```python
def reais(v):
    return f"R$ {v:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
```

**Atenção com o `$` nas células markdown:** no Jupyter, `$...$` vira fórmula
matemática. Escreva o valor em código inline (`` `R$ 8.497` ``) — dentro de
crase nada é interpretado. Em prosa corrida, escape com barra dupla (`R\\$`).
O mesmo vale para `*`, `_` e `~` soltos no texto.

## O arco natural da análise

Não precisa ser rígido, mas saiba em qual etapa está:

1. **Carregar** — `read_csv`, `shape`. Logo de cara, faça a checagem de leitura
   (seção acima) — uma vez.
2. **Conhecer** — que colunas? que tipos? tem dado faltando?
3. **Limpar** — corrigir tipos, tratar nulos, remover duplicatas.
4. **Explorar uma variável de cada vez** — como se distribui? valores mais comuns?
5. **Cruzar variáveis** — X influencia Y? tem padrão entre essas duas colunas?
6. **Resumir** — uma célula markdown com as conclusões principais ao final.

## Formato de resposta

Comece com UMA pergunta. Não planeje o notebook inteiro de antemão. Crie a
markdown + código, execute, leia, interprete, e só então avance. Trabalhe como
um analista: uma pergunta de cada vez.

## Continuar uma análise que já tem conclusão

A célula de conclusão é um **resumo vivo no fim do notebook** — não uma parede.
Quando o usuário pedir para aprofundar, **não escreva as novas células abaixo
da conclusão**:

1. Insira as novas células (pergunta → código → interpretação) **imediatamente
   acima** do bloco de conclusão.
2. Depois, **atualize a conclusão** para incorporar as novas descobertas.

**Exceção:** se o novo pedido começa uma análise de assunto realmente diferente,
o certo seria um notebook novo. Nesse caso, **pergunte ao usuário** se prefere
continuar aqui ou começar outro notebook.

## Isto não é trabalho de subagente

O ciclo acima é síncrono com quem pediu: pergunta o objetivo e **espera**, faz
uma célula, a pessoa lê, e só então a próxima pergunta nasce do que apareceu.
Subagente roda destacado e devolve relatório — despachado, ele produz
exatamente o notebook que esta skill proíbe: dez células de uma vez e a
conclusão escrita antes de alguém ter olhado um output. A análise fica na
janela principal.

O que **cabe** despacho é a seção "Revisão crítica" virada contra um notebook
já pronto: ler o artefato real e tentar derrubar cada achado (`n`, share vs.
risco, explicação alternativa, janela curta, causa sem base). Isso é
adversarial, não-interativo, e é o formato do `revisor`.
