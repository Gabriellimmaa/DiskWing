# DiskWing — modelos de logo

Quatro direções iniciais para o aplicativo macOS open source de armazenamento e cache. A marca é escrita **DiskWing** em texto corrido; o desenho do nome usa **diskwing** em minúsculas.

## Conteúdo

- `overview.png` e `overview-dark.png`: comparação dos quatro modelos.
- `size-check.png`: inspeção dos símbolos em tamanho real.
- `gallery.html`: galeria local com fundos claro/escuro e links para os SVGs.
- `concepts/`: quatro conceitos; cada um contém versões horizontal, vertical, símbolo e ícone de aplicativo.
- `wordmark/`: logotipo tipográfico independente.
- `source/`: construção vetorial, fonte Manrope e licença OFL.

## Conceitos

### Lift — Disco com asa

O núcleo circular representa o armazenamento; três penas apontam para cima e para fora. O centro vazado mantém a referência a disco e dá respiro ao símbolo.

Cor principal: `#2764E7`. Cor secundária: `#5D94FF`.

### Fold — Monograma D

Uma construção compacta em uma única forma. A letra D se reconhece pela haste e pela curva externa; os vazios diagonais sugerem penas e movimento. É o conceito mais contido.

Cor principal: `#087D6C`. Cor secundária: `#20AC92`.

### Orbit — Espaço em movimento

O anel sugere a ocupação do disco. Um segmento se desprende e ganha uma ponta de asa: uma metáfora para espaço recuperado. O círculo permanece forte nas versões pequenas.

Cor principal: `#C86315`. Cor secundária: `#EFA04E`.

### Soar — Asa dobrada

Uma direção abstrata, sem desenhar um dispositivo. O plano maior sugere uma asa aberta; a dobra e a cauda dão uma assinatura própria à silhueta. O nome completa a referência a armazenamento.

Cor principal: `#BA4A40`. Cor secundária: `#E57D6C`.

## Versões e fundos

- `color.svg`: símbolo colorido; nome em azul-escuro. Para fundos claros.
- `dark.svg`: marca inteira em azul-escuro. Para reprodução em uma cor.
- `light.svg`: marca inteira branca, com fundo transparente. Para fundos escuros.
- Em `app-icon/`, as três versões têm uma base arredondada e margem transparente de 96 px em uma tela de 1024 px. São estudos de aplicação como ícone.

## Uso

- SVGs são vetoriais editáveis, com texto convertido em caminhos: não exigem instalação de fontes.
- A fonte Manrope é fornecida em `source/`, sob a licença SIL Open Font License incluída no pacote.
- Preserve ao menos 25% da largura do símbolo como área livre externa.
- Use o símbolo isolado em tamanhos pequenos. Para o conjunto horizontal, comece em 160 px de largura e confira a leitura no contexto.
- A folha `size-check.png` permite comparar as opções antes de decidir qual refiná-las para o ícone final.
- A marca monocromática pode adotar a cor de texto do contexto, desde que mantenha contraste suficiente.
- Evite distorção, contorno adicional, rotação e efeitos que alterem a silhueta.

## Exportação

Os PNGs dos ícones têm 1024 × 1024 px, fundo externo transparente e perfil sRGB. A versão vetorial permanece como fonte principal.
O script `source/build_logos.py` recria os SVGs. Requer Python e fontTools. `source/render.cjs` exporta os SVGs para PNG com sharp.

Os arquivos são estudos de design para seleção e refinamento. Não foi realizada busca de similaridade de marcas gráficas.
