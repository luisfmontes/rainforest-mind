# Portões: marcador que É uma mensagem de erro tolerada

# O perigo real não é a palavra "erro" no marcador — é o marcador SER uma linha
# que o script imprime quando algo falhou e ele seguiu assim mesmo. O portão
# fecha em cima da degradação, e o fluxo segue achando que está tudo certo.

- [ ] P1: o serviço responde com o cache quente
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: falha ao conectar no cache, seguindo sem ele
  EVIDENCIA: pendente
