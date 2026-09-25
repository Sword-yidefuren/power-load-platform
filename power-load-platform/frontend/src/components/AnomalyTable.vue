<script setup>
/**
 * 明细表格：全部负荷记录
 *
 * 为什么图都有了还要表格？
 *   图用来"看趋势"，表格用来"查具体值"。真实的数据平台两者都要有 ——
 *   领导看到图上有个尖峰，下一步一定是问"哪个地区、几点钟、多少度电"。
 *
 * 这个组件顺便演示了 Vue 里最常用的东西：v-for 渲染列表 + 计算属性过滤。
 */
import { computed } from 'vue'

const props = defineProps({
  records: { type: Array, default: () => [] }
})

/**
 * computed（计算属性）：它和普通函数的区别是"会缓存"。
 * records 没变时，反复读 filtered 不会重新计算。
 * 如果用 methods，每次重新渲染都会算一遍 —— 数据量大时很浪费。
 */
const filtered = computed(() => {
  // 这里只做"异常点排前面"的处理，让面试官一眼看到异常检测结果
  return [...props.records].sort((a, b) => {
    if (a.isAnomaly !== b.isAnomaly) return b.isAnomaly - a.isAnomaly
    return a.id - b.id
  })
})

/** 格式化数字，保留 1 位小数并加千分位 */
function fmt(v) {
  if (v === null || v === undefined) return '-'
  return Number(v).toLocaleString(undefined, {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1
  })
}

/** 把 "2026-09-23T14:00:00" 显示成 "2026-09-23 14:00" */
function fmtTime(ts) {
  if (!ts) return '-'
  return String(ts).replace('T', ' ').slice(0, 16)
}
</script>

<template>
  <div class="card">
    <h2>负荷明细数据</h2>
    <div class="hint">
      共 {{ filtered.length }} 条 · 异常点排在前面 · 数据来自 /api/load-records
    </div>

    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>地区</th>
          <th>采样时刻</th>
          <th style="text-align: right">负荷 (kW)</th>
          <th style="text-align: right">气温 (℃)</th>
          <th>状态</th>
        </tr>
      </thead>
      <tbody>
        <!--
          v-for 是 Vue 的循环渲染。
          :key 非常重要：它让 Vue 知道"哪一行是哪一行"，
          没有 key（或用下标当 key）在做增删排序时会出现"内容串行"的 bug。
        -->
        <tr v-for="row in filtered" :key="row.id">
          <td>{{ row.id }}</td>
          <td>{{ row.regionName }}</td>
          <td>{{ fmtTime(row.ts) }}</td>
          <td class="num">{{ fmt(row.loadKw) }}</td>
          <td class="num">{{ row.temperature === null ? '-' : fmt(row.temperature) }}</td>
          <td>
            <span v-if="row.isAnomaly === 1" class="tag danger">异常</span>
            <span v-else class="tag">正常</span>
          </td>
        </tr>
        <tr v-if="!filtered.length">
          <td colspan="6" style="text-align: center; color: #909399">没有数据</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
