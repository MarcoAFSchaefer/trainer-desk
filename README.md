# Trainer Desk

Layout em estilo IDE para o Gen1Recomp: o jogo fica no centro e painéis de outros mods ficam em docas à esquerda, à direita e embaixo, com abas, divisórias arrastáveis e janelas próprias.

Feito para Pokémon FireRed/LeafGreen no Gen1Recomp (API de mods 3).

## O que faz

- Docas com abas; arraste uma aba para mudar de lugar e as divisórias para redimensionar.
- Abas que não cabem vão para um menu no fim da barra.
- Cada painel pode sair para uma janela própria do Windows e voltar.
- **F10** esconde e mostra todas as docas (tecla configurável nas opções do mod).
- A roda do mouse sobre um painel vai para o painel; sobre o jogo continua sendo o zoom do jogo.
- Menu no canto do jogo: mostrar/fechar painéis, tema e restaurar o layout.
- Encaixa como painel a imagem que outro mod manda para a segunda tela (por exemplo, o Kanto Gear).

## Instalação

Copie a pasta `trainer_desk` para a pasta de mods do jogo:

```
%APPDATA%\pokemon-love2d\mods\trainer_desk
```

## Para outros mods

`mod.find("trainer_desk").exports.dock` (com `api == 1`) oferece `register{ id, title, width, height, draw | image, pointer, interval, pixel, side, first, responsive }`, `unregister`, `panels`, `show`, `theme`, `registerTheme`, `setTheme`, `active`, `collapsed`, `hotkey`.

Com `responsive = true`, `draw(now, largura, altura)` recebe o espaço real que o painel tem na doca. `pointer(ação, x, y, quantidade)` recebe `"down"`, `"move"`, `"up"`, `"cancel"` e `"wheel"`.

## Testes

Os testes rodam no Linux com LÖVE 11.5 e um X virtual, junto com o Trainer Lens:

```
DOCK_MOD=$PWD/trainer_desk PP_MOD=/caminho/trainer-lens/trainer_lens \
  xvfb-run -a love tests
```

O resultado esperado é `ALL DOCK CHECKS PASSED`. As imagens geradas vão para `TEST_OUT` (padrão `/tmp/kg_out`).

## Histórico

Até a versão 0.4.1 se chamava PokeDock (id `poke_dock`).
