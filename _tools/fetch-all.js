// 并行下载三件套，各自重试 3 次
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const TOOLS = path.resolve(__dirname, '..');
const CACHE = path.join(TOOLS, '_cache');
fs.mkdirSync(CACHE, { recursive: true });

const targets = [
  {
    name: 'JDK 17',
    url: 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip',
    out: path.join(CACHE, 'jdk17.zip'),
  },
  {
    name: 'Maven 3.9.11',
    // dlcdn 只保留最新版，3.9.x 已归档到 archive
    url: 'https://archive.apache.org/dist/maven/maven-3/3.9.11/binaries/apache-maven-3.9.11-bin.zip',
    out: path.join(CACHE, 'maven.zip'),
  },
  {
    name: 'MySQL 8.0.44',
    url: 'https://cdn.mysql.com/Downloads/MySQL-8.0/mysql-8.0.44-winx64.zip',
    out: path.join(CACHE, 'mysql.zip'),
  },
];

function downloadOnce(t) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [path.join(__dirname, 'download.js'), t.url, t.out], {
      stdio: 'inherit',
    });
    child.on('close', (code) => resolve(code === 0));
  });
}

async function downloadWithRetry(t) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    console.log(`\n[${t.name}] 第 ${attempt} 次尝试...`);
    if (fs.existsSync(t.out) && fs.statSync(t.out).size > 1024 * 1024) {
      console.log(`[${t.name}] 已存在，跳过`);
      return true;
    }
    if (await downloadOnce(t)) return true;
    console.log(`[${t.name}] 失败，准备重试`);
  }
  console.error(`[${t.name}] 三次均失败`);
  return false;
}

(async () => {
  const results = await Promise.all(targets.map(downloadWithRetry));
  console.log('\n===== 下载结果 =====');
  targets.forEach((t, i) => console.log(`${results[i] ? 'OK  ' : 'FAIL'} ${t.name}`));
  if (results.some((r) => !r)) process.exit(1);
})();
