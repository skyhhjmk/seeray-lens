import { stat } from 'node:fs/promises';

const files = ['dist/index.js', 'dist/index.global.js'];
for (const file of files) {
  const size = await stat(file);
  console.log(`${file}: ${size.size} bytes`);
}
