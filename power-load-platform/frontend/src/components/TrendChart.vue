<script setup>
/**
 * 折线图：各地区负荷随时间的变化曲线
 *
 * 这是整个项目的"主图" —— 电力负荷数据最经典的展现方式。
 * 你能从图上直接看出"日双峰"规律（午高峰、晚高峰）。
 *
 * props 是父组件传进来的数据。Vue 的规则：子组件不要自己去请求接口，
 * 数据由父组件统一拿了再传下来 —— 这样只有一个地方管数据，
 * 出了问题好定位（面试可以聊"单一数据源"）。
 */
import { watch } from 'vue'
import { useECharts, COLORS } from '../composables/useECharts'

const props = defineProps({
  // 后端 /api/load-records 返回的 data 数组
  records: { type: Array, default: () => [] }
})

const { chartRef, setOption } = useECharts()

function draw() {
  const rows = props.records || []
  if (!rows.length) return

  // 1) 把扁平的数据按地区分组：{ '广州': [...], '深圳': [...] }
  const byRegion = {}
  rows.forEach((r) => {
    if (!byRegion[r.regionName]) byRegion[r.regionName] = []
    byRegion[r.regionName].push(r)
  })

  // 2) 时间轴：取所有记录的时刻，去重后排序。
  //    slice(11,16) 是把 "2026-09-23 14:00:00" 截成 "14:00"，
  //    这样横轴不会太长。
  const times = [...new Set(rows.map((r) => r.ts))].sort()
  const xLabels = times.map((t) => String(t).slice(11, 16))

  // 3) 每个地区一条折线。没有该时刻的数据就填 null，ECharts 会断开，
  //    不会错误地连成一条直线。
  const series = Object.keys(byRegion).map((region, idx) => {
    const map = {}
    byRegion[region].forEach((r) => {
      map[String(r.ts).slice(11, 16)] = Number(r.loadKw)
    })
    return {
      name: region,
      type: 'line',
      smooth: true,
      symbolSize: 7,
      connectNulls: false,
      lineStyle: { width: 3 },
      itemStyle: { color: COLORS[idx % COLORS.length] },
      data: xLabels.map((t) => (t in map ? map[t] : null))
    }
  })

  // 4) 找出异常点，单独用一个散点系列标红 —— 这就是"异常检测"的可视化
  const anomalies = rows
    .filter((r) => r.isAnomaly === 1)
    .map((r) => [String(r.ts).slice(11, 16), Number(r.loadKw)])

  if (anomalies.length) {
    series.push({
      name: '异常点',
      type: 'scatter',
      symbolSize: 16,
      itemStyle: { color: '#f56c6c' },
      data: anomalies,
      // 只用来标注，不参与图例的折线语义
      z: 10
    })
  }

  setOption({
    tooltip: { trigger: 'axis' },
    legend: { data: series.map((s) => s.name), top: 0 },
    grid: { left: 60, right: 30, top: 40, bottom: 40 },
    xAxis: { type: 'category', boundaryGap: false, data: xLabels },
    yAxis: {
      type: 'value',
      name: '负荷 (kW)',
      nameTextStyle: { color: '#909399' },
      axisLabel: { formatter: (v) => v.toLocaleString() }
    },
    series
  })
}

// watch 而不是直接在 setup 里调用 —— 这一点很重要：
// setup 执行时 props 已经有了，但图表还没挂载（onMounted 还没跑）。
// 用 watch + immediate:true，无论"数据先到"还是"组件先挂载"都能正确画出来。
watch(() => props.records, draw, { deep: true, immediate: true })
</script>

<template>
  <div ref="chartRef" class="chart tall"></div>
</template>
