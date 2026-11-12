<template>
  <div class="relative flex w-full flex-col h-screen bg-surface">
    <!-- Header -->
    <Header :current-tab="currentTab" @change-tab="changeTab" />
    
    <!-- Main Content -->
    <main class="flex-1 flex overflow-hidden">
      <DownloadView v-show="currentTab === 'download'" />
      <HistoryView v-show="currentTab === 'history'" />
      <AboutView v-show="currentTab === 'about'" />
      <SettingsView v-show="currentTab === 'settings'" />
    </main>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import Header from './components/Header.vue'
import DownloadView from './components/DownloadView.vue'
import HistoryView from './components/HistoryView.vue'
import AboutView from './components/AboutView.vue'
import SettingsView from './components/SettingsView.vue'
import type { TabType } from './types'

const currentTab = ref<TabType>('download')

function changeTab(tab: TabType) {
  currentTab.value = tab
  // 通知子组件标签已切换
  window.dispatchEvent(new CustomEvent('tab-changed', { detail: tab }))
}

// 把链接拖进窗口：默认行为会让整个窗口跳转到该网页，改为填入链接输入框
function onDragOver(e: DragEvent) {
  e.preventDefault()
  if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy'
}

function onDrop(e: DragEvent) {
  const target = e.target as HTMLElement | null
  // 拖到输入框里时保留浏览器原生的插入文本行为
  if (target && (target.tagName === 'TEXTAREA' || target.tagName === 'INPUT')) return
  e.preventDefault()
  const dt = e.dataTransfer
  if (!dt) return
  const uriList = dt.getData('text/uri-list').split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#'))
  const text = (uriList[0] || dt.getData('text/plain') || '').trim()
  if (!text) return
  currentTab.value = 'download'
  window.dispatchEvent(new CustomEvent('url-dropped', { detail: text }))
}

window.addEventListener('dragover', onDragOver)
window.addEventListener('drop', onDrop)

// 监听跳转设置页事件
window.addEventListener('navigate-to-settings', () => {
  currentTab.value = 'settings'
})

// 监听菜单点击关于事件
let unsubscribeMenu: (() => void) | null = null

onMounted(() => {
  if (window.electronAPI?.onMenuShowAbout) {
    unsubscribeMenu = window.electronAPI.onMenuShowAbout(() => {
      currentTab.value = 'about'
    })
  }
})

onUnmounted(() => {
  if (unsubscribeMenu) {
    unsubscribeMenu()
  }
})
</script>

<style>
/* Material Symbols Outlined */
.material-symbols-outlined {
  font-family: 'Material Symbols Outlined';
  font-weight: normal;
  font-style: normal;
  font-size: 24px;
  line-height: 1;
  letter-spacing: normal;
  text-transform: none;
  display: inline-block;
  white-space: nowrap;
  word-wrap: normal;
  direction: ltr;
  -webkit-font-feature-settings: 'liga';
  -webkit-font-smoothing: antialiased;
  font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}
</style>
