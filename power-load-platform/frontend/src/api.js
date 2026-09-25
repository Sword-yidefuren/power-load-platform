import axios from 'axios'

/**
 * 第 6 步 · API 层 —— 前端唯一"跟后端说话"的地方
 *
 * 为什么要专门建一个 api.js，而不是在每个组件里各写各的 axios？
 *   1. 地址只写一遍。后端哪天改了路径，只改这里一处。
 *   2. 以后要加统一的 token、超时、错误处理，也在这里加。
 *   3. 组件里只剩下 `const data = await getRegionSummary()`，读起来清楚。
 *
 * ★ 重点：baseURL 写的是 '/api'，不是 'http://127.0.0.1:8080/api'。
 *   因为要走 vite.config.js 里配的代理 —— 写完整地址反而会触发跨域。
 *   这是前后端联调最常见的坑：地址写对了，却被浏览器 CORS 拦掉。
 */
const http = axios.create({
  baseURL: '/api',
  timeout: 10000
})

// 响应拦截器：把"网络层错误"翻译成人能看懂的话。
// 没有它的话，你只会看到 "Request failed with status code 500"，
// 完全不知道是后端挂了、数据库没启动、还是地址写错了。
http.interceptors.response.use(
  (response) => response,
  (error) => {
    let hint = error.message
    if (error.code === 'ECONNABORTED') {
      hint = '请求超时：后端可能没启动，或者这条查询太慢'
    } else if (!error.response) {
      hint = '连不上后端：请确认 Spring Boot 已经在 8080 端口启动'
    } else {
      const status = error.response.status
      if (status === 404) hint = '404 接口不存在：检查地址有没有拼错'
      else if (status === 500) hint = '500 后端内部错误：去看 Spring Boot 控制台的堆栈'
      else if (status === 403) hint = '403 被拒绝（可能是跨域或权限问题）'
    }
    return Promise.reject(new Error(hint))
  }
)

// ---------------- 明细 ----------------
/** 全部负荷记录，或按地区筛选 */
export function getLoadRecords(region) {
  const params = region ? { region } : {}
  return http.get('/load-records', { params }).then((r) => r.data)
}

/** 高负荷记录 */
export function getHighLoad(threshold = 10000) {
  return http.get('/load-records/high', { params: { threshold } }).then((r) => r.data)
}

// ---------------- 统计 ----------------
/** 按地区聚合（平均/峰值/谷值/异常数） */
export function getRegionSummary() {
  return http.get('/stats/region-summary').then((r) => r.data)
}

/** 按地区聚合 + 派生指标（峰谷差、负荷率） */
export function getRegionDetail() {
  return http.get('/stats/region-detail').then((r) => r.data)
}

/** 按日期聚合 */
export function getByDate() {
  return http.get('/stats/by-date').then((r) => r.data)
}

/** 读算法预先算好的日统计表 */
export function getDailyStat() {
  return http.get('/stats/daily').then((r) => r.data)
}
