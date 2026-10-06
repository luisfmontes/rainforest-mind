# Critério de trava

**Quando a tarefa entrega gate, hook, validador ou qualquer coisa que barra**, o
`pronto quando:` enumera as duas faces, nas duas direções — testar só o que a trava
barra deixa passar o gate que barra também o trabalho normal (100 casos eram de
escrita e o gate barrava `grep` de leitura):

- **Tentativas de contorno:** as formas pelas quais alguém escaparia dela. Critério
  "N flags dão exit 2" cumpre-se com bateria verde e mutação que reprova, sem provar
  que a trava resiste.
- **Casos legítimos que passam perto e NÃO podem ser barrados:** o trabalho normal
  com a mesma aparência (leitura com o padrão da trava no texto, redirecionamento
  citado dentro de string). Cada um é caso de teste, rodado contra a trava pronta.

**Regra de parada declarada no plano quando a trava reimplementa a gramática de
outra linguagem** (shell, SQL, regex): ali o conjunto de contraexemplos não fecha, e
cada conserto de falso positivo abre o próximo. O plano diz onde para (modelo de
ameaça do design) e o que fica fora; ao estourar, volta para o `brainstorm` em vez
de somar um parser a cada rodada. Diagnóstico de trava que falhou se mede na saída
real, nunca se fabrica.

