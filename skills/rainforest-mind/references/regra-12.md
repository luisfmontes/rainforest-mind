# Regra 12 — Entrega de agente se valida na saída real

Agente reporta o que
pretendia, não o que aconteceu — sem mentir: ele mede de um jeito que não
pode falhar (2026-08-07: 5 de 7 erros do dia eram isso). As formas
recorrentes, todas com suíte verde: **teste tautológico** (o teste escolhe
o próprio caminho de saída e verifica que um arquivo que ninguém criou não
existe — passa com o código de produção intocado); **mutação falsa**
(tabela verde "mutação → teste pega" quando a única mutação que dispararia
o teste seria sabotar a função nova, não reverter o comportamento real);
**fase renomeada** (itens não feitos viram "próximas fases" num relatório
de sucesso — um agente entregou 1 de 6 itens assim); **aritmética que não
fecha** (675 + 7 ≠ 676) e **código contradizendo o próprio docstring**.
Detector automático não pega nada disso.
(acervo: 2026-08-07)

**E ele inventa nos dois sentidos.** A seção "Verificação" de um relatório
não é transcrição de saída: é **prosa gerada no formato de uma transcrição**.
O mesmo gerador que produz ✓ falso produz ⚠ falso — um esconde defeito, o
outro queima um ciclo de auditoria desmentindo problema que não existe.
Consequência dura: **nenhum identificador sai do relato para dentro de um
comando.** Hash, digest, URL de PR, número de issue — a janela principal
re-deriva tudo de `git`/`gh`. Isso neutraliza a invenção sem depender de o
agente melhorar.
(acervo: 2026-08-09)

Defesas: (1) o **critério de
sucesso vem pronto no briefing**, nunca é construído pelo executor —
qual comando rodar, qual saída inspecionar, qual mutação (que **reverta o
comportamento real**, especificada) deve fazer qual teste falhar. O
briefing **nomeia a falsificação**: comando exato e saída exata que
provariam a entrega errada. Adjetivo não é critério — "não decorativo",
"de verdade", "robusto" são convencíveis; `curl` devolvendo uma string
específica não é;
(2) validar toda entrega **executando o artefato real e olhando a saída**
— suíte verde e relato não são evidência; entrega de worktree tem a parte
mecânica pronta no `conferir-entrega.cjs` da regra 11, e rodá-lo **não é
opcional**: relatório internamente coerente é indistinguível de relatório
verdadeiro por leitura, e só a comparação com o **estado do worktree** separa
os dois. A checagem de **entrada não commitada é reprovação**, não aviso;
(acervo: 2026-08-19)

(3) o relatório lista
**cada item do briefing** com feito/não-feito — "próximas fases" não
pedidas e números que não somam são gatilho de auditoria, não detalhe;
(4) agentes concorrentes **não compartilham a mesma instância de browser**
(Playwright) — trocam de aba um sob o outro e leem a página errada;
(5) **comando cujo exit code é o sinal não vai para dentro de pipe** —
`| tail`, `| grep`, `| head` devolvem o exit do último elo. Use
`${PIPESTATUS[0]}` ou não canalize.
(acervo: 2026-08-09)

(6) o **medidor também pode estar quebrado**, nos dois sentidos — falso verde
e falso vermelho. Antes de aceitar o resultado de um instrumento improvisado
(contagem por grep, harness de teste, script de medição), confirmar que ele
fala a **mesma língua do que mede** — payload emitido por node se mede em
node, nunca atravessando fronteira de codificação ou de interpretador só para
contar — e que ele **acende** num caso que tem de acender, antes de usá-lo
para reprovar outro. Saída vazia, ou idêntica entre casos que deveriam
diferir, é sintoma do medidor até prova em contrário. E o mesmo vale para a
LEITURA da saída: o veredito de uma bateria é o exit code e a linha de placar,
nunca um grep de substring — bateria que exercita mutação imprime o vermelho
esperado no meio do verde, e quem grepa `FALHA` lê defeito onde há prova.
(acervo: 2026-08-11, 2026-08-22, 2026-08-26)

(7) **campo vazio não é campo ok.** Instrumento que responde por registro —
tarefa agendada, job, fila, endpoint de saúde — pode trazer todo campo de
estado dizendo "saudável" e guardar a verdade num campo em **branco**. Branco
lê-se como "nada de errado", nunca como "não vai acontecer": é o único formato
de resposta que não dispara leitura. Os campos de estado provam o **passado**;
antes de dar um registro por vivo, nomear qual campo prova a **próxima
ocorrência** e conferir que ele está preenchido.
(acervo: 2026-09-01)

**Exit ≠ 0 nunca é descrito como sucesso** — nem "quase passou", nem "passou com aviso", nem "falhou só por X"; o número é a verdade e a prosa se ajusta a ele. Nasceu do fluxo 7 (recibo), que traduz o contrato validate→deliver do archify: entrega congela bytes só depois de exit 0, e recibo declara o que NÃO prova.
(acervo: 2026-09-02)

**Critério que nomeia um arquivo leva o caminho conferido.** Nome sem caminho,
e cláusula "se existir", são licença para o agente concluir ausência onde só
faltou olhar na convenção certa — "se existir" só entra quando a inexistência
for parte do que se quer medir.
(acervo: 2026-08-17)

**O experimento controlado do briefing falsificável.** Dois executores, mesma
sessão, mesmo tipo de tarefa, resultados opostos — e a variável não foi
modelo, worktree nem ênfase:
(acervo: 2026-08-09)

**A mutação é o segundo passo do critério, não adorno — e quem escreveu o
teste é o pior juiz de se ele morde.** Suíte verde prova que o teste passa,
não que ele **serve**: o briefing de qualquer bateria nova pede, depois do
verde, "quebre a peça que a checagem afirma proteger, cole a saída vermelha,
desfaça, cole a verde de novo". A mutação **mantém o artefato executável** —
mutação que rebenta a execução mede o `catch`, não o comportamento — e o teste
afirma que o resultado mutado é **não-vazio** antes de julgar a diferença. E a
integração **repete a mutação por conta própria**, no fonte de produção, nunca
numa cópia.
(acervo: 2026-08-25)

**Entrega analítica escapa por não ter artefato.** Relatório que compara,
levanta achado ou lê documentação não tem comando pra rodar, então as defesas
acima não pegam nele — e ele chega com a mesma cara de confiança. O sinal
barato, antes de virar conclusão: conferir **na fonte** duas citações que o
relatório faz do nosso lado (`arquivo:linha`) e **uma contagem** que ele
declara. Citação que não existe na fonte = ler a fonte, não integrar o
relatório.
(acervo: 2026-08-08)

E "duas citações" é o mínimo, não o teto: quando o relatório traz **N**
citações com âncora (`[HH:MM:SS]`, `arquivo:linha`), a validação é o grep de
**cada uma** contra a fonte, não uma amostra — o item fabricado tende a ser o
único entre muitos corretos, e amostra pequena o deixa passar. Vale também
para nome de arquivo citado no relato: existir de verdade é a primeira
checagem, antes de ler o resto.
(acervo: 2026-08-20, 2026-08-24)

**Recomendação é entrega, e cai junto quando o fato que a sustenta cai.**
Analisando algo, um fato inicial (lido de README, de memória, de suposição)
pode ser corrigido no meio do trabalho — a recomendação construída sobre ele
não segue de pé por inércia: desce e se reavalia no mesmo instante em que o
fato desceu, nunca numa passada posterior que talvez não aconteça.
(acervo: 2026-08-23)

**Saída verde de ferramenta também não é evidência.** Vale para CLI, não só
para agente: depois de publicar, instalar ou atualizar qualquer coisa,
conferir o **artefato que roda** — arquivo no disco, versão no clone que
executa, saída do binário — nunca a mensagem de sucesso.
(acervo: 2026-08-08)

**Isso vale para a própria janela editando configuração, não só para CLI de
terceiro.** Mudança em arquivo de config ou variável de ambiente é entrega como
outra qualquer, com dois lados: antes de escrever, a **semântica** da chave tem
que estar lida na fonte que a consome — achar o nome certo numa tabela não é
ler o que ele faz; depois de escrever, o arquivo salvo é intenção, não entrega
— só conta como feito depois de **reiniciar o processo que lê o arquivo** e
confirmar, na saída real dele, que o valor novo valeu.
(acervo: 2026-08-17, 2026-08-21)

Publicar este plugin exige três coisas, e faltar uma
deixa a mudança **publicada e inerte**: bump em `.claude-plugin/plugin.json`
(o cache instala **por versão**), fast-forward do clone em
`plugins/marketplaces/<nome>`, e conferir a versão viva no cache — a única
**sem** `.orphaned_at`. Não use `.in_use` como sinal: ele é transitório e
some com o plugin descarregado. E a versão nova só aparece no cache **no
próximo carregamento** — publicar não instala.
(acervo: 2026-08-09)

**✅ sem comando e saída colados = não verificado**, e o briefing dita o
formato, não só a exigência. Item marcado como conferido sem trazer, na
mesma linha, o comando e a **saída literal**, é lido como **não feito** e a
janela principal confere ela mesma. Pedir "cole a saída" no fim do briefing
não basta.
(acervo: 2026-08-08)

Então o critério de sucesso vai **numerado**, e cada item pede,
nesta ordem: (1) o **comando literal**, (2) a **saída colada**, (3) só então
o veredito. Um ✅ falso não custa só aquele item: obriga a reconferir o
relatório inteiro na mão, que é o custo que o relatório existia pra eliminar.
**E critério que FALHOU o agente não dispensa** — "não afeta a
funcionalidade" é conclusão da janela principal, nunca dele.

**Recomendação destrutiva de agente não se executa, se investiga.** Agente
que conclui "apague X", "reinstale Y", "limpe a pasta Z" entregou
**hipótese**, não diagnóstico: a janela principal confere a cadeia causal e
leva ao usuário, nunca roda direto. O alarme: **a ação apaga dado e a evidência
é "o arquivo contém a string que eu procurei"**.
(acervo: 2026-08-08)

---

Os incidentes que sustentam os parágrafos acima — o que aconteceu, com data e
custo — moram em `references/regra-12-acervo.md`, indexados pelas datas que cada
parágrafo cita. A regra se aplica sem eles; o acervo se lê quando o "por quê"
for a pergunta.
