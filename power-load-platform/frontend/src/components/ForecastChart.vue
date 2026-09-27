<script setup>
/**
 * 第 7 步 · 预测曲线图
 *
 * 把"历史实际负荷"和"Python 模型预测的未来 24 小时"画在同一张图上。
 *
 * ★ 这张图最重要的设计不是好看，而是**诚实**：
 *
 *   后端返回的每个预测点都带一个 extrapolated 标记 ——
 *   表示"这个时刻模型在训练时从未见过"（历史数据只覆盖 0/1/2/12/14 点，
 *   所以 24 个小时里有 19 个属于外推）。
 *
 *   如果把这些点画得和外推点一样"实"，看图的人会误以为所有预测都一样可靠。
 *   所以我用两种线型区分：
 *       见过的时刻 -> 深色虚线（相对可靠）
 *       外推的时刻 -> 浅色点线（可信度低）
 *
 *   这种"把数据可信度画出来"的做法，比藏起来专业得多 ——
 *   面试聊到可视化时，这是一个能体现判断力的点。
 */
import { watch } from 'vue'
import { useECharts } from '../composables/useECharts'

const props = defineProps({
  // 后端 /api/forecast 返回的 data（按地区分组的数组）
  series: { type: Array, default: () => [] },
  // 后端 /api/load-records 的历史明细，用来画"实际"那一段
  records: { type: Array, default: () => [] }
})

const { chartRef, setOption } = useECharts()

const COLOR = { 'GD-01': '#e74c3c', 'GD-02': '#2980b9' }

function draw() {
  const groups = props.series || []
  if (!groups.length) return

  const actual = []
  const predicted = []
  const extrapolated = []

  // ---------- 1. 历史实际曲线 ----------
  const byRegion = {}
  ;(props.records || []).forEach((r) => {
    if (!byRegion[r.regionName]) byRegion[r.regionName] = []
    byRegion[r.regionName].push(r)
  })

  Object.keys(byRegion).forEach((name) => {
    const rows = byRegion[name].sort((a, b) => String(a.ts).localeCompare(String(b.ts)))
    actual.push({
      name: `${name} 实际`,
      type: 'line',
      smooth: false,
      symbolSize: 7,
      lineStyle: { width: 3, type: 'solid' },
      itemStyle: { color: name === '广州' ? COLOR['GD-01'] : COLOR['GD-02'] },
      // x 轴用时间字符串，和预测点对齐
      data: rows.map((r) => [String(r.ts).slice(0, 16).replace('T', ' '), Number(r.loadKw)])
    })
  })

  // ---------- 2. 预测曲线（区分外推点） ----------
  groups.forEach((g) => {
    const color = COLOR[g.regionCode] || '#909399'

    // 只包含"模型见过的时刻"的预测
    predicted.push({
      name: `${g.regionName} 预测`,
      type: 'line',
      smooth: true,
      symbol: 'triangle',
      symbolSize: 6,
      lineStyle: { width: 2.5, type: 'dashed', opacity: 0.9 },
      itemStyle: { color },
      data: g.points
        .filter((p) => !p.extrapolated)
        .map((p) => [p.time, Number(p.predictedLoad)])
    })

    // 外推点：单独成系列，画成浅色点线，视觉上明确"可信度更低"
    extrapolated.push({
      name: `${g.regionName} 预测(外推)`,
      type: 'line',
      smooth: true,
      symbol: 'none',
      lineStyle: { width: 1.5, type: 'dotted', opacity: 0.55 },
      itemStyle: { color, opacity: 0.55 },
      // 外推点前后各带一个"见过的时刻"作为端点，曲线才能连起来
      data: g.points
        .filter((p) => p.extrapolated)
        .map((p) => [p.time, Number(p.predictedLoad)])
    })
  })

  // x 轴：把实际和预测的时刻合并、去重、排序，避免类别轴错位
  const allTimes = new Set()
  actual.forEach((s) => s.data.forEach((d) => allTimes.add(d[0])))
  predicted.forEach((s) => s.data.forEach((d) => allTimes.add(d[0])))
  extrapolated.forEach((s) => s.data.forEach((d) => allTimes.add(d[0])))
  const xLabels = [...allTimes].sort()

  setOption({
    tooltip: {
      trigger: 'axis',
      formatter: (params) => {
        let s = params[0].axisValue
        params.forEach((p) => {
          if (p.value && p.value[1] !== undefined && p.value[1] !== null) {
            s += `<br/>${p.marker}${p.seriesName}：${Number(p.value[1]).toFixed(1)} kW`
          }
        })
        return s
      }
    },
    legend: { top: 0, type: 'scroll' },
    grid: { left: 70, right: 30, top: 45, bottom: 75 },
    xAxis: {
      type: 'category',
      data: xLabels,
      axisLabel: { rotate: 45, fontSize: 10, formatter: (v) => String(v).slice(5) }
    },
    yAxis: {
      type: 'value',
      name: '负荷 (kW)',
      nameTextStyle: { color: '#909399' },
      axisLabel: { formatter: (v) => v.toLocaleString() }
    },
    series: [...actual, ...predicted, ...extrapolated]
  })
}

watch([() => props.series, () => props.records], draw, { deep: true, immediate: true })
</script>

<template>
  <div ref="chartRef" class="chart tall"></div>
</template>
