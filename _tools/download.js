// 下载工具：用 Node 内置 fetch 下载大文件到磁盘（PowerShell 的 schannel 在此环境不可用）
// 用法: node download.js <url> <输出文件路径>
const fs = require('fs');
const path = require('path');

const [, , url, outPath] = process.argv;

if (!url || !outPath) {
  console.error('用法: node download.js <url> <outPath>');
  process.exit(1);
}

async function main() {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });

  const res = await fetch(url, {
    redirect: 'follow',
    headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) dsh-setup' },
  });

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText} for ${url}`);
  }

  const total = Number(res.headers.get('content-length') || 0);
  let done = 0;
  let lastPct = -1;

  const out = fs.createWriteStream(outPath);
  const reader = res.body.getReader();

  while (true) {
    const { done: finished, value } = await reader.read();
    if (finished) break;
    done += value.length;
    if (!out.write(Buffer.from(value))) {
      await new Promise((r) => out.once('drain', r));
    }
    if (total) {
      const pct = Math.floor((done / total) * 100);
      if (pct >= lastPct + 10) {
        lastPct = pct;
        process.stdout.write(`  ${pct}%  (${(done / 1048576).toFixed(1)}/${(total / 1048576).toFixed(1)} MB)\n`);
      }
    }
  }

  await new Promise((r) => out.end(r));
  const size = fs.statSync(outPath).size;
  console.log(`OK ${outPath}  ${(size / 1048576).toFixed(1)} MB`);
}

main().catch((e) => {
  console.error('下载失败:', e.message);
  process.exit(1);
});
