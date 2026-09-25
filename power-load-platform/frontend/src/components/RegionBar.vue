<script setup>
/**
 * 柱状图：各地区平均负荷对比
 *
 * 数据来自后端 /api/stats/region-summary（第 5 步那个 GROUP BY 聚合接口）。
 *
 * 这个组件演示了"图表联动"：
 *   点柱子 -> emit('pick', 地区名) -> 父组件拿它去重新筛选折线图
 *
 * ★ 一个关键知识点：ECharts 上的点击不是 DOM 事件。
 *   你不能在 <div> 上写 @click 来知道"用户点了哪根柱子"，
 *   因为整张图对浏览器来说只是**一个 canvas 元素**，
 *   柱子并不是真实的 HTML 标签。
 *   必须拿到 ECharts 实例，用 chart.on('click', handler) 才行。
 */
import { onMounted, watch } from 'vue'
import { useECharts } from '../composables/useECharts'

const props = defineProps({
  summary: { type: Array, default: () => [] }
})

const emit = defineEmits(['pick'])

const { chartRef, setOption, getChart } = useECharts()

function draw() {
  const rows = props.summary || []
  if (!rows.length) return

  setOption({
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      formatter: (params) => {
        const i = params[0].dataIndex
        const d = rows[i]
        return (
          `<b>${d.regionName}</b><br/>` +
          `平均负荷：${Number(d.avgLoad).toFixed(2)} kW<br/>` +
          `峰值：${Number(d.maxLoad).toFixed(2)} kW<br/>` +
          `谷值：${Number(d.minLoad).toFixed(2)} kW<br/>` +
          `样本数：${d.sampleCount}<br/>` +
          `异常点：${d.anomalyCount}`
        )
      }
    },
    grid: { left: 70, right: 30, top: 20, bottom: 40 },
    xAxis: { type: 'category', data: rows.map((r) => r.regionName) },
    yAxis: {
      type: 'value',
      name: '平均负荷 (kW)',
      nameTextStyle: { color: '#909399' }
    },
    series: [
      {
        type: 'bar',
        barWidth: '45%',
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
          color: {
            type: 'linear',
            x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: '#5aa9ff' },
              { offset: 1, color: '#1f4e8c' }
            ]
          }
        },
        label: {
          show: true,
          position: 'top',
          formatter: (p) => Number(p.value).toFixed(0)
        },
        data: rows.map((r) => Number(r.avgLoad))
      }
    ]
  })
}

watch(() => props.summary, draw, { deep: true, immediate: true })

onMounted(() => {
  // 注意执行顺序：useECharts 内部的 onMounted 先跑（图表已 init），
  // 这里才轮到这个 onMounted，所以 getChart() 能拿到实例。
  const chart = getChart()
  if (!chart) return

  chart.on('click', (params) => {
    // params.dataIndex 是"第几根柱子"，用它反查是哪一行数据
    const row = (props.summary || [])[params.dataIndex]
    if (row) {
      emit('pick', row.regionName)
    }
  })
})
</script>

<template>
  <div ref="chartRef" class="chart"></div>
</template>
