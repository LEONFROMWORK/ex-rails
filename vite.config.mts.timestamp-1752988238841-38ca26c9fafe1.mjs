// vite.config.mts
import { defineConfig } from "file:///Users/kevin/excelapp-rails/node_modules/vite/dist/node/index.js";
import RubyPlugin from "file:///Users/kevin/excelapp-rails/node_modules/vite-plugin-ruby/dist/index.js";
import vue from "file:///Users/kevin/excelapp-rails/node_modules/@vitejs/plugin-vue/dist/index.mjs";
import path from "path";
var __vite_injected_original_dirname = "/Users/kevin/excelapp-rails";
var vite_config_default = defineConfig({
  plugins: [
    RubyPlugin(),
    vue()
  ],
  resolve: {
    alias: {
      "@": path.resolve(__vite_injected_original_dirname, "./app/javascript"),
      "~": path.resolve(__vite_injected_original_dirname, "./app/javascript")
    }
  },
  server: {
    hmr: {
      host: "localhost"
    }
  },
  build: {
    // Improve build performance
    rollupOptions: {
      output: {
        manualChunks: {
          "vue-vendor": ["vue", "vue-router", "pinia"],
          "ui-vendor": ["radix-vue", "class-variance-authority", "clsx", "tailwind-merge"]
        }
      }
    }
  }
});
export {
  vite_config_default as default
};
//# sourceMappingURL=data:application/json;base64,ewogICJ2ZXJzaW9uIjogMywKICAic291cmNlcyI6IFsidml0ZS5jb25maWcubXRzIl0sCiAgInNvdXJjZXNDb250ZW50IjogWyJjb25zdCBfX3ZpdGVfaW5qZWN0ZWRfb3JpZ2luYWxfZGlybmFtZSA9IFwiL1VzZXJzL2tldmluL2V4Y2VsYXBwLXJhaWxzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ZpbGVuYW1lID0gXCIvVXNlcnMva2V2aW4vZXhjZWxhcHAtcmFpbHMvdml0ZS5jb25maWcubXRzXCI7Y29uc3QgX192aXRlX2luamVjdGVkX29yaWdpbmFsX2ltcG9ydF9tZXRhX3VybCA9IFwiZmlsZTovLy9Vc2Vycy9rZXZpbi9leGNlbGFwcC1yYWlscy92aXRlLmNvbmZpZy5tdHNcIjtpbXBvcnQgeyBkZWZpbmVDb25maWcgfSBmcm9tICd2aXRlJ1xuaW1wb3J0IFJ1YnlQbHVnaW4gZnJvbSAndml0ZS1wbHVnaW4tcnVieSdcbmltcG9ydCB2dWUgZnJvbSAnQHZpdGVqcy9wbHVnaW4tdnVlJ1xuaW1wb3J0IHBhdGggZnJvbSAncGF0aCdcblxuZXhwb3J0IGRlZmF1bHQgZGVmaW5lQ29uZmlnKHtcbiAgcGx1Z2luczogW1xuICAgIFJ1YnlQbHVnaW4oKSxcbiAgICB2dWUoKSxcbiAgXSxcbiAgcmVzb2x2ZToge1xuICAgIGFsaWFzOiB7XG4gICAgICAnQCc6IHBhdGgucmVzb2x2ZShfX2Rpcm5hbWUsICcuL2FwcC9qYXZhc2NyaXB0JyksXG4gICAgICAnfic6IHBhdGgucmVzb2x2ZShfX2Rpcm5hbWUsICcuL2FwcC9qYXZhc2NyaXB0JyksXG4gICAgfSxcbiAgfSxcbiAgc2VydmVyOiB7XG4gICAgaG1yOiB7XG4gICAgICBob3N0OiAnbG9jYWxob3N0JyxcbiAgICB9LFxuICB9LFxuICBidWlsZDoge1xuICAgIC8vIEltcHJvdmUgYnVpbGQgcGVyZm9ybWFuY2VcbiAgICByb2xsdXBPcHRpb25zOiB7XG4gICAgICBvdXRwdXQ6IHtcbiAgICAgICAgbWFudWFsQ2h1bmtzOiB7XG4gICAgICAgICAgJ3Z1ZS12ZW5kb3InOiBbJ3Z1ZScsICd2dWUtcm91dGVyJywgJ3BpbmlhJ10sXG4gICAgICAgICAgJ3VpLXZlbmRvcic6IFsncmFkaXgtdnVlJywgJ2NsYXNzLXZhcmlhbmNlLWF1dGhvcml0eScsICdjbHN4JywgJ3RhaWx3aW5kLW1lcmdlJ10sXG4gICAgICAgIH0sXG4gICAgICB9LFxuICAgIH0sXG4gIH0sXG59KSJdLAogICJtYXBwaW5ncyI6ICI7QUFBcVEsU0FBUyxvQkFBb0I7QUFDbFMsT0FBTyxnQkFBZ0I7QUFDdkIsT0FBTyxTQUFTO0FBQ2hCLE9BQU8sVUFBVTtBQUhqQixJQUFNLG1DQUFtQztBQUt6QyxJQUFPLHNCQUFRLGFBQWE7QUFBQSxFQUMxQixTQUFTO0FBQUEsSUFDUCxXQUFXO0FBQUEsSUFDWCxJQUFJO0FBQUEsRUFDTjtBQUFBLEVBQ0EsU0FBUztBQUFBLElBQ1AsT0FBTztBQUFBLE1BQ0wsS0FBSyxLQUFLLFFBQVEsa0NBQVcsa0JBQWtCO0FBQUEsTUFDL0MsS0FBSyxLQUFLLFFBQVEsa0NBQVcsa0JBQWtCO0FBQUEsSUFDakQ7QUFBQSxFQUNGO0FBQUEsRUFDQSxRQUFRO0FBQUEsSUFDTixLQUFLO0FBQUEsTUFDSCxNQUFNO0FBQUEsSUFDUjtBQUFBLEVBQ0Y7QUFBQSxFQUNBLE9BQU87QUFBQTtBQUFBLElBRUwsZUFBZTtBQUFBLE1BQ2IsUUFBUTtBQUFBLFFBQ04sY0FBYztBQUFBLFVBQ1osY0FBYyxDQUFDLE9BQU8sY0FBYyxPQUFPO0FBQUEsVUFDM0MsYUFBYSxDQUFDLGFBQWEsNEJBQTRCLFFBQVEsZ0JBQWdCO0FBQUEsUUFDakY7QUFBQSxNQUNGO0FBQUEsSUFDRjtBQUFBLEVBQ0Y7QUFDRixDQUFDOyIsCiAgIm5hbWVzIjogW10KfQo=
