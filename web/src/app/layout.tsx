import type { Metadata } from "next";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";
import "./globals.css";

export const metadata: Metadata = {
    metadataBase: new URL("https://intelnav.net"),
    title: {
        default: "IntelNav — decentralized, pipeline-parallel LLM inference",
        template: "%s · IntelNav",
    },
    description:
        "IntelNav splits a model into layer-range slices, scatters them across volunteer hardware, and streams hidden states through the chain to answer a prompt. No single peer holds the whole model.",
    openGraph: {
        title: "IntelNav",
        description:
            "Decentralized, pipeline-parallel LLM inference. No single peer holds the whole model.",
        url: "https://intelnav.net",
        siteName: "IntelNav",
        type: "website",
    },
    twitter: { card: "summary_large_image", title: "IntelNav" },
    icons: { icon: "/favicon.svg" },
};

export const viewport = {
    themeColor: [
        { media: "(prefers-color-scheme: light)", color: "#ffffff" },
        { media: "(prefers-color-scheme: dark)",  color: "#0d1117" },
    ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
    return (
        <html lang="en">
            <body className="antialiased">
                <Nav />
                <main className="max-w-3xl mx-auto px-6 py-12">{children}</main>
                <Footer />
            </body>
        </html>
    );
}
