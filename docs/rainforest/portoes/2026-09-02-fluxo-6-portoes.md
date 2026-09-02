# Portões: fluxo 6 — portoes.cjs

Os portões DESTE fluxo, verificados pelo próprio `portoes.cjs`. É de propósito:
um mecanismo de oráculo que não se submete ao próprio oráculo é exatamente o
tipo de trava que fica inerte sem ninguém notar — foi o que aconteceu com a
checagem `cobertura`, que a tarefa 6 deste fluxo destravou depois de ela passar
o fluxo 9 inteiro sem rodar uma vez.

- [x] P0: os portões deste fluxo têm oráculos honestos
  CHECK: node scripts/portoes.cjs lint docs/rainforest/portoes/2026-09-02-fluxo-6-portoes.md
  ESPERA: LINT OK
  EVIDENCIA: {"shell":"cmd.exe","cwd":"C:\\Projetos\\rainforest-mind","exit":0,"match":true,"fingerprint":"a443e1ef4b47"}

- [x] P1: o parser aceita o formato e o `status` não executa CHECK nenhum
  CHECK: bash scripts/testa-portoes-parser.sh
  ESPERA: 16 ok, 0 falha(s)
  EVIDENCIA: {"shell":"cmd.exe","cwd":"C:\\Projetos\\rainforest-mind","exit":0,"match":true,"fingerprint":"a29bf0c636c4"}

- [x] P2: o lint reprova oráculo desonesto e separa erro de aviso
  CHECK: bash scripts/testa-portoes-lint.sh
  ESPERA: 17 ok, 0 falha(s)
  EVIDENCIA: {"shell":"cmd.exe","cwd":"C:\\Projetos\\rainforest-mind","exit":0,"match":true,"fingerprint":"d1f9abf9432a"}

- [x] P3: cumprido exige exit 0 E match, e abandono nunca fecha o fluxo
  CHECK: bash scripts/testa-portoes-rodar.sh
  ESPERA: 22 ok, 0 falha(s)
  EVIDENCIA: {"shell":"cmd.exe","cwd":"C:\\Projetos\\rainforest-mind","exit":0,"match":true,"fingerprint":"991926a502c8"}

- [x] P4: os dois ganchos agem, e a cobertura deixou de ser inerte
  CHECK: bash scripts/testa-portoes-gate.sh
  ESPERA: 11 ok, 0 falha(s)
  EVIDENCIA: {"shell":"cmd.exe","cwd":"C:\\Projetos\\rainforest-mind","exit":0,"match":true,"fingerprint":"364e383aac2b"}

- [x] P5: o pipeline existente não regrediu
  CHECK: bash scripts/testa-estado.sh
  ESPERA: 137 ok, 0 falhas
  EVIDENCIA: {"shell":"cmd.exe","cwd":"C:\\Projetos\\rainforest-mind","exit":0,"match":true,"fingerprint":"00d7695263f7"}
