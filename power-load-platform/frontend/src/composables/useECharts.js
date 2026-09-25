import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as echarts from 'echarts'

/**
 * 第 6 步 · 一个可复用的"图表"封装（Vue 里叫 composable，组合式函数）
 *
 * 为什么要封装？因为 ECharts 有 4 个固定的繁琐步骤，每个图都要写一遍：
 *   1. 页面渲染完成后拿到 DOM 节点
 *   2. echarts.init(节点) 初始化
 *   3. setOption(配置) 设置数据
 *   4. 组件销毁时 dispose() 释放，还要监听窗口缩放自适应
 *
 * 把它抽出来之后，写一个新图表只需要关心"配置长什么样"。
 *
 * 用法：
 *   const { chartRef, setOption } = useECharts()
 *   <template><div ref="chartRef" style="height:300px"></div></template>
 *   setOption({ xAxis: {...}, series: [...] })
 */
export function useECharts() {
  const chartRef = ref(null)
  let chart = null
  // 如果调用方在 onMounted 之前就调用了 setOption，先把配置暂存在这里，
  // 等图表初始化完成后补画上去。
  // 注意：必须声明在 onMounted 之前 —— let 有"暂时性死区"，
  // 声明在使用之后会直接抛 ReferenceError。
  let pendingOption = null

  // 窗口大小变化时让图表跟着变，否则拉大浏览器图表会留白
  function handleResize() {
    if (chart) chart.resize()
  }

  onMounted(() => {
    // onMounted 保证 DOM 已经渲染出来，此时 chartRef.value 才是真实节点
    if (chartRef.value) {
      chart = echarts.init(chartRef.value)
      window.addEventListener('resize', handleResize)
      // 初始化完成后立刻把已有配置画出来（如果调用方在 onMounted 之前就设了 option）
      if (pendingOption) {
        chart.setOption(pendingOption)
      }
    }
  })

  onBeforeUnmount(() => {
    // 页面切走时一定要释放，否则 ECharts 实例留在内存里泄漏
    window.removeEventListener('resize', handleResize)
    if (chart) {
      chart.dispose()
      chart = null
    }
  })

  /**
   * 设置/更新图表数据。
   * 关键参数 notMerge: true —— 不加它的话，ECharts 会把新旧配置"合并"，
   * 结果就是：你切换地区筛选时，旧的数据系列还留在图上，看起来像没刷新。
   * 这是新手最常踩的 ECharts 坑之一。
   */
  function setOption(option) {
    if (chart) {
      chart.setOption(option, true)
    } else {
      pendingOption = option
    }
  }

  /**
   * 把 ECharts 实例暴露出去。
   * 因为 ECharts 的事件（比如点柱子）不是 DOM 事件，不能写 @click，
   * 必须拿到实例调 chart.on('click', ...)。所以这里给一个 getter。
   */
  function getChart() {
    return chart
  }

  return { chartRef, setOption, getChart }
}

/** 一个共用的 ECharts 主题色，保证所有图表风格统一 */
export const COLORS = ['#409eff', '#67c23a', '#e6a23c', '#f56c6c', '#909399', '#9b59b6']
