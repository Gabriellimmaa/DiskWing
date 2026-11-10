const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const packaged = path.basename(__dirname) === 'source' && fs.existsSync(path.join(__dirname, 'masters'));
const workspace = packaged ? path.dirname(path.dirname(__dirname)) : __dirname;
const source = packaged ? path.join(__dirname, 'masters') : path.join(workspace, 'diskwing-logo-concepts');
const root = packaged ? path.dirname(__dirname) : path.join(workspace, 'diskwing-brand-final');
const mac = path.join(root, 'macos');
const INK = '#172435';
const BLUE = '#2764E7';
const ACCENT = '#5D94FF';
const WHITE = '#FFFFFF';
const mkdir = p => fs.mkdirSync(p, { recursive: true });
const write = (p, data) => { mkdir(path.dirname(p)); fs.writeFileSync(p, data); };
const json = (p, data) => write(p, JSON.stringify(data, null, 2) + '\n');
const read = p => fs.readFileSync(p, 'utf8')
  // Keep the approved silhouette while clearing two subpixel junctions.
  .replaceAll('L52 65L43 78Z', 'L52 65L48 73Z')
  .replaceAll('C84 100 69 111 46 113L38 103Z', 'C84 99 69 109 46 111L38 103Z');
const iconSource = read(path.join(source, 'concepts/01-lift/icon/color.svg'));
const symbolGroup = iconSource.match(/<g transform=.*<\/g>/s)[0];
const svg = (w, h, title, body, viewBox = `0 0 ${w} ${h}`) => `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${viewBox}" role="img" aria-labelledby="title"><title id="title">${title}</title>${body}</svg>\n`;
const monochrome = color => symbolGroup.replace(/fill="#[0-9A-Fa-f]{6}"/g, `fill="${color}"`);
const scaled = (body, x, y, scale) => `<g transform="translate(${x} ${y}) scale(${scale})">${body}</g>`;

async function png(input, file, width) {
  let image = sharp(Buffer.isBuffer(input) ? input : Buffer.from(input), { density: 144 });
  if (width) image = image.resize({ width });
  await image.toColourspace('srgb').withIccProfile('srgb').png({ compressionLevel: 6 }).toFile(file);
}

async function main() {
  mkdir(root);
  const variants = [
    ['color', 'color'],
    ['mono-dark', 'dark'],
    ['mono-white', 'light'],
    ['color-reverse', 'color']
  ];
  for (const layout of ['horizontal', 'vertical']) {
    for (const [variant, original] of variants) {
      let data = read(path.join(source, `concepts/01-lift/${layout}/${original}.svg`));
      if (variant === 'color-reverse') data = data.replace(`fill="${INK}" transform=`, `fill="${WHITE}" transform=`);
      data = data.replace(/DiskWing · Lift · (color|dark|light)/g, `DiskWing · Lift · ${layout} · ${variant}`);
      const file = `diskwing-${layout}-${variant}`;
      write(path.join(root, 'logo/svg', `${file}.svg`), data);
      mkdir(path.join(root, 'logo/png'));
      await png(data, path.join(root, 'logo/png', `${file}.png`), layout === 'horizontal' ? 1800 : 1200);
    }
  }
  for (const [variant, original] of variants.slice(0,3)) {
    const data = read(path.join(source, `concepts/01-lift/icon/${original}.svg`)).replace(/DiskWing · Lift · (color|dark|light)/g, `DiskWing · Lift · symbol · ${variant}`);
    const name = `diskwing-symbol-${variant}`;
    write(path.join(root,'logo/svg',name+'.svg'),data);
    await png(data,path.join(root,'logo/png',name+'.png'),512);
  }
  for (const [variant, original] of [['dark','dark'], ['white','light']]) {
    const data = read(path.join(source,`wordmark/${original}.svg`));
    write(path.join(root,'logo/svg',`diskwing-wordmark-${variant}.svg`),data);
    await png(data,path.join(root,'logo/png',`diskwing-wordmark-${variant}.png`),1600);
  }

  const appSVG = read(path.join(source,'concepts/01-lift/app-icon/color.svg')).replace('DiskWing · Lift · color','DiskWing · Lift · macOS app icon');
  write(path.join(mac,'diskwing-app-icon.svg'),appSVG);
  await png(appSVG,path.join(mac,'diskwing-app-icon-1024.png'),1024);
  const iconset=path.join(mac,'DiskWing.iconset');
  const catalog=path.join(mac,'DiskWing.xcassets');
  const appset=path.join(catalog,'AppIcon.appiconset');
  mkdir(iconset); mkdir(appset);
  json(path.join(catalog,'Contents.json'),{info:{author:'DiskWing',version:1}});
  const images=[];
  for (const points of [16,32,128,256,512]) {
    for (const scale of [1,2]) {
      const name=`icon_${points}x${points}${scale===2?'@2x':''}.png`;
      await png(appSVG,path.join(iconset,name),points*scale);
      fs.copyFileSync(path.join(iconset,name),path.join(appset,name));
      images.push({filename:name,idiom:'mac',scale:`${scale}x`,size:`${points}x${points}`});
    }
  }
  json(path.join(appset,'Contents.json'),{images,info:{author:'DiskWing',version:1}});

  const menuSVG=svg(112,112,'DiskWing · menu bar template',monochrome('#000000'),'8 10 112 112');
  write(path.join(mac,'diskwing-menubar-template.svg'),menuSVG);
  const menuSet=path.join(catalog,'DiskWingMenuBarTemplate.imageset');
  const markSet=path.join(catalog,'DiskWingMark.imageset');
  mkdir(menuSet); mkdir(markSet);
  const menuImages=[],markImages=[];
  for(const scale of [1,2]) {
    const suffix=scale===2?'@2x':'';
    const menuName=`diskwing-menubar${suffix}.png`;
    await png(menuSVG,path.join(menuSet,menuName),18*scale);
    menuImages.push({filename:menuName,idiom:'mac',scale:`${scale}x`});
    const markName=`diskwing-mark${suffix}.png`;
    await png(iconSource,path.join(markSet,markName),128*scale);
    markImages.push({filename:markName,idiom:'mac',scale:`${scale}x`});
  }
  json(path.join(menuSet,'Contents.json'),{images:menuImages,info:{author:'DiskWing',version:1},properties:{'template-rendering-intent':'template'}});
  json(path.join(markSet,'Contents.json'),{images:markImages,info:{author:'DiskWing',version:1},properties:{'template-rendering-intent':'original'}});

  // Foreground layers are intentionally unmasked for Apple's Icon Composer.
  // Its square canvas maps to the inset macOS tile in the legacy export.
  const composerMark=svg(1024,1024,'DiskWing · Lift · foreground',scaled(monochrome(WHITE),118.153846,118.153846,6.153846));
  const composerFolder=path.join(mac,'icon-composer-source');
  write(path.join(composerFolder,'01-lift-mark.svg'),composerMark);
  await png(composerMark,path.join(composerFolder,'01-lift-mark.png'),1024);
  json(path.join(composerFolder,'composition.json'),{
    name:'DiskWing',canvas:{width:1024,height:1024},background:{color:BLUE,colorSpace:'sRGB'},
    layers:[{name:'01 Lift mark',file:'01-lift-mark.svg',position:{x:0,y:0},size:{width:1024,height:1024}}],
    note:'Especificação legível da composição; não é o documento nativo .icon. Não aplicar máscara ou margem adicional ao importar esta camada.'
  });

  for(const name of ['Manrope.ttf','Manrope-OFL.txt']) {
    write(path.join(root,'source',name),fs.readFileSync(path.join(source,'source',name)));
  }
  write(path.join(root,'source','lift-mark.svg'),iconSource);
  json(path.join(root,'brand-colors.json'),{primary:BLUE,accent:ACCENT,ink:INK,white:WHITE});
  if (!packaged) {
    for (const layout of ['icon', 'horizontal', 'vertical', 'app-icon']) {
      for (const variant of ['color','dark','light']) {
        const relative=`concepts/01-lift/${layout}/${variant}.svg`;
        write(path.join(root,'source/masters',relative),fs.readFileSync(path.join(source,relative)));
      }
    }
    for (const variant of ['dark','light']) {
      const relative=`wordmark/${variant}.svg`;
      write(path.join(root,'source/masters',relative),fs.readFileSync(path.join(source,relative)));
    }
    for (const name of ['Manrope.ttf','Manrope-OFL.txt']) {
      write(path.join(root,'source/masters/source',name),fs.readFileSync(path.join(source,'source',name)));
    }
  }
  write(path.join(root,'source','build-assets.cjs'),fs.readFileSync(__filename));

  const logo=read(path.join(root,'logo/svg/diskwing-horizontal-color.svg')).match(/<g.*<\/g>/s)[0];
  const reverse=read(path.join(root,'logo/svg/diskwing-horizontal-color-reverse.svg')).match(/<g.*<\/g>/s)[0];
  const label=(s,x,y,size=18,color='#647286',weight=500)=>`<text x="${x}" y="${y}" font-family="Arial, sans-serif" font-size="${size}" font-weight="${weight}" fill="${color}">${s}</text>`;
  let board='<rect width="1600" height="1080" fill="#F4F3EF"/>';
  board+=label('DISKWING / LIFT',64,60,17,'#647286',700);
  board+=label('Identidade final',64,126,52,INK,700);
  board+=label('Logo, símbolo e ícone para macOS',64,167,21);
  board+='<rect x="64" y="212" width="868" height="348" rx="24" fill="#FFF"/>';
  board+=label('LOGO PRINCIPAL',96,258,14);
  board+=scaled(logo,105,315,1.35);
  board+='<rect x="64" y="588" width="868" height="348" rx="24" fill="#172435"/>';
  board+=label('VERSÃO PARA FUNDO ESCURO',96,635,14,'#B7C3D3');
  board+=scaled(reverse,105,691,1.35);
  board+='<rect x="960" y="212" width="576" height="724" rx="24" fill="#FFF"/>';
  board+=label('ÍCONE DO APLICATIVO',992,258,14);
  const appInner=appSVG.match(/<rect.*<\/g>/s)[0];
  board+=scaled(appInner,1030,296,.42);
  board+=label('1024 × 1024 px · ICNS · Xcode',1040,767,17);
  board+=label('BARRA DE MENUS',1000,824,13);
  board+=scaled(monochrome(INK),1002,849,18/128);
  board+=scaled(monochrome(INK),1040,843,30/128);
  board+=label('18 pt / @2x',1090,866,16);
  board+=`<circle cx="78" cy="992" r="8" fill="${BLUE}"/>`+label(BLUE,98,998,16);
  board+=`<circle cx="254" cy="992" r="8" fill="${ACCENT}"/>`+label(ACCENT,274,998,16);
  board+=`<circle cx="430" cy="992" r="8" fill="${INK}"/>`+label(INK,450,998,16);
  board+=label('diskwing.tech',1536,1000,18);
  // Align the footer within its right margin.
  board=board.replace('x="1536" y="1000"','x="1536" y="1000" text-anchor="end"');
  write(path.join(root,'source','preview.svg'),svg(1600,1080,'DiskWing · Lift · identidade final',board));
  await png(svg(1600,1080,'DiskWing · Lift · identidade final',board),path.join(root,'preview.png'),1600);

  const sizes=[16,32,64,128,256];
  let proof='<rect width="1200" height="440" fill="#F4F3EF"/>';
  proof+=label('DiskWing / ícones em tamanho real',48,68,30,INK,700);
  let x=48;
  for(const size of sizes) {
    proof+=scaled(appInner,x,128+(256-size)/2,size/1024);
    proof+=label(size+' px',x,415,16);
    x+=size+66;
  }
  await png(svg(1200,440,'DiskWing · redução do ícone',proof),path.join(root,'icon-size-check.png'),1200);
  console.log(JSON.stringify({root,svgLogoCount:fs.readdirSync(path.join(root,'logo/svg')).length,appIconSlots:images.length,menuBarPoints:18}));
}
main().catch(e=>{console.error(e);process.exit(1);});
