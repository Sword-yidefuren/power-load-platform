<script setup>
/**
 * 日统计对比：同一天里，各地区的"平均 / 峰值 / 谷值"负荷
 *
 * ★ 关于这张图的设计取舍（这是个真实的工程判断，值得一讲）：
 *
 *   后端 /api/stats/by-date 返回的是"按日期聚合"的结果。
 *   但目前数据库里的数据**只有 2026-09-23 这一天**，
 *   所以那个接口只返回 1 行 —— 一条数据是画不出"趋势线"的。
 *
 *   与其画一张只有 1 个点的假折线图，不如换个更有意义的视角：
 *   用 /api/stats/daily 拿到的"每地区每天的统计"，
 *   按地区对比平均/峰值/谷值。这样能直接看出：
 *     - 谁的峰值最高（对电网压力最大）
 *     - 谁的峰谷差最大（用电最不均衡）
 *
 *   等以后数据积累到多天，把 x 轴换成 statDate 就能变成真正的趋势图。
 *   这里我特意把 xAxis 写成"地区"，是为了让它现在就"有话说"。
 *
 *   —— 面试时这种"我知道数据量不够所以换了展示方式"的判断，比多画一张图值钱。
 */
import { watch } from 'vue'
import { useECharts } from '../composables/useECharts'

const props = defineProps({
  // 后端 /api/stats/daily 返回的 data 数组（load_daily_stat 表的行）
  daily: { type: Array, default: () => [] }
})

const { chartRef, setOption } = useECharts()

function draw() {
  const rows = props.daily || []
  if (!rows.length) return

  // 地区编码 -> 中文名。数据里只有编码（GD-01），画图给人看要转成名字。
  // 真实项目里这张对照表应该来自后端接口，这里为了简单先写死。
  const nameOf = { 'GD-01': '广州', 'GD-02': '深圳' }
  const labels = rows.map((r) => nameOf[r.regionCode] || r.regionCode)

  setOption({
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' }
    },
    legend: { data: ['平均负荷', '峰值负荷', '谷值负荷'], top: 0 },
    grid: { left: 70, right: 30, top: 40, bottom: 40 },
    xAxis: { type: 'category', data: labels },
    yAxis: {
      type: 'value',
      name: '负荷 (kW)',
      nameTextStyle: { color: '#909399' },
      axisLabel: { formatter: (v) => v.toLocaleString() }
    },
    series: [
      {
        name: '平均负荷',
        type: 'bar',
        barWidth: '20%',
        itemStyle: { color: '#409eff', borderRadius: [4, 4, 0, 0] },
        data: rows.map((r) => Number(r.avgLoad))
      },
      {
        name: '峰值负荷',
        type: 'bar',
        barWidth: '20%',
        itemStyle: { color: '#f56c6c', borderRadius: [4, 4, 0, 0] },
        data: rows.map((r) => Number(r.maxLoad))
      },
      {
        name: '谷值负荷',
        type: 'bar',
        barWidth: '20%',
        itemStyle: { color: '#67c23a', borderRadius: [4, 4, 0, 0] },
        data: rows.map((r) => Number(r.minLoad))
      }
    ]
  })
}

watch(() => props.daily, draw, { deep: true, immediate: true })
</script>

<template>
  <div ref="chartRef" class="chart"></div>
</template>
