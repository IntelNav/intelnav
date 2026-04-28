import type { Config } from "tailwindcss";

const config: Config = {
    content: ["./src/**/*.{ts,tsx,mdx}"],
    darkMode: "media", // honour the OS preference; no JS toggle for v1
    theme: {
        extend: {
            fontFamily: {
                sans: [
                    "ui-sans-serif",
                    "system-ui",
                    "-apple-system",
                    "Segoe UI",
                    "Inter",
                    "sans-serif",
                ],
                mono: [
                    "ui-monospace",
                    "JetBrains Mono",
                    "Menlo",
                    "Monaco",
                    "Consolas",
                    "monospace",
                ],
            },
            colors: {
                ink: {
                    bg: "#0d1117",
                    panel: "#161b22",
                    line: "#30363d",
                    fg: "#c9d1d9",
                    strong: "#f0f6fc",
                    muted: "#8b949e",
                    faint: "#6e7681",
                    accent: "#58a6ff",
                },
                paper: {
                    bg: "#ffffff",
                    panel: "#f6f8fa",
                    line: "#d0d7de",
                    fg: "#1f2328",
                    strong: "#1f2328",
                    muted: "#57606a",
                    faint: "#6e7681",
                    accent: "#0969da",
                },
            },
        },
    },
    plugins: [],
};

export default config;
