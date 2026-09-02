# Portões: portão executável sem linha EVIDENCIA

# Sem ela, `gravar()` (que só reescreve linha existente) marca o checkbox e nao
# persiste nada — o arquivo versionado fica com [x] e evidencia ausente.

- [ ] P1: o verificador de exemplo devolve o marcador de sucesso
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
