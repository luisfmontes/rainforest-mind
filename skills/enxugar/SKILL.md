---
name: enxugar
description: Análise de código morto, inflação e abstração não usada — dois modos, mesmo método. Revisa um diff ou audita o repo inteiro, listando (nunca aplicando) o que pode sair.
---

# Enxugar

Método para identificar código que pode ser removido ou reduzido sem afetar o
comportamento observável. A skill **lista e não aplica** — decisão e remoção
são do usuário.

## Escopo

Escopo fechado por **cinco tags**, cada uma marcando um tipo diferente de
candidato à remoção. Fora de escopo:

- **Correção, segurança e performance** — essas vão para `revisar` e
  `auditor-de-seguranca`. Código lento mas necessário não sai.
- **Estilo e preferência pessoal** — "eu escreveria diferente" é opinião, não
  achado. Só entra se violar padrão documentado do repo.
- **O mínimo de um check executável** — regra do próprio `modo-dev`. Uma suíte
  com um caso, uma lint com uma regra: nunca marcado para deleção.

## Os cinco tipos

### `apagar:` — Código morto, nunca chamado

Função, classe, módulo, case, bloco ou feature flag que:

- Não tem chamador em nenhum lugar do repo (procure por grep/symbol).
- Não é exportado para fora do repo (public API documentada, package.json
  `main`/`exports`, endpoint registrado).
- Não é ativado por configuração que ainda existe (ou a config foi removida e
  ele junto).

Exemplo: função deletada em todos os `require()` mas deixada no arquivo.

**Substituto:** nada — linha sai.

### `stdlib:` — A biblioteca padrão já faz isso

Código que reimplementa funcionalidade que:

- A biblioteca padrão da linguagem/plataforma já oferece (ex: `String.prototype.padStart()` em vez de `lpad` feito à mão).
- Um pacote que já está no `package.json`/`requirements.txt` oferece (não trazer novo).
- Um método do próprio objeto oferece (`Array.prototype.find()` em vez de loop
  manual).

**Substituto:** chame a função padrão por nome. Ex: `"stdlib: String.padStart()"`

### `nativo:` — A plataforma já faz isso

Código que duplica um recurso nativo do SO ou plataforma:

- Node oferece (fs, path, child_process, etc).
- Windows/Linux oferece (variáveis de ambiente, temp dir, clipboard, etc).
- Banco de dados oferece (função de data, regex, hash).

Não confunda com `stdlib` — este é "a linguagem", aquele é "o ambiente".

**Substituto:** nomeie o recurso nativo. Ex: `"nativo: os.tmpdir()"`

### `yagni:` — Abstração com uma implementação

Camada, helper ou padrão que existe para suportar múltiplas formas, mas há
apenas uma forma usada:

- Interface com um único implementador.
- Config que ninguém muda (sempre o mesmo valor, ou nunca é alterado).
- Função de escopo, genérica, com um chamador só.
- Padrão strategy/factory para um cenário singular.

YAGNI = "You Aren't Gonna Need It" — a abstração economiza **quando vai mudar**.
Se não vai, empoeira.

**Substituto:** colapse para a forma concreta usada.

### `encolher:` — Mesma lógica, menos linhas

Refactoring óbvio que reduz linhas sem mudança de comportamento:

- Loop que pode ser uma compreensão ou `map()`.
- Condicional aninhada que pode ser `&&` / `||`.
- Função que retorna o resultado de uma outra, passando args.
- Variável intermediária desnecessária.
- Comentário duplicado com o nome da função.

Diferente de `apagar` (remove tudo), `encolher` **mantém a lógica** — a forma
fica só menor.

**Substituto:** a forma curta. Mostre a transformação. Ex: `"encolher: 3→1 linha: use map() em vez de loop"`

## Dois modos, mesmo método

### Modo 1: Revisar um diff

```
/enxugar --diff
```

Recebe o diff atual (por git ou especificado), localiza linhas novas/mudadas,
procura em cada bloco editado pelos cinco tipos acima. Sai com os achados
**da mudança**, não do repo todo.

Caso de uso: "o que eu só adicionei que pode sair?"

### Modo 2: Auditar o repo inteiro

```
/enxugar
```

Varre o repositório inteiro, listando achados em toda a base. Sai com todas as
oportunidades.

Caso de uso: "onde está o desperdício no projeto?"

## Formato de achado

Uma linha por achado, sempre nesta ordem:

```
<arquivo>:L<n>: <tag> <o que cortar>. <o que entra no lugar>.
```

Onde:

- `<arquivo>` — caminho relativo ao root do repo.
- `L<n>` — linha onde começa. Se bloco, L<início>-<fim>.
- `<tag>` — uma das cinco: `apagar`, `stdlib`, `nativo`, `yagni`, `encolher`.
- `<o que cortar>` — o texto/conceito que sai (nomeie, não descreva).
- `<o que entra>` — o substituto, se houver. Nada = zero caracteres.

**Exemplos:**

- ❌ Vago e prolixo: "O arquivo `util/helpers.js` não está sendo usado em nenhum lugar do código, e a função é uma abstração que não oferece valor. Poderia ser removido para deixar o código mais limpo."

- ✅ Acionável: `util/helpers.js:L1-42: apagar util/helpers.js. `

---

- ❌ Sem substituto nomeado: "Tem um helper pra calcular hash aqui que replica a lib crypto."

- ✅ Com nome: `crypto-helper.js:L5-8: stdlib crypto.createHash(). `

---

- ❌ Mistura refactor com redução: "Aqui o for pode virar um map, economizando 4 linhas e ficando mais legível."

- ✅ Apenas redução: `utils.js:L23-27: encolher 5→1 linha: use Array.map() em vez de for. `

## Ranking

Achados saem **ordenados pelo maior corte primeiro**. Ao final, feche com:

```
líquido: -N linhas
```

Onde N é a soma de linhas removidas menos linhas adicionadas (o delta real).

Se não houver nada a cortar:

```
Já está enxuto.
```

## Nenhum check executável é marcado

Se o repo tem um linter, bateria de testes ou validação que roda no CI, nada
dela é candidato à deleção — nem que execute um caso só.

Se encontrar um, reporte a oportunidade separadamente (issue/design), mas não
marque para corte. O teste que falha quando você tira é prova de que serve.

## Incidente 2026-07-15: correção mascarada de economia

Um agente recomendou remover um bloco inteiro de validação por ser "redundante".
O teste continuava passando porque havia um check anterior que capturava o erro
— o segundo era de fato morto. Mas o check anterior falhava para casos onde a
validação posterior deveria servir. A remoção "economizava" 12 linhas e introduzia
um bug. A regra acima (nenhum check é apagado) previne exatamente isso.

---

## Exemplos

### Ruim: achado sem ação clara

❌ **Entrada:** revisar um diff de refactor em `src/math.js`

❌ **Achado vago:** "tem umas funções antigas que parecem não ser usadas"

❌ **Por quê:** "umas funções" não é nome. Não está testável se a ação foi
feita.

### Bom: achado acionável

✅ **Entrada:** revisar diff em `src/math.js:L45-92`

✅ **Achado:** `src/math.js:L45-52: apagar sum(). `

✅ **Por quê:** Nome da função (sum), arquivo, linhas. Só o que cortar. Se o
diff tem outras mudanças no mesmo arquivo, só sum entra no achado (diff-mode).

---

### Ruim: confundir abstração com economia

❌ **Entrada:** auditar `server/` inteiro

❌ **Achado:** "a camada de Models duplique a lógica do banco — poderia
remover a camada e chamar o banco direto"

❌ **Por quê:** Abstração com um implementador é `yagni`, não apagar. E mudar
arquitetura é escopo demais para `enxugar`.

### Bom: reconhecer yagni sem remover

✅ **Entrada:** auditar `server/`

✅ **Achado:** `server/models/index.js:L1-40: yagni UserModel (um implementador só). Colapse para orm direto. `

✅ **Por quê:** Nomeado, localizado, ideia proposta — mas o critério de sucesso
é que entra num design-doc pra discussão, não sai no próximo commit.

