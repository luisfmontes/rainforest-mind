# Mutação no lugar (`no-lugar: sim`)

O campo opcional `no-lugar: sim` do bloco `mutacao:` vale para bateria presa a um
processo vivo sobre a árvore real: editor Unity aberto com `unity command run_tests`,
Godot, Unreal. A cópia temporária da catraca não alcança esse processo (#527, #569).

Com o campo, a catraca muta o arquivo real, roda a bateria na própria raiz e
restaura os bytes originais em toda saída. O preço é o risco que a cópia existe para
evitar (#266): durante a bateria, quem ler o arquivo (outra sessão, outro agente) lê
o mutante. Por isso o campo é por tarefa e fica à vista de quem revisa o plano.

O que a catraca recusa (exit 4, nada mutado):
- alvo com mudança não commitada, não rastreado ou ignorado pelo git, porque o git
  precisa poder desfazer;
- `git` que falha dentro de um repositório, ou que não reconhece um `.git` existente;
- arquivo que mudou entre a leitura e a mutação (alguém editou durante o baseline);
- outra execução viva com o mesmo arquivo mutado.

Na restauração, se o arquivo não é mais o mutante nem o original (alguém editou
durante a bateria), a catraca não escreve: deixa o backup no temporário e sai 1.

`cobertura` recusa valor que não seja `sim`.
