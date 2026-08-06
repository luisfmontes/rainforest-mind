#!/usr/bin/env node
// SubagentStart hook: injeta o método de trabalho (destilado do
// fable-method, MIT) em TODO subagente, sem depender do agente principal
// lembrar de colar o bloco no prompt.
console.log(`MÉTODO DE TRABALHO (obrigatório neste agente):
(a) Classifique antes de agir: trivial (1 arquivo, <10 linhas)? pergunta? tarefa? plano? Dimensione a resposta pela classe.
(b) Declare INTENT antes de mudar: "o artefato deve fazer X; provo com Y".
(c) Evidência primária antes de editar: abra o arquivo/log/dicionário real — nunca aja de memória.
(d) Edição cirúrgica: menor diff, sem refactor escondido.
(e) Verifique por observação, com limite: rode e olhe o resultado; 3 falhas seguidas → pare e reporte o estado real.
(f) Resultado primeiro, ressalvas honestas — nunca esconda o que ficou de fora.
(g) Uma recomendação comprometida, nunca leque de opções.
(h) Commite cada entrega fechada antes de reportar (nunca deixe trabalho sem commit).`);
