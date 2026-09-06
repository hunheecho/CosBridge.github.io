// index.html + style.css + src/*.js 를 하나의 HTML로 합친다 (dist/prophecy_single.html). 배포·공유용.
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
let html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
html = html.replace('<link rel="stylesheet" href="style.css">', () => '<style>\n' + fs.readFileSync(path.join(ROOT, 'style.css'), 'utf8') + '\n</style>');
html = html.replace(/<script src="src\/(\w+)\.js"><\/script>/g, (_, name) => '<script>\n' + fs.readFileSync(path.join(ROOT, 'src', name + '.js'), 'utf8').replace(/<\/script>/g, '<\\/script>') + '\n</script>');
fs.mkdirSync(path.join(ROOT, 'dist'), { recursive: true });
const out = path.join(ROOT, 'dist', 'prophecy_single.html');
fs.writeFileSync(out, html);
console.log('built', out, Math.round(fs.statSync(out).size / 1024) + 'KB');
// 아티팩트/임베드용: 문서 래퍼 태그 없이 <title>·<style>·본문·<script>만
const inner = html.replace(/^[\s\S]*?<head>/, '').replace(/<\/head>\s*<body>/, '').replace(/<\/body>\s*<\/html>\s*$/, '')
  .replace(/<meta[^>]*>\s*/g, '');
const out2 = path.join(ROOT, 'dist', 'prophecy_artifact.html');
fs.writeFileSync(out2, inner.trim() + '\n');
console.log('built', out2, Math.round(fs.statSync(out2).size / 1024) + 'KB');
