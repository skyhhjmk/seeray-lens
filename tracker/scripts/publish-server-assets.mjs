import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const trackerRoot = resolve(import.meta.dirname, '..');
const resources = resolve(trackerRoot, '../server/src/main/resources/META-INF/resources');
const tracker = await readFile(resolve(trackerRoot, 'dist/index.global.js'), 'utf8');
const bootstrap = await readFile(resolve(trackerRoot, 'src/bootstrap.js'), 'utf8');
await writeFile(
  resolve(resources, 'tracker.js'),
  `${tracker.trimEnd()}\n${bootstrap.trimEnd()}\n`,
);
await copyFile(resolve(trackerRoot, 'dist/recorder.js'), resolve(resources, 'recorder.js'));
await copyFile(resolve(trackerRoot, 'dist/replayer.js'), resolve(trackerRoot, '../admin/web/replayer.js'));
await mkdir(resolve(trackerRoot, '../admin/assets'), { recursive: true });
await copyFile(resolve(trackerRoot, 'dist/replayer.js'), resolve(trackerRoot, '../admin/assets/replayer.js'));
