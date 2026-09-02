# As baterias que o glob nunca chamou (2026-09-02)

Relatório de método do conserto da portaria (`fix/portaria-escreve-worktree`).
O conserto em si — `escreve: true` admitido com worktree obrigatório — está
descrito na emenda de `skills/rainforest-mind/references/regra-10-portaria.md`.
Aqui fica o que o dia ensinou sobre **instrumento**, que é o que costuma
sobreviver ao código.

## 1. Seis baterias verdes que nunca rodaram

As baterias do fluxo 9 são `hooks/testa-portaria-*.cjs`. O glob que define a
suíte casa **só** `.sh`:

- `.github/workflows/baterias.yml:136` — `ls scripts/testa-*.sh hooks/testa-*.sh`
- `CONTRIBUTING.md:11` — o mesmo glob, para rodar local

São seis arquivos, 139 casos, escritos com cuidado visível — o `testa-portaria-nucleo.cjs`
tem caso para payload ilegível, para `git -C` subindo em silêncio, para
frontmatter em CRLF. Todos verdes. **Nenhum jamais executado por ninguém** desde
que nasceram, nem no CI nem no comando local.

Não foi descoberto por auditoria. Foi descoberto porque este conserto **mexeu**
na portaria e alguém rodou as baterias à mão para ver o que quebrava.

### É a quarta trava inerte do mesmo padrão

As três anteriores estão em `2026-09-02-o-conserto-que-nao-alcanca-o-uso-que-o-motivou.md`.
O padrão não varia: **o instrumento responde**. Não estoura, não fica em branco,
não avisa. A variação desta é a mais barata de produzir e a mais difícil de ver:
a bateria não é chamada, e o verde de quem chama as outras parece cobrir essa
também. Ninguém lê um relatório de CI procurando o nome que **não** está lá.

### O conserto, e a alternativa recusada

`hooks/testa-portaria.sh` adota as seis: itera sobre `hooks/testa-portaria-*.cjs`,
roda cada uma com `node`, e reprova se alguma reprovar.

A alternativa — mudar o glob do CI para casar `.cjs` — foi recusada. O glob tem
uma **guarda de piso** (`total < 15` reprova) que existe justamente para pegar
glob quebrado; mexer no glob mexe na guarda junto, e trocaria uma trava por
outra menos testada. O wrapper carrega a mesma guarda, com piso próprio de 6,
pelo mesmo motivo: *"um glob que não casa com ninguém roda zero bateria e sai 0
— é exatamente assim que estas seis passaram despercebidas"*.

### O que isso sugere olhar

Nenhuma máquina nova foi construída para isso agora, mas a pergunta fica escrita:
**quantos outros arquivos de teste deste repositório não são casados por
nenhum glob?** A resposta é um `ls` cruzado com os dois globs, e vale como
issue antes de virar hook.

## 2. A bateria órfã pegou a regressão na primeira vez que rodou

O conserto precisava resolver o estágio ativo **antes** da primeira negação
possível, para que o log parasse de gravar `estagio: "?"`. A primeira versão
disso envolvia o resolver num `catch` que zerava o resultado.

Efeito colateral: instalação quebrada (`scripts/estado.cjs` fora do lugar)
passava a negar dizendo **"sem estágio ativo — abra um fluxo"**. O exit code
continuava certo — 2, fail-closed —, e por isso nada aparentava estar errado. O
que mentia era o **motivo**: mandava o usuário abrir um fluxo, quando o problema
era a instalação.

Quem pegou foi o **caso 15** do `testa-portaria-nucleo.cjs`, que quebra a
dependência interna numa cópia da árvore e afirma que o stderr diz *"falha
interna"*. Ele existe desde o fluxo 9, e **rodou pela primeira vez neste dia**.

O conserto do conserto: o erro é guardado e **sobe** no passo 4, onde a rede de
`main` o converte em exit 2 com "falha interna".

> A régua que sai daqui: **exit code certo não é motivo certo.** Uma negação
> fail-closed com a mensagem errada manda consertar o que não está quebrado, e
> não deixa rastro de que mandou. Este arquivo já dizia "negação muda é bug";
> falta dizer que negação **eloquente e errada** é pior, porque convence.

## 3. O defeito que duas sessões pisaram sem registrar

O bloqueio do `executar` (nenhum agente admitido cobria o estágio) apareceu no
log da portaria em **duas sessões distintas**, com horas de intervalo:

```
02:31 / 02:32 / 02:32  deny executor   [?]  sessão bde80d72…
02:41                  deny planejador [executar]   ← a saída tentada
11:44 / 11:45          deny executor   [?]  sessão be3ae6df…
```

A primeira sessão tentou o `planejador` como saída, levou deny, contornou
implementando na mão — e **o handover que ela escreveu não menciona isso em
lugar nenhum**. O handover tem sete seções sobre travas inertes e nenhuma linha
sobre a trava que a bloqueou naquele mesmo turno.

Não é desatenção isolada: é o formato. Handover registra **o que se entregou** e
**o que falta entregar**; não tem lugar para *"o que me atrapalhou e eu
contornei"*. O contorno funciona, o trabalho anda, e o defeito fica esperando a
próxima sessão.

> A régua: **contorno é achado.** Quando uma trava do próprio repositório barra
> o trabalho e a saída é fazer diferente, isso vai para o handover mesmo que o
> trabalho tenha andado — senão o custo é pago de novo, por alguém que não sabe
> que já foi pago.

## 4. O log respondeu porque tinha sido desenhado para responder

Vale registrar o que **funcionou**. A pergunta "isso já vinha acontecendo?" foi
respondida em um comando, com data, sessão e motivo, porque o `despachos.jsonl`
é append-only e cada linha é autocontida (D4 do fluxo 9). Sem ele, a resposta
seria memória de duas sessões — e uma delas não tinha registrado nada.

O mesmo log expôs a própria lacuna: as cinco negações traziam `estagio: "?"`,
porque a negação acontecia antes da resolução do estágio. Evidência boa o
bastante para revelar onde ela mesma é cega é rara; a correção veio junto.

## 5. Estado das travas, ao fim

| Trava | Como se saiu |
|---|---|
| Portaria (fluxo 9) | barrou o despacho, com motivo correto — o desenho funcionou, a **cobertura** do manifesto é que estava incompleta |
| Baterias `.cjs` do fluxo 9 | **inertes** desde o nascimento; adotadas por `hooks/testa-portaria.sh` |
| Caso 15 (falha interna) | pegou uma regressão real, na primeira execução da vida |
| Catraca de mutação | três mutações, as três vermelhas — a trava de isolamento, a recusa de nomeado e o estágio no log |
| Teto de `references/` | reprovou o primeiro rascunho da emenda (12.073 B contra 10.500), forçando a separação entre **elaboração de regra** e **relatório de método** — que é a divisão certa e não teria acontecido sozinha |
