import { createApp } from 'vue'
// 字体随应用打包，不依赖 Google Fonts（国内访问不到时图标会显示成英文单词）
import 'material-symbols/outlined.css'
import '@fontsource/inter/400.css'
import '@fontsource/inter/500.css'
import '@fontsource/inter/600.css'
import '@fontsource/inter/700.css'
import '@fontsource/plus-jakarta-sans/400.css'
import '@fontsource/plus-jakarta-sans/500.css'
import '@fontsource/plus-jakarta-sans/600.css'
import '@fontsource/plus-jakarta-sans/700.css'
import './style.css'
import App from './App.vue'

// 给 <html> 打上平台标记，CSS 用它给 macOS 红绿灯按钮留位置
document.documentElement.classList.add(`platform-${window.electronAPI?.platform ?? 'web'}`)

createApp(App).mount('#app')

// 通知 preload 移除启动加载遮罩（否则遮罩会挡住界面 5 秒）
window.postMessage({ payload: 'removeLoading' }, '*')
