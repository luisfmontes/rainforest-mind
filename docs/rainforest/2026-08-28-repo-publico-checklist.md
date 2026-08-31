# Ir a público — avaliação do README e checklist

Avaliação de 2026-08-28, contra o README completo (54 KB, 27 seções) e uma
varredura do repositório.

## Veredito do README

A voz é o maior ativo: tese na primeira linha, honestidade rara (a seção
"Codex e Gemini: o que atravessa, e o que não" vende mais que qualquer
promessa), números em vez de adjetivos. **O problema não é qualidade, é
forma: ele é um manual excelente usado como vitrine.** Visitante de GitHub
decide em 30 segundos, e hoje os 30 segundos dele acabam antes da linha 507 —
onde está a instalação.

## Checklist (em ordem de impacto)

1. **Instalação sobe para logo depois do pitch.** Três linhas de quickstart
   antes da filosofia. Quem quer entender a floresta continua rolando; quem
   quer plantar, planta. Requisitos (Claude Code mínimo, Node, SO) na mesma
   seção — hoje o leitor descobre o PowerShell dos vigias tarde demais.

2. **Uma demo em movimento vale as 27 seções: grave o momento da trava.**
   GIF/asciinema curto (15 s) do `marcar --status ok` sem evidência sendo
   **recusado** com exit 2, e depois passando com a saída colada. Nenhum
   concorrente mostra o próprio plugin dizendo "não" — é a tese do repo em
   vídeo. (O fluxo 1 do pacote entrega exatamente essa cena.)

3. **Caminhos pessoais no texto.** A varredura achou `/Users/Luis/...` e
   `C:\Users\Luis\.rainforest` em docs — nada grave (sem segredo, sem e-mail
   pessoal, LICENSE presente), mas troque por `<user>` antes do público.
   Sweep: `grep -rn "Users.Luis" --include="*.md" .`

4. **Partir o manual.** README fica com: pitch, banner, demo, quickstart,
   o fluxo em uma tela, as travas em uma tabela, e links. As 17 regras,
   orçamento de token, ajuste fino, FOCO por dentro → `docs/` (os arquivos
   já são bons; é mudança de endereço, não reescrita).

5. **Badge de versão hoje é manual (0.78 chumbado).** Ou workflow que
   atualiza no release, ou remover — badge desatualizada é pior que nenhuma.

6. **Decisão de língua, tomada de propósito.** PT-BR é identidade e
   diferencial na comunidade BR — recomendo manter, com um parágrafo curto
   em inglês no topo dizendo o que é e que o projeto é intencionalmente em
   português. Meio-termo (metade traduzido) é o único erro real aqui.

7. **`CONTRIBUTING.md` mínimo.** A seção "Mexer no plugin" já é o embrião:
   mover, e declarar o que o público precisa saber — PRs passam pelo fluxo
   de 7 estágios? Bateria verde é obrigatória? A revisão bimestral aceita
   pauta de fora?

8. **Banner novo** (`assets/banner.svg` no pacote): a tagline virou cena —
   feixe de luz numa árvore só, as abas-folha apagadas na sombra e a
   "FOCO agora" acesa no feixe, com o pipeline de sete estágios como
   vagalumes no rodapé, `executar` aceso. Autocontido (fontes de sistema,
   zero dependência externa), renderiza igual no GitHub claro e escuro.

## O que já está pronto para o público (não mexer)

LICENSE presente; nenhum segredo ou e-mail pessoal na varredura; o histórico
real em `docs/rainforest/` (designs, planos, estados, relatórios) é ativo, não
passivo — o repo comendo a própria ração é a melhor prova social que ele tem.
