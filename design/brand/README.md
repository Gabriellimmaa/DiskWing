# DiskWing — identidade final Lift

> Registro original da marca aprovada. A integração no aplicativo e as verificações da consolidação estão em ../../docs/context/MIGRATION-2026-11-09.md.

Arquivos finais do modelo **Lift**, selecionado em 9 de novembro de 2026. A forma do símbolo, a tipografia e as cores do modelo aprovado foram preservadas.

## Arquivos principais

| Uso | Arquivo / pasta |
| --- | --- |
| Logo principal | `logo/svg/diskwing-horizontal-color.svg` |
| Logo para fundo escuro | `logo/svg/diskwing-horizontal-color-reverse.svg` |
| Versão vertical | `logo/svg/diskwing-vertical-color.svg` |
| Símbolo isolado | `logo/svg/diskwing-symbol-color.svg` |
| Reprodução em uma cor | Versões `mono-dark` e `mono-white` |
| PNGs transparentes do logo | `logo/png/` |
| Ícone do aplicativo para macOS | `macos/DiskWing.icns` |
| Ícone em PNG de 1024 × 1024 px | `macos/diskwing-app-icon-1024.png` |
| Fonte vetorial do ícone | `macos/diskwing-app-icon.svg` |
| Ícone em todas as resoluções | `macos/DiskWing.iconset/` |
| Catálogo do Xcode | `macos/DiskWing.xcassets/` |
| Símbolo para barra de menus | `DiskWingMenuBarTemplate.imageset`, dentro do catálogo |
| Camada vetorial para Icon Composer | `macos/icon-composer-source/01-lift-mark.svg` |
| Prancha final | `preview.png` |
| Ícones em tamanho real | `icon-size-check.png` |

## Uso no Xcode

1. Arraste `macos/DiskWing.xcassets` para o projeto, ou copie `AppIcon.appiconset` para o catálogo existente.
2. Em **Target → General → App Icons**, selecione **AppIcon**. Evite manter dois conjuntos com esse mesmo nome no target.
3. O catálogo contém os dez espaços para macOS: 16, 32, 128, 256 e 512 pontos, cada um em 1x e 2x. O maior PNG tem 1024 × 1024 px.
4. Para a barra de menus, use `DiskWingMenuBarTemplate`. A imagem mede 18 pt, com recursos de 18 e 36 px, e está marcada como template para o macOS adaptar sua cor. O símbolo não leva o fundo azul do ícone do aplicativo.
5. `DiskWingMark` é o símbolo colorido para uso dentro do aplicativo.

O `.icns` pode ser utilizado por ferramentas que aceitam esse formato diretamente. Ele foi criado a partir de `DiskWing.iconset`, com `iconutil`, e contém as representações padrão e Retina. O catálogo e o `.icns` representam o mesmo ícone aprovado.

## Icon Composer

A camada `macos/icon-composer-source/01-lift-mark.svg` tem tela de 1024 × 1024 px, símbolo branco, fundo transparente e nenhum recorte de cantos. Ela foi ajustada para manter a mesma proporção visual do ícone plano ao ser aplicada à composição da Apple.

Para criar o documento no Icon Composer:

1. Crie uma composição de 1024 × 1024 px para Mac.
2. Configure o fundo como sRGB `#2764E7`.
3. Importe `01-lift-mark.svg` e preserve a posição e a escala originais. O PNG equivalente também está incluído.
4. Deixe o recorte dos cantos a cargo do aplicativo/sistema.
5. Salve o documento como `DiskWing.icon` e adicione-o ao projeto se optar por esse fluxo.

**Não há um documento nativo `.icon` neste pacote.** Ao abrir o Icon Composer nesta máquina, a Apple solicitou o aceite inicial de licença; esse aceite ficou reservado ao usuário. `composition.json` é uma especificação legível da composição, não um substituto para o formato nativo.

Os arquivos `.icns` e `.appiconset` estão completos e podem ser usados independentemente dessa etapa.

## Marca

- Nome em texto corrido: **DiskWing**.
- Desenho tipográfico: **diskwing**, em minúsculas.
- Azul principal: `#2764E7`.
- Azul de destaque: `#5D94FF`.
- Cor escura: `#172435`.
- Branco: `#FFFFFF`.
- Tipografia: **Manrope**, peso 650, com espaçamento ajustado.

Os SVGs do logo contêm letras convertidas em caminhos; a fonte não precisa estar instalada para exibi-los. A fonte e a licença SIL Open Font License estão em `source/` para futuras edições.

Mantenha uma área livre mínima equivalente a 25% da largura do símbolo. Preserve proporções e orientação. Use o símbolo isolado quando o nome perder legibilidade. Evite sombras e contornos adicionais no logo; a aplicação do ícone macOS já inclui sua base.

As versões `color` usam nome escuro, apropriado para fundos claros. `color-reverse` mantém o símbolo azul e usa o nome branco. `mono-dark` e `mono-white` oferecem a marca inteira em uma cor. Os PNGs do logo têm fundo transparente e perfil sRGB.

## Fontes editáveis e reconstrução

`source/masters/` contém apenas o modelo Lift aprovado. `source/build-assets.cjs` recria os SVGs derivados, PNGs, catálogo de recursos e pranchas, usando Node.js e a biblioteca `sharp`. Para reconstruir o `.icns`, use:

```sh
iconutil -c icns macos/DiskWing.iconset -o macos/DiskWing.icns
```

O relatório `validation.json` registra a inspeção dos SVGs, dimensões dos PNGs, retorno do `.icns` para um iconset e compilação do catálogo com as ferramentas do Xcode. Esses testes validam os recursos; não substituem a integração no aplicativo.

## Referências de formato

- [Apple — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Apple — Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Apple — Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Apple — High Resolution Guidelines, formatos iconset e iconutil](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html)
