## Resumo
Hoje o hook de manutenção cria `manutencao-<AAAA-MM-DD>.lock` uma vez por dia na raiz de dados e nunca apaga a trava. Em `~/.rainforest` já são 46. Com esta mudança, a sessão que cria a trava do dia apaga as de dias anteriores (ideia `manutencao-lock-acumula-na-raiz-de-dados`):

```
openSync(trava do dia, 'wx')   ── EEXIST → sai (perdeu a corrida, não poda)
spawn(memoria.cjs manutencao)
podarTravasAntigas(raiz, hoje) ── /^manutencao-(\d{4}-\d{2}-\d{2})\.lock$/ com data < hoje → unlink
exit 0
```

A trava do dia, uma de data futura, o `manutencao.log` e qualquer arquivo com outro nome ficam. Erro ao listar a raiz ou ao apagar um arquivo é engolido, e o hook continua saindo 0. Sobe a versão para 2.8.1 (PATCH).

## Evidência
- **Antes:** a raiz com `manutencao-2026-01-01.lock` passa pelo hook e o arquivo continua lá. A `prova:` do plano sai 1 na base.
  **Depois:** `bash hooks/testa-memoria-manutencao.sh` sai com `ok: 41, falhou: 0`. A seção 11 lista os arquivos depois da abertura: `manutencao-2026-1-1.lock manutencao-2026-11-07.lock manutencao-2999-12-31.lock manutencao-x.lock manutencao.log`. As duas travas de 2026 sumiram, e numa raiz em que a trava de hoje já existia a de 2026-01-02 ficou.
- **Mutação:** trocando `podarTravasAntigas(raiz, hoje);` por `void raiz;`, a bateria fica vermelha nas duas rodadas (`conferir-mutacao.cjs`, exit 1 com o mutante).

## Perigo de merge
**Porta:** mão dupla. A mudança se desfaz com um revert. As travas antigas que o hook apagar não fazem falta: só a do dia é consultada, e nenhum outro script lê as outras.
**Raio de impacto:** pequeno. Só a abertura da sessão que dispara a manutenção é afetada.

## Deixado para depois
- revisar: [baixa] salto de relogio para frente apaga travas reais e gera uma manutencao extra → descartada: design aceita relogio fora de ordem; efeito e uma passada de manutencao a mais no dia, sem perda de dado

🤖 Generated with [Claude Code](https://claude.com/claude-code)
