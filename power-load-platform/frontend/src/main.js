import { createApp } from 'vue'
import App from './App.vue'
import './style.css'

// Vue 的启动入口：
//   1. 用 App.vue 作为根组件，创建应用
//   2. 挂载到 index.html 里的 <div id="app">
// createApp(App).mount('#app') 这一行就把"JS 对象"变成了"页面上的界面"
createApp(App).mount('#app')
