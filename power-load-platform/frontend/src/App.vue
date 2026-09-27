<script setup>
/**
 * 主界面 —— 整个看板的"总指挥"
 *
 * ★ 重要设计原则：数据只在 App.vue 里请求一次，然后分发给各个子组件。
 *
 *   为什么不各组件自己请求？
 *     1. 同一个接口可能被多个图用到，各请求一次 = 重复请求，浪费
 *     2. 出了问题只有一个地方要查
 *     3. 筛选条件（比如"只看深圳"）要影响多个图，集中管理才不会打架
 *
 *   这叫"单一数据源"。面试聊前端架构时会问到。
 */
import { computed, onMounted, ref } from 'vue'
import {
  getLoadRecords,
  getRegionSummary,
  getRegionDetail,
  getDailyStat,
  getForecast,
  getForecastOverview
} from './api'

import TrendChart from './components/TrendChart.vue'
import RegionBar from './components/RegionBar.vue'
import DailyLine from './components/DailyLine.vue'
import AnomalyTable from './components/AnomalyTable.vue'
import ForecastChart from './components/ForecastChart.vue'

// ---------------- 数据状态 ----------------
// ref 是 Vue 3 的"响应式"容器：它里面的值一变，用到它的地方会自动重新渲染。
const records = ref([])        // 明细记录
const summary = ref([])        // 按地区聚合
const detail = ref([])         // 按地区聚合 + 派生指标
const daily = ref([])          // 算法算好的日统计
const forecast = ref([])        // 预测曲线（按地区分组）
const forecastInfo = ref({})    // 预测概览（点数、R²、免责说明）
const loading = ref(true)
const error = ref('')
const picked = ref('')         // 当前在柱状图上点选的地区

/**
 * 一次把所有数据取回来。
 * Promise.all 让多个请求"同时发出"，而不是一个等一个 —— 页面加载快好几倍。
 */
async function loadAll() {
  loading.value = true
  error.value = ''
  try {
    const [rec, sum, det, dai, fc, fcInfo] = await Promise.all([
      getLoadRecords(),
      getRegionSummary(),
      getRegionDetail(),
      getDailyStat(),
      getForecast(),
      getForecastOverview()
    ])
    records.value = rec.data || []
    summary.value = sum.data || []
    detail.value = det.data || []
    daily.value = dai.data || []
    forecast.value = fc.data || []
    forecastInfo.value = fcInfo || {}
  } catch (e) {
    // api.js 的拦截器已经把错误翻译成人话了，这里直接显示
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(loadAll)

/**
 * 顶部 KPI 指标：从明细数据里现算。
 *
 * computed 会自动跟着 records 变化重新计算，
 * 不需要手动"数据变了再调一次计算函数" —— 这就是响应式的好处。
 */
const kpi = computed(() => {
  const rows = records.value
  if (!rows.length) {
    return { total: 0, peak: 0, avg: 0, anomalies: 0 }
  }
  const loads = rows.map((r) => Number(r.loadKw))
  return {
    total: rows.length,
    peak: Math.max(...loads),
    avg: loads.reduce((a, b) => a + b, 0) / loads.length,
    anomalies: rows.filter((r) => r.isAnomaly === 1).length
  }
})

/** 点柱状图时触发：把选中的地区存起来，折线图会自动跟着筛 */
function onPickRegion(name) {
  picked.value = picked.value === name ? '' : name
}

/**
 * 折线图实际用的数据：如果选了地区，就只保留该地区的记录。
 *
 * 注意这里是"前端筛选"，不是重新请求后端。
 * 数据量小的时候这样最快；数据量大（几万行）就必须改成请求后端带参数查询，
 * 否则要把全表拉到浏览器里 —— 这也是面试可能问的点。
 */
const trendRecords = computed(() => {
  if (!picked.value) return records.value
  return records.value.filter((r) => r.regionName === picked.value)
})
</script>

<template>
  <div>
    <!-- 顶部标题 -->
    <div class="page-header">
      <h1>电力负荷数据可视化平台</h1>
      <div class="sub">
        Spring Boot + MySQL + Vue3 + ECharts ·
        数据来源：load_record 明细表 / load_daily_stat 统计表
      </div>
    </div>

    <!-- 加载中 -->
    <div v-if="loading" class="state">正在从后端加载数据…</div>

    <!-- 加载失败：显示原因 + 重试按钮 -->
    <div v-else-if="error" class="state error">
      <div>❌ 加载失败：{{ error }}</div>
      <button @click="loadAll">重试</button>
    </div>

    <!-- 正常内容 -->
    <template v-else>
      <!-- KPI 卡片 -->
      <div class="kpi-row">
        <div class="kpi-card">
          <div class="label">采样记录总数</div>
          <div class="value">{{ kpi.total }}<span class="unit">条</span></div>
        </div>
        <div class="kpi-card">
          <div class="label">最高负荷</div>
          <div class="value">{{ kpi.peak.toLocaleString() }}<span class="unit">kW</span></div>
        </div>
        <div class="kpi-card">
          <div class="label">平均负荷</div>
          <div class="value">{{ kpi.avg.toFixed(1) }}<span class="unit">kW</span></div>
        </div>
        <div class="kpi-card" :class="{ warn: kpi.anomalies > 0 }">
          <div class="label">异常点数量</div>
          <div class="value">{{ kpi.anomalies }}<span class="unit">个</span></div>
        </div>
      </div>

      <!-- 主图：负荷趋势 -->
      <div class="card">
        <h2>各地区负荷趋势</h2>
        <div class="hint">
          横轴是当天各采样时刻，纵轴是负荷值。红点 = 算法判定的异常点。
          <span v-if="picked">
            · 当前只看 <b>{{ picked }}</b>
            <a href="#" @click.prevent="picked = ''" style="margin-left: 8px">显示全部</a>
          </span>
        </div>
        <TrendChart :records="trendRecords" />
      </div>

      <div class="grid-2">
        <!-- 柱状图：地区对比（可点击筛选） -->
        <div class="card">
          <h2>各地区平均负荷对比</h2>
          <div class="hint">点击柱子可只看该地区的趋势（再点一次取消）</div>
          <RegionBar :summary="summary" @pick="onPickRegion" />
        </div>

        <!-- 日统计对比 -->
        <div class="card">
          <h2>日统计：平均 / 峰值 / 谷值</h2>
          <div class="hint">数据来自 load_daily_stat 表</div>
          <DailyLine :daily="daily" />
        </div>
      </div>

      <!-- ============================================================
           第 7 步：负荷预测（Python 线性回归 + 回写数据库 + 后端接口）
           ============================================================ -->
      <div class="card">
        <h2>负荷预测：历史实际 vs 未来 24 小时</h2>
        <div class="hint">
          实线 = 历史实际负荷　|　深色虚线 = 模型见过的时刻（相对可靠）　|　
          <span style="color: #f56c6c">浅色点线 = 模型外推（训练时未见过该时刻，可信度低）</span>
        </div>
        <ForecastChart :series="forecast" :records="records" />
        <div class="kpi-row" style="margin-top: 16px; margin-bottom: 0">
          <div class="kpi-card">
            <div class="label">预测点数</div>
            <div class="value">{{ forecastInfo.totalPoints || 0 }}<span class="unit">个</span></div>
          </div>
          <div class="kpi-card">
            <div class="label">覆盖地区</div>
            <div class="value">{{ forecastInfo.regionCount || 0 }}<span class="unit">个</span></div>
          </div>
          <div class="kpi-card">
            <div class="label">模型留一法 R²</div>
            <div class="value">{{ forecastInfo.modelR2 ?? '-' }}</div>
          </div>
          <div class="kpi-card warn">
            <div class="label">模型说明</div>
            <div class="value" style="font-size: 13px; line-height: 1.5">
              仅 8 条训练数据<br />不代表真实预测能力
            </div>
          </div>
        </div>
        <div class="hint" style="margin-top: 12px; margin-bottom: 0">
          {{ forecastInfo.note }}
        </div>
      </div>

      <!-- 派生指标表：峰谷差、负荷率 -->
      <div class="card">
        <h2>地区负荷特征指标</h2>
        <div class="hint">
          峰谷差和负荷率是后端 Java 计算出来的派生指标，数据库里没有这两列
        </div>
        <table>
          <thead>
            <tr>
              <th>地区</th>
              <th style="text-align: right">样本数</th>
              <th style="text-align: right">平均负荷 (kW)</th>
              <th style="text-align: right">峰值 (kW)</th>
              <th style="text-align: right">谷值 (kW)</th>
              <th style="text-align: right">峰谷差 (kW)</th>
              <th style="text-align: right">负荷率</th>
              <th style="text-align: right">异常点</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in detail" :key="row.regionCode">
              <td>{{ row.regionName }}</td>
              <td class="num">{{ row.sampleCount }}</td>
              <td class="num">{{ Number(row.avgLoad).toFixed(1) }}</td>
              <td class="num">{{ Number(row.maxLoad).toFixed(1) }}</td>
              <td class="num">{{ Number(row.minLoad).toFixed(1) }}</td>
              <td class="num">{{ Number(row.peakValleyDiff).toFixed(1) }}</td>
              <td class="num">{{ (Number(row.loadRate) * 100).toFixed(2) }}%</td>
              <td class="num">
                <!--
                  注意字段名是 anomalyCount（聚合结果），不是 isAnomaly（单条记录的标记）。
                  写错不会报错，只会显示 undefined —— 前后端联调最难查的就是这种。
                -->
                <span v-if="row.anomalyCount > 0" class="tag danger">{{ row.anomalyCount }}</span>
                <span v-else>0</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 明细表格 -->
      <AnomalyTable :records="records" />
    </template>
  </div>
</template>
