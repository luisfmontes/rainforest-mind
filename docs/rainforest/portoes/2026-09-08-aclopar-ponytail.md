# Portões: aclopar-ponytail — invariantes do núcleo

Os portões para a tarefa 2 do plano, que implementa detecção de perda de
frases críticas no núcleo injetado.

- [x] P0: invariantes conferem no repositório íntegro
  CHECK: node scripts/conferir-invariantes.cjs
  ESPERA: ok: conferidas 5 invariantes
  EVIDENCIA: {"shell":"cmd.exe","cwd":".","exit":0,"match":true,"fingerprint":"4f12038f503b"}

- [x] P1: bateria de testes passa
  CHECK: bash scripts/testa-conferir-invariantes.sh
  ESPERA: ok: 3   falhou: 0
  EVIDENCIA: {"shell":"cmd.exe","cwd":".","exit":0,"match":true,"fingerprint":"1c3a457690c4"}
