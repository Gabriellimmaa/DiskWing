#!/usr/bin/env python3
"""Build the editable SVG concept family and its presentation boards.

Requires fontTools. Wordmarks and presentation text are converted to paths.
"""
from __future__ import annotations

import html
import json
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen

ROOT = Path(__file__).resolve().parents[1]
INK = '#172435'
PAPER = '#F4F3EF'
FONTS = {}


def font_at(weight=650):
    if weight not in FONTS:
        base = TTFont(ROOT / 'source/Manrope.ttf')
        FONTS[weight] = instantiateVariableFont(base, {'wght': weight}, inplace=True)
    return FONTS[weight]


def text_width(text, size=24, weight=650, tracking=0):
    font = font_at(weight)
    cmap = font.getBestCmap()
    units = font['head'].unitsPerEm
    return sum(font['hmtx'][cmap[ord(c)]][0] for c in text) * size / units + max(0, len(text)-1) * tracking


def text_path(text, x, y, size=24, weight=650, fill=INK, tracking=0, anchor='start'):
    font = font_at(weight)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font['head'].unitsPerEm
    if anchor == 'middle':
        x -= text_width(text, size, weight, tracking) / 2
    elif anchor == 'end':
        x -= text_width(text, size, weight, tracking)
    cursor = 0
    paths = []
    for char in text:
        glyph_name = cmap[ord(char)]
        pen = SVGPathPen(glyphs)
        glyphs[glyph_name].draw(pen)
        commands = pen.getCommands()
        if commands:
            paths.append(f'<path transform="translate({cursor:.3f} 0)" d="{commands}"/>')
        cursor += font['hmtx'][glyph_name][0] + tracking / scale
    return f'<g aria-label="{html.escape(text, quote=True)}" fill="{fill}" transform="translate({x:.3f} {y:.3f}) scale({scale:.7f} {-scale:.7f})">' + ''.join(paths) + '</g>'


CONCEPTS = [
    {
        'id': '01-lift', 'name': 'Lift', 'label': 'Disco com asa',
        'color': '#2764E7', 'accent': '#5D94FF', 'tint': '#EDF3FF',
        'description': 'Um disco encontra uma asa em ascensão. Direto e expressivo.',
        'rationale': 'O núcleo circular representa o armazenamento; três penas apontam para cima e para fora. O centro vazado mantém a referência a disco e dá respiro ao símbolo.',
        'parts': [
            ('primary', 'M39 59a27 27 0 1 0 0 54a27 27 0 1 0 0-54Zm0 17a10 10 0 1 1 0 20a10 10 0 1 1 0-20Z', 'evenodd'),
            ('primary', 'M31 68C45 38 76 20 116 16C108 36 95 49 77 57L52 65L43 78Z', None),
            ('accent', 'M58 71L106 52C99 73 84 85 61 91L51 89Z', None),
            ('primary', 'M58 94L90 82C84 100 69 111 46 113L38 103Z', None),
        ],
    },
    {
        'id': '02-fold', 'name': 'Fold', 'label': 'Monograma D',
        'color': '#087D6C', 'accent': '#20AC92', 'tint': '#E9F6F1',
        'description': 'A letra D abriga duas aberturas que desenham uma asa.',
        'rationale': 'Uma construção compacta em uma única forma. A letra D se reconhece pela haste e pela curva externa; os vazios diagonais sugerem penas e movimento. É o conceito mais contido.',
        'parts': [
            ('primary', 'M21 16H58C92 16 112 35 112 64S92 112 58 112H21Q17 112 17 108V20Q17 16 21 16ZM43 41V78L80 41ZM45 94H57C79 94 91 82 88 56Z', 'evenodd'),
        ],
    },
    {
        'id': '03-orbit', 'name': 'Orbit', 'label': 'Espaço em movimento',
        'color': '#C86315', 'accent': '#EFA04E', 'tint': '#FFF2E3',
        'description': 'Um disco aberto e um segmento que se transforma em voo.',
        'rationale': 'O anel sugere a ocupação do disco. Um segmento se desprende e ganha uma ponta de asa: uma metáfora para espaço recuperado. O círculo permanece forte nas versões pequenas.',
        'parts': [
            ('primary', 'M62 17A47 47 0 1 0 109 64H85A23 23 0 1 1 62 41Z', None),
            ('accent', 'M75 17L120 9L111 54L96 35Z', None),
        ],
    },
    {
        'id': '04-soar', 'name': 'Soar', 'label': 'Asa dobrada',
        'color': '#BA4A40', 'accent': '#E57D6C', 'tint': '#FFF0EB',
        'description': 'Uma asa de papel, formada por três planos geométricos.',
        'rationale': 'Uma direção abstrata, sem desenhar um dispositivo. O plano maior sugere uma asa aberta; a dobra e a cauda dão uma assinatura própria à silhueta. O nome completa a referência a armazenamento.',
        'parts': [
            ('primary', 'M17 77L73 15L69 65L116 40L85 89L54 110Z', None),
            ('accent', 'M17 77L69 65L54 110Z', None),
            ('primary', 'M69 65L116 40L85 89Z', None),
        ],
    },
]


def symbol(c, variant='color', x=0, y=0, scale=1):
    color = c['color'] if variant == 'color' else (INK if variant == 'dark' else '#FFFFFF')
    accent = c['accent'] if variant == 'color' else color
    result = []
    for role, path, fillrule in c['parts']:
        fill = color if role == 'primary' else accent
        rule = f' fill-rule="{fillrule}"' if fillrule else ''
        result.append(f'<path fill="{fill}"{rule} d="{path}"/>')
    return f'<g transform="translate({x} {y}) scale({scale})">' + ''.join(result) + '</g>'


def document(width, height, title, body, description='', extra_defs=''):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
            f'role="img" aria-labelledby="title desc"><title id="title">{html.escape(title)}</title>'
            f'<desc id="desc">{html.escape(description)}</desc>'
            + (f'<defs>{extra_defs}</defs>' if extra_defs else '') + body + '</svg>\n')


def save(path, content):
    dest = ROOT / path
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding='utf-8')


def app_body(c, variant='color', prefix='app'):
    if variant == 'color':
        back = c['color']
        mark = 'light'
        border = '#FFFFFF'
    elif variant == 'dark':
        back = INK
        mark = 'light'
        border = '#FFFFFF'
    else:
        back = '#F4F3EF'
        mark = 'dark'
        border = INK
    return (f'<rect x="96" y="96" width="832" height="832" rx="186" fill="{back}"/>'
            f'<rect x="100" y="100" width="824" height="824" rx="182" fill="none" stroke="{border}" stroke-opacity=".13" stroke-width="2"/>'
            + symbol(c, mark, 192, 192, 5))


def generate_assets():
    for c in CONCEPTS:
        for variant in ['color', 'dark', 'light']:
            title = f'DiskWing · {c["name"]} · {variant}'
            desc = c['rationale']
            text_color = '#FFFFFF' if variant == 'light' else INK
            root = f'concepts/{c["id"]}'
            save(f'{root}/icon/{variant}.svg', document(128,128,title,symbol(c,variant),desc))
            body = symbol(c,variant,16,16) + text_path('diskwing',168,106,78,650,text_color,tracking=-1.3)
            width = round(184 + text_width('diskwing',78,650,-1.3))
            save(f'{root}/horizontal/{variant}.svg',document(width,160,title,body,desc))
            body = symbol(c,variant,136,32) + text_path('diskwing',200,261,66,650,text_color,tracking=-1.1,anchor='middle')
            save(f'{root}/vertical/{variant}.svg',document(400,328,title,body,desc))
            save(f'{root}/app-icon/{variant}.svg',document(1024,1024,title,app_body(c,variant),desc))
    for variant,fill in [('dark',INK),('light','#FFFFFF')]:
        width = round(text_width('diskwing',78,650,-1.3)+32)
        save(f'wordmark/{variant}.svg',document(width,112,'DiskWing · wordmark',text_path('diskwing',16,82,78,650,fill,-1.3)))


def scaled_group(content,x,y,scale):
    return f'<g transform="translate({x} {y}) scale({scale})">{content}</g>'


def board(dark=False):
    W,H=1800,1536
    bg='#0E1724' if dark else PAPER
    panel='#182435' if dark else '#FFFFFF'
    ink='#F7F8FB' if dark else INK
    sub='#AEBBCD' if dark else '#647286'
    rule='#2C3C51' if dark else '#E9EBED'
    body=f'<rect width="{W}" height="{H}" fill="{bg}"/>'
    body+=text_path('DISKWING  /  IDENTIDADE VISUAL',64,67,18,650,sub,tracking=1.6)
    body+=text_path('Quatro formas de voar.',64,154,66,650,ink,tracking=-1.9)
    body+=text_path('Conceitos para um aplicativo open source de armazenamento no macOS.',67,207,23,450,sub)
    body+=text_path('01—04',1736,68,20,650,sub,anchor='end')
    for i,c in enumerate(CONCEPTS):
        x=64+(i%2)*852;y=264+(i//2)*586
        body+=f'<rect x="{x}" y="{y}" width="820" height="554" rx="24" fill="{panel}"/>'
        body+=text_path(f'0{i+1}   {c["name"]}',x+32,y+48,24,700,ink)
        body+=text_path(c['label'],x+788,y+47,17,500,sub,anchor='end')
        body+=text_path(c['description'],x+32,y+87,17,450,sub)
        body+=symbol(c,'color',x+48,y+123,1.16)
        body+=text_path('diskwing',x+224,y+232,82,650,ink,tracking=-1.4)
        body+=f'<path d="M{x+32} {y+296}H{x+788}" stroke="{rule}"/>'
        body+=text_path('ÍCONE DO APP',x+32,y+330,12,650,sub,tracking=1.2)
        body+=scaled_group(app_body(c),x+14,y+340,.16)
        body+=text_path('SÍMBOLO REDUZIDO',x+212,y+330,12,650,sub,tracking=1.2)
        for size,xx in [(16,0),(24,50),(32,108),(48,176)]:
            body+=symbol(c,'light' if dark else 'dark',x+214+xx,y+401-size/2,size/128)
            body+=text_path(str(size),x+214+xx+size/2,y+454,13,500,sub,anchor='middle')
        body+=f'<rect x="{x+500}" y="{y+320}" width="288" height="200" rx="16" fill="{INK if not dark else PAPER}"/>'
        body+=symbol(c,'light' if not dark else 'dark',x+594,y+353,.78)
        body+=text_path('MONOCROMÁTICO',x+644,y+497,11,650,'#CCD5E1' if not dark else '#647286',tracking=1,anchor='middle')
        body+=f'<circle cx="{x+44}" cy="{y+514}" r="5" fill="{c["color"]}"/>'
        body+=text_path(c['color'],x+59,y+519,12,600,sub)
    body+=text_path('diskwing.tech',64,1500,17,650,sub)
    body+=text_path('ESTUDOS DE MARCA  ·  NOVEMBRO 2026',1736,1500,13,500,sub,tracking=.8,anchor='end')
    return document(W,H,'DiskWing · quatro conceitos de logo',body,'Comparação de quatro marcas vetoriais: Lift, Fold, Orbit e Soar.')


def size_board():
    W,H=1600,960
    body=f'<rect width="{W}" height="{H}" fill="{PAPER}"/>'
    body+=text_path('DiskWing / legibilidade',64,83,42,650,INK,tracking=-1.3)
    body+=text_path('Símbolos em 16, 24, 32, 48, 64 e 128 pixels — apresentados em tamanho real.',64,126,20,450,'#647286')
    for i,c in enumerate(CONCEPTS):
        y=178+i*175
        body+=f'<rect x="64" y="{y}" width="1472" height="151" rx="18" fill="#FFF"/>'
        body+=text_path(f'0{i+1}  {c["name"]}',88,y+83,22,650)
        for size,x in [(16,330),(24,420),(32,525),(48,650),(64,800),(128,1000)]:
            body+=symbol(c,'dark',x,y+75-size/2,size/128)
            body+=text_path(f'{size}px',x+size/2,y+136,12,500,'#647286',anchor='middle')
        body+=scaled_group(app_body(c),1280,y+3,.14)
    return document(W,H,'DiskWing · teste de redução',body)


def guide():
    lines=['# DiskWing — modelos de logo','',
           'Quatro direções iniciais para o aplicativo macOS open source de armazenamento e cache. A marca é escrita **DiskWing** em texto corrido; o desenho do nome usa **diskwing** em minúsculas.', '',
           '## Conteúdo','',
           '- `overview.png` e `overview-dark.png`: comparação dos quatro modelos.',
           '- `size-check.png`: inspeção dos símbolos em tamanho real.',
           '- `gallery.html`: galeria local com fundos claro/escuro e links para os SVGs.',
           '- `concepts/`: quatro conceitos; cada um contém versões horizontal, vertical, símbolo e ícone de aplicativo.',
           '- `wordmark/`: logotipo tipográfico independente.',
           '- `source/`: construção vetorial, fonte Manrope e licença OFL.', '',
           '## Conceitos','']
    for c in CONCEPTS:
        lines += [f'### {c["name"]} — {c["label"]}','',c['rationale'],'',f'Cor principal: `{c["color"]}`. Cor secundária: `{c["accent"]}`.','']
    lines += ['## Versões e fundos','',
              '- `color.svg`: símbolo colorido; nome em azul-escuro. Para fundos claros.',
              '- `dark.svg`: marca inteira em azul-escuro. Para reprodução em uma cor.',
              '- `light.svg`: marca inteira branca, com fundo transparente. Para fundos escuros.',
              '- Em `app-icon/`, as três versões têm uma base arredondada e margem transparente de 96 px em uma tela de 1024 px. São estudos de aplicação como ícone.', '',
              '## Uso','',
              '- SVGs são vetoriais editáveis, com texto convertido em caminhos: não exigem instalação de fontes.',
              '- A fonte Manrope é fornecida em `source/`, sob a licença SIL Open Font License incluída no pacote.',
              '- Preserve ao menos 25% da largura do símbolo como área livre externa.',
              '- Use o símbolo isolado em tamanhos pequenos. Para o conjunto horizontal, comece em 160 px de largura e confira a leitura no contexto.',
              '- A folha `size-check.png` permite comparar as opções antes de decidir qual refiná-las para o ícone final.',
              '- A marca monocromática pode adotar a cor de texto do contexto, desde que mantenha contraste suficiente.',
              '- Evite distorção, contorno adicional, rotação e efeitos que alterem a silhueta.', '',
              '## Exportação','',
              'Os PNGs dos ícones têm 1024 × 1024 px, fundo externo transparente e perfil sRGB. A versão vetorial permanece como fonte principal.',
              'O script `source/build_logos.py` recria os SVGs. Requer Python e fontTools. `source/render.cjs` exporta os SVGs para PNG com sharp.', '',
              'Os arquivos são estudos de design para seleção e refinamento. Não foi realizada busca de similaridade de marcas gráficas.', '']
    save('README.md','\n'.join(lines))


def gallery():
    cards=[]
    for i,c in enumerate(CONCEPTS):
        root=f'concepts/{c["id"]}'
        cards.append(f'''<article><header><h2>0{i+1} · {c['name']}</h2><span>{c['label']}</span></header>
        <div class="hero"><img class="brand" src="{root}/horizontal/color.svg" alt="Logo DiskWing: {c['name']}"></div>
        <p>{c['rationale']}</p><div class="samples"><img class="app" src="{root}/app-icon/color.png" alt="Ícone de aplicativo"><div class="inverse"><img src="{root}/horizontal/light.svg" alt="Versão branca"></div></div>
        <footer><a href="{root}/horizontal/color.svg" download>Logo SVG</a><a href="{root}/icon/color.svg" download>Símbolo SVG</a><a href="{root}/app-icon/color.png" download>Ícone PNG</a><a href="{root}/vertical/color.svg" download>Versão vertical</a></footer></article>''')
    save('gallery.html','''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DiskWing — modelos de logo</title><style>
    *{box-sizing:border-box}body{margin:0;background:#f4f3ef;color:#172435;font:16px -apple-system,BlinkMacSystemFont,Arial,sans-serif;padding:48px;max-width:1500px;margin:auto}h1{font-size:clamp(36px,5vw,64px);letter-spacing:-2px;margin:18px 0}body>p{color:#647286;margin-bottom:40px}.toolbar{display:flex;justify-content:space-between;gap:20px;align-items:center}button{padding:12px 18px;border:1px solid #ccd4df;border-radius:30px;background:transparent;color:inherit;cursor:pointer}main{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:white;border-radius:24px;padding:28px}article header{display:flex;align-items:center;justify-content:space-between;gap:20px}h2{font-size:23px;margin:0}header span{color:#647286;font-size:14px}.hero{display:flex;align-items:center;justify-content:center;min-height:210px}.brand{width:90%;max-height:150px}article p{color:#647286;line-height:1.6;min-height:104px}.samples{display:flex;gap:24px;align-items:center}.app{width:160px}.inverse{background:#172435;border-radius:16px;padding:28px;flex:1}.inverse img{width:100%;display:block}footer{display:flex;gap:12px;flex-wrap:wrap;margin-top:24px}a{color:#2764e7;text-decoration:none;border-bottom:1px solid #cadbff;padding-bottom:4px;font-size:14px}body.dark{background:#0e1724;color:#f7f8fb}.dark article{background:#182435}.dark article p,.dark header span{color:#aebbcd}.dark a{color:#9dbbff}@media(max-width:850px){body{padding:24px}main{grid-template-columns:1fr}.samples{gap:12px}.app{width:110px}article p{min-height:0}article header{align-items:flex-start;flex-direction:column;gap:8px}}
    </style><div class="toolbar"><span>DISKWING / ESTUDOS DE IDENTIDADE</span><button id="theme">Alternar fundo</button></div><h1>Quatro formas de voar.</h1><p>Modelos vetoriais para o aplicativo open source de armazenamento no macOS.</p><main>'''+''.join(cards)+r'''</main><p>Tipografia Manrope · SVGs com texto em caminhos · diskwing.tech</p><script>
    document.getElementById('theme').onclick=()=>{const dark=document.body.classList.toggle('dark');document.querySelectorAll('.brand').forEach(i=>i.src=i.src.replace(/\/(color|light)\.svg$/,dark?'/light.svg':'/color.svg'));};</script></html>''')


if __name__ == '__main__':
    generate_assets()
    save('overview.svg',board())
    save('overview-dark.svg',board(True))
    save('size-check.svg',size_board())
    guide()
    gallery()
    save('source/concepts.json',json.dumps([{k:v for k,v in c.items() if k!='parts'} for c in CONCEPTS],ensure_ascii=False,indent=2)+'\n')
    print(f'Generated {len(list(ROOT.rglob("*.svg")))} SVGs in {ROOT}')
