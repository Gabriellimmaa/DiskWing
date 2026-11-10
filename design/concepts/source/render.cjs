const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');

async function main() {
  for (const name of ['overview', 'overview-dark', 'size-check']) {
    await sharp(path.join(root, `${name}.svg`)).png().toFile(path.join(root, `${name}.png`));
  }
  for (const concept of fs.readdirSync(path.join(root, 'concepts'))) {
    for (const kind of ['icon', 'horizontal', 'vertical', 'app-icon']) {
      const folder = path.join(root, 'concepts', concept, kind);
      await sharp(path.join(folder, 'color.svg'), {density: kind === 'app-icon' ? 72 : 144})
        .png().toFile(path.join(folder, 'color.png'));
    }
  }
  console.log('Rendered presentation boards and 16 transparent PNG assets.');
}
main().catch(e => { console.error(e); process.exit(1); });
