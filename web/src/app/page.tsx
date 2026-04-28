"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import { Hero } from "@/components/Hero";
import { Typewriter } from "@/components/Typewriter";
import { TerminalMock, TerminalLine } from "@/components/TerminalMock";
import { NetworkGraph } from "@/components/NetworkGraph";

export default function Home() {
    return (
        <>
            <Hero />
            <Tagline />
            <LiveDemo />
            <NetworkSection />
            <Features />
            <InstallStrip />
        </>
    );
}

/* ────────────────────────────────────────────────────────────────── */
/* A single big quote-style tagline, breathing room. Sets pace
   between the hero and the dense terminal section. */
function Tagline() {
    return (
        <section className="max-w-4xl mx-auto px-6 py-32 sm:py-44 text-center">
            <motion.p
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-100px" }}
                transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
                className="font-serif text-3xl sm:text-4xl lg:text-5xl leading-[1.15] tracking-tight"
                style={{ color: "var(--strong)" }}
            >
                Everyone running a node holds <em className="italic" style={{ color: "var(--accent)" }}>part of a model</em>.
                Together, they hold them all.
            </motion.p>
        </section>
    );
}

/* ────────────────────────────────────────────────────────────────── */

function LiveDemo() {
    return (
        <section className="relative max-w-6xl mx-auto px-6 py-24 sm:py-32">
            <SectionHeader
                eyebrow="Two binaries, one chain"
                title="Chat from one terminal. Host from another."
                lede={
                    <>
                        <code>intelnav</code> is the chat client.{" "}
                        <code>intelnav-node</code> is the host daemon. They share
                        an identity but run as separate processes — closing the
                        chat doesn&apos;t take your slices off the network.
                    </>
                }
            />

            <div className="grid lg:grid-cols-2 gap-6">
                <TerminalMock title="islam@laptop ~ — intelnav">
                    <TerminalLine tag="sys" tone="muted">
                        Welcome to intelnav 0.1.0 · proto v1.
                    </TerminalLine>
                    <TerminalLine tag="sys" tone="muted">
                        peer 12D3KooW…uizeh reading the DHT.
                    </TerminalLine>
                    <div className="h-2" />
                    <TerminalLine tag="you" tone="accent">
                        write a rust function that reverses a string
                    </TerminalLine>
                    <div className="h-2" />
                    <TerminalLine tag="qwen">
                        <Typewriter
                            text={`fn reverse(s: &str) -> String {\n    s.chars().rev().collect()\n}`}
                            delay={26}
                        />
                    </TerminalLine>
                </TerminalMock>

                <TerminalMock title="islam@laptop ~ — intelnav-node" delay={0.15}>
                    <TerminalLine tag="INFO" tone="success">
                        libp2p node up · /ip4/0.0.0.0/tcp/4001
                    </TerminalLine>
                    <TerminalLine tag="INFO" tone="success">
                        DHT announces published n=2
                    </TerminalLine>
                    <TerminalLine tag="INFO" tone="muted">
                        bootstrap: dialed seed1.intelnav.net:4001
                    </TerminalLine>
                    <div className="h-2" />
                    <TerminalLine tag="peer" tone="accent">
                        accepted chain · cid=AEaibo2n…  layers [0..7)
                    </TerminalLine>
                    <TerminalLine tag="peer" tone="muted">
                        forward 12 → 24 (28 ms)
                    </TerminalLine>
                    <TerminalLine tag="peer" tone="muted">
                        forward 24 → 48 (29 ms)
                    </TerminalLine>
                    <TerminalLine tag="peer" tone="muted">
                        <Typewriter
                            text={[
                                "forward 48 → 96 (28 ms)",
                                "forward 96 → 144 (30 ms)",
                                "forward 144 → 192 (29 ms)",
                                "forward 192 → 240 (28 ms)",
                            ]}
                            delay={20}
                            pause={1400}
                        />
                    </TerminalLine>
                </TerminalMock>
            </div>
        </section>
    );
}

/* ────────────────────────────────────────────────────────────────── */

function NetworkSection() {
    return (
        <section className="max-w-6xl mx-auto px-6 py-24 sm:py-32">
            <SectionHeader
                eyebrow="The chain"
                title="A model is a chain of layers. So is the network."
                lede={
                    <>
                        Hidden states travel from your machine through every peer
                        that owns a slice of the model, in order, until the tail
                        produces a token. Each hop is TCP + Noise + yamux; each
                        peer&apos;s place is found via Kademlia.
                    </>
                }
            />
            <NetworkGraph />
        </section>
    );
}

/* ────────────────────────────────────────────────────────────────── */

function Features() {
    return (
        <section className="max-w-6xl mx-auto px-6 py-24 sm:py-28">
            <SectionHeader
                eyebrow="Architecture"
                title="Built so the cost of joining stays small."
                lede={null}
            />
            <div className="grid md:grid-cols-2 gap-4">
                {features.map((f, i) => (
                    <FeatureCard key={f.title} feature={f} delay={i * 0.06} />
                ))}
            </div>
        </section>
    );
}

function FeatureCard({
    feature,
    delay,
}: {
    feature: { title: string; body: string; tag: string };
    delay: number;
}) {
    return (
        <motion.div
            initial={{ y: 16, opacity: 0 }}
            whileInView={{ y: 0, opacity: 1 }}
            viewport={{ once: true, margin: "-50px" }}
            transition={{ duration: 0.55, delay, ease: [0.16, 1, 0.3, 1] }}
            whileHover={{ y: -2 }}
            className="rounded-2xl p-6 transition-colors group"
            style={{
                background: "var(--panel)",
                border: "1px solid var(--line)",
            }}
        >
            <p
                className="text-xs tracking-[0.2em] uppercase mb-3 font-mono transition-colors"
                style={{ color: "var(--accent)" }}
            >
                {feature.tag}
            </p>
            <h3
                className="font-serif text-xl mb-2 tracking-tight"
                style={{ color: "var(--strong)" }}
            >
                {feature.title}
            </h3>
            <p style={{ color: "var(--muted)" }}>{feature.body}</p>
        </motion.div>
    );
}

const features = [
    {
        tag: "01",
        title: "Pipeline-parallel",
        body: "Each peer owns a contiguous layer range. Hidden states forward through every hop until the head produces a token.",
    },
    {
        tag: "02",
        title: "Kademlia DHT",
        body: "Provider records advertise (model_cid, layer_range). Clients fan out per-range lookups to assemble a chain on demand.",
    },
    {
        tag: "03",
        title: "Mandatory contribution",
        body: "Every peer hosts a slice or relays DHT routing. No leech mode — the network only works because everyone commits.",
    },
    {
        tag: "04",
        title: "Two binaries",
        body: "intelnav is the chat client. intelnav-node is the host daemon. Closing chat doesn't drop your slices.",
    },
];

/* ────────────────────────────────────────────────────────────────── */

function InstallStrip() {
    return (
        <section className="relative max-w-6xl mx-auto px-6 py-20 my-16">
            <div
                className="rounded-3xl px-6 py-16 sm:px-12 sm:py-24 text-center relative overflow-hidden"
                style={{
                    background: "var(--panel)",
                    border: "1px solid var(--line)",
                }}
            >
                <motion.div
                    initial={{ opacity: 0, scale: 0.9 }}
                    whileInView={{ opacity: 1, scale: 1 }}
                    viewport={{ once: true }}
                    transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
                    className="absolute inset-0 -z-10 grid-bg"
                    style={{ opacity: 0.6 }}
                />
                <h2
                    className="font-serif text-3xl sm:text-4xl lg:text-5xl leading-tight tracking-tight max-w-2xl mx-auto"
                    style={{ color: "var(--strong)" }}
                >
                    Three lines on Linux. Pick a slice. Chat.
                </h2>
                <pre
                    className="mt-10 mx-auto max-w-xl text-left rounded-md px-5 py-4 text-[13px] leading-relaxed font-mono overflow-x-auto"
                    style={{
                        background: "var(--bg)",
                        border: "1px solid var(--line)",
                        color: "var(--fg)",
                    }}
                >
                    <span style={{ color: "var(--faint)" }}>$ </span>curl -fsSL https://intelnav.net/install.sh | sh{"\n"}
                    <span style={{ color: "var(--faint)" }}>$ </span>intelnav{"\n"}
                    <span style={{ color: "var(--faint)" }}>$ </span><span style={{ color: "var(--accent)" }}>/models</span>   <span style={{ color: "var(--faint)" }}># press &apos;c&apos; on a row to host</span>
                </pre>
                <div className="mt-10 flex flex-wrap justify-center gap-3">
                    <Link
                        href="/install/"
                        className="px-5 py-3 rounded-full text-[15px] font-medium transition-all hover:scale-[1.03]"
                        style={{
                            background: "var(--accent)",
                            color: "#ffffff",
                            boxShadow: "0 8px 24px -8px rgba(99, 102, 241, 0.55)",
                        }}
                    >
                        Full install guide
                    </Link>
                    <a
                        href="https://github.com/IntelNav/intelnav"
                        target="_blank"
                        rel="noopener noreferrer"
                        className="px-5 py-3 rounded-full text-[15px] font-medium"
                        style={{
                            background: "transparent",
                            color: "var(--strong)",
                            border: "1px solid var(--line-2)",
                        }}
                    >
                        Source on GitHub →
                    </a>
                </div>
            </div>
        </section>
    );
}

/* ────────────────────────────────────────────────────────────────── */

function SectionHeader({
    eyebrow,
    title,
    lede,
}: {
    eyebrow: string;
    title: string;
    lede: React.ReactNode;
}) {
    return (
        <motion.div
            initial={{ y: 14, opacity: 0 }}
            whileInView={{ y: 0, opacity: 1 }}
            viewport={{ once: true, margin: "-100px" }}
            transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
            className="max-w-2xl mb-12"
        >
            <p
                className="text-[12px] tracking-[0.2em] uppercase mb-4 font-mono"
                style={{ color: "var(--accent)" }}
            >
                {eyebrow}
            </p>
            <h2
                className="font-serif text-3xl sm:text-4xl leading-tight tracking-tight"
                style={{ color: "var(--strong)" }}
            >
                {title}
            </h2>
            {lede && (
                <p className="mt-4 text-lg leading-relaxed" style={{ color: "var(--muted)" }}>
                    {lede}
                </p>
            )}
        </motion.div>
    );
}
