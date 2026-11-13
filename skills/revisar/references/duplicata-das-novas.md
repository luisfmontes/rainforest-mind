# Duplicata das funções novas

Quem lê: o `revisar`, no passo (b2) de `agents/revisor.md`. Este arquivo diz como
conferir se uma função que o diff cria já existe no repositório.

## (a) Por que existe

O plano previne a cópia: o `busca:` obriga a procurar antes de criar função nova.
O desenho está em `docs/rainforest/design/2026-11-13-reuso-antes-de-criar.md`. Mas
o plano nem sempre pega. No caso que originou o desenho, a cópia foi consciente:
quem gerou sabia que a função existia e copiou (comentários como "molde de
RetratoAcesso"). Por isso o `revisar` é a rede. Ele olha só o que o diff criou e
compara com o catálogo do repositório.

## (b) O passo

1. Liste as funções que o diff cria:

   ```
   node <plugin>/scripts/catalogo-funcoes.cjs novas --raiz <repo> --base <base>
   ```

   `<base>` é a mesma base do `git diff <base>...<head>`. A saída é um array JSON,
   com `arquivo`, `linha`, `nome`, `assinatura` e `linguagem`. Se sair com erro
   (`novas: base não resolvida`), a conferência não rodou: registre `LACUNA`, nunca
   "sem duplicata". Array vazio quer dizer que o diff não criou função nas
   linguagens que o catálogo lê; diga isso.

2. Leia o catálogo do repositório:

   ```
   node <plugin>/scripts/catalogo-funcoes.cjs listar --raiz <repo> --contexto 3
   ```

3. Para cada função nova, escolha as candidatas no catálogo:
   - entradas de nome parecido (mesmo radical ou sinônimo óbvio, como
     `formatarData` e `dataParaTexto`);
   - entradas da mesma pasta do arquivo novo;
   - funções que o próprio diff toca.

   A função nova também aparece no catálogo. Ela não é candidata a si mesma.

4. Abra a implementação da nova e de cada candidata. Compare o que acontece na
   entrada e nos casos de borda (nulo, vazio, erro). Nome parecido não basta, e
   nome diferente pode fazer a mesma coisa.

5. Dê a cada par um nível de confiança, pela escala da seção (c).

## (c) Escala de confiança

Copiada de `skills/enxugar/references/duplicata-semantica.md`, bloco "Confiança"
da Fase 4 (comparar):

- **HIGH**: mesma entrada dá a mesma saída. Ex.: `formatarData(d)` e
  `dataParaTexto(d)` formatam igual.
- **MEDIUM**: mesmo propósito com diferença menor. Ex.: `validarEmail` com regex e
  `checarEmail` com biblioteca.
- **LOW**: talvez relacionadas. Ex.: `sanitizar(s)` e `escaparHtml(s)`.

A mesma fonte manda, na dúvida, não consolidar. Aqui, na dúvida, o par não é HIGH.

## (d) Consequência

- **HIGH**: achado `[alta]` (comportamento errado). Cite `arquivo:linha` da função
  nova e `arquivo:linha` da existente, e o cenário: a mesma entrada dá a mesma
  saída. Leva a `VEREDITO: reprovado`.
- **MEDIUM** e **LOW**: observação, numa seção `## Observações`, sem etiqueta de
  severidade. Não reprovam.

## (e) O que não é achado

Antes de reprovar, confira se o par cai em uma destas situações. Se cai, não é
achado:

- **Artefato isolado que o design declara** (D4 do desenho). Ex.: relatórios por
  fundo, copiados de propósito para que a mudança de um não afete o outro. Confira
  no desenho, ou na linha `catalogo` com `desfecho: construir` do `busca:` da
  tarefa, com o motivo que aponta a decisão.
- **Cópia que o design decidiu.** Se o desenho fecha a cópia como decisão, cite a
  decisão e não reprove.
- **Wrapper que só chama a existente.** Pela trava de wrapper da seção `duplicar:`
  de `skills/enxugar/SKILL.md` ("cópia vs. wrapper vs. refactor necessário"): se o
  trecho chama a função existente, é utilidade, não cópia.
- **Função de convenção do framework.** Ex.: `ModelDef`, `ViewDef` e `MenuDef` em
  MVC do Protheus. O framework exige o nome, e cada fonte tem a sua.

## (f) Linguagens

O catálogo lê:

- JS/TS: `.js`, `.cjs`, `.mjs`, `.ts`, `.tsx`, `.jsx`
- Python: `.py`
- Dart: `.dart`
- ADVPL/TLPP: `.prw`, `.prx`, `.tlpp`, `.ch`. O método `Method x() Class Y` entra
  como `Y:x`. A declaração recuada dentro do corpo da classe não conta.

Fora dessas extensões a checagem não roda. Escreva no relato
`duplicata: pulada, <extensão> fora do catálogo`. Não escreva que não há duplicata.
