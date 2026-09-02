# Portões: fixture de abandono

- [ ] P1: o verificador de exemplo devolve o marcador de sucesso
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente

- [ ] P2: a migração roda contra o banco de produção
  CHECK: node test/fixtures/portoes/scripts/sempre-ok.cjs
  ESPERA: VERIFICACAO PASSOU
  EVIDENCIA: pendente

ABANDONA: P2 nao ha banco de producao neste ambiente; precisa de decisao humana sobre encenar um ou tirar o portao
