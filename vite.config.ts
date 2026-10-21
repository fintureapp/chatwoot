import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

// Finture local Docker (docs/LOCAL_DEVELOPMENT.md):
// - VITE_USE_POLLING=true: bind mounts do Windows não emitem eventos inotify.
// - VITE_ALLOWED_HOSTS: o Rails faz proxy dos assets usando o host "vite".
const usePolling = process.env.VITE_USE_POLLING === 'true';
const allowedHosts = (process.env.VITE_ALLOWED_HOSTS || '')
  .split(',')
  .map(host => host.trim())
  .filter(Boolean);

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
  server: {
    ...(allowedHosts.length ? { allowedHosts } : {}),
    ...(usePolling ? { watch: { usePolling: true, interval: 300 } } : {}),
  },
});
