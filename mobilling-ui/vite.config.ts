import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return
          // Split heavy/independent vendor libs into their own chunks so the
          // main bundle stays small and the browser can cache them separately.
          // Split the heavy, independent libraries into their own cacheable
          // chunks. Each only depends on React (in `vendor`) one-directionally,
          // so no circular chunks form.
          if (id.includes('recharts') || id.includes('d3-')) return 'recharts'
          if (id.includes('framer-motion')) return 'framer-motion'
          if (id.includes('@tabler/icons-react')) return 'icons'
          if (id.includes('@mantine')) return 'mantine'
          // React core lives WITH the rest of vendor (router, query, axios,
          // dayjs, …). Keeping React and its consumers in one chunk avoids the
          // circular-chunk warning that splitting them apart produces.
          return 'vendor'
        },
      },
    },
  },
})
