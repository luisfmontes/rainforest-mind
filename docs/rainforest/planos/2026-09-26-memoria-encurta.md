# Plano: Memória da abertura encurta antes de cortar

Design: docs/rainforest/design/2026-09-26-memoria-encurta.md

## O que não pode quebrar
- Bloco que cabe inteiro sai byte a byte igual ao de hoje, sem aviso.
- O aviso de pipeline (captura parada) continua no topo e nunca é ele que sai.
- O bloco nunca passa de 3.000 B, com aviso e tudo.
- A legenda (`montarLegendaMemoria`) não muda.
- Nenhuma bateria escreve no `~/.rainforest` real; a medição no banco real é só leitura.

## Tarefas

### 1. Escada de encaixe no bloco de memória [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `hooks/lib/memoria-sessao.cjs`, `hooks/testa-memoria-escada.cjs`, `hooks/testa-memoria-escada.sh`, `hooks/testa-memoria-session-start.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/memoria-sessao.cjs`
  de: `const DEGRAUS_TEXTO = [200, 160, 120];`
  para: `const DEGRAUS_TEXTO = [];`
  bateria: `node hooks/testa-memoria-escada.cjs`
  fixture: `testa-memoria-escada.cjs, caso "14 observações com títulos longos cabem todas com textos encurtados"`
pronto quando: com 14 observações no formato real do banco (`conteudo` com título longo na primeira linha e subtítulo longo na seguinte, como as de 2026-09-26: títulos de 250 a 435 caracteres, subtítulo de mediana 188 B), `montarMemoria` devolve as 14 linhas dentro de 3.000 B, com o texto (título — subtítulo) encurtado na palavra e terminado em `…`, e o aviso no topo diz o degrau ("textos encurtados a 120 caracteres" ou o que tiver cabido); com observações curtas que cabem inteiras, a saída é idêntica à de hoje e sem aviso; com observações que não cabem nem em 120, corta as mais antigas e o aviso diz o degrau e quantas saíram; com aviso de pipeline presente, ele segue no topo; o bloco nunca passa de 3.000 B — provado por `node hooks/testa-memoria-escada.cjs` nesses casos, e pela medição no banco real (só leitura, janelas de 14 sobre as 60 mais recentes) subindo a média de observações que entram de 6,3 para pelo menos 12.

### 2. Versão 1.23.15 [tipo: configurar]
atende: D1
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: bump de versão, sem comportamento a inverter.
pronto quando: `node scripts/conferir-versao.cjs` aceita (maior que a `origin/main`, hoje `1.23.14`) e `bash scripts/testa-versao.sh` confirma `plugin.json` e selo do README iguais.
