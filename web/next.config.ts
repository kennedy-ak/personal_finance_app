import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // E2E runs its own server against the local Supabase stack; a separate
  // build directory lets it run alongside a normal `next dev`.
  distDir: process.env.NEXT_DIST_DIR || ".next",
  cacheComponents: true,
  partialPrefetching: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
