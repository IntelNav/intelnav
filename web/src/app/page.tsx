import Link from "next/link";
import { Code } from "@/components/Code";

export default function Home() {
    return (
        <article className="space-y-10">
            <header className="space-y-3">
                <h1
                    className="text-4xl sm:text-5xl font-bold tracking-tight"
                    style={{ color: "var(--strong)" }}
                >
                    IntelNav
                </h1>
                <p className="text-lg sm:text-xl" style={{ color: "var(--muted)" }}>
                    Decentralized, pipeline-parallel LLM inference.
                </p>
            </header>

            <pre
                className="overflow-x-auto px-5 py-4 rounded-md text-[13px] leading-relaxed font-mono"
                style={{
                    background: "var(--panel)",
                    border: "1px solid var(--line)",
                    color: "var(--muted)",
                }}
            >
{`prompt → [ you · layers 0..k ] → peer A · k..m → peer B · m..N → tokens`}
            </pre>

            <section className="space-y-4">
                <p>
                    IntelNav splits a model into layer-range slices, scatters them
                    across volunteer hardware, and streams hidden states through
                    the chain to answer a prompt. <strong>No single peer holds
                    the whole model.</strong> Slices are addressed on a Kademlia
                    DHT, prompts are encrypted end-to-end, and the only thing a
                    contributor commits to is the slice they have RAM for.
                </p>
                <p style={{ color: "var(--muted)" }}>
                    Every peer must contribute. You either host a slice or run as
                    a DHT relay. There is no leech mode — without contribution,
                    the network collapses into the people running it.
                </p>
            </section>

            <section className="space-y-3">
                <h2 className="text-xl font-semibold" style={{ color: "var(--strong)" }}>
                    Get it
                </h2>
                <p style={{ color: "var(--muted)" }}>
                    One-liner installer for Linux. macOS + Windows are on the
                    roadmap.
                </p>
                <Code prompt>{`curl -fsSL https://intelnav.net/install.sh | sh`}</Code>
                <p className="text-sm" style={{ color: "var(--muted)" }}>
                    Or build from source — see <Link href="/install/">Install</Link>.
                </p>
            </section>

            <section className="space-y-4">
                <h2 className="text-xl font-semibold" style={{ color: "var(--strong)" }}>
                    What you get
                </h2>
                <div className="grid gap-3 sm:grid-cols-2">
                    {features.map((f) => (
                        <div
                            key={f.title}
                            className="rounded-md p-4"
                            style={{ background: "var(--panel)", border: "1px solid var(--line)" }}
                        >
                            <h3 className="font-semibold mb-1" style={{ color: "var(--strong)" }}>
                                {f.title}
                            </h3>
                            <p className="text-sm" style={{ color: "var(--muted)" }}>
                                {f.body}
                            </p>
                        </div>
                    ))}
                </div>
            </section>

            <section className="flex flex-wrap gap-x-6 gap-y-2 text-sm pt-4">
                <Link href="/how-it-works/" className="hover:underline" style={{ color: "var(--accent)" }}>
                    How it works →
                </Link>
                <Link href="/install/" className="hover:underline" style={{ color: "var(--accent)" }}>
                    Install →
                </Link>
                <Link href="/docs/" className="hover:underline" style={{ color: "var(--accent)" }}>
                    Docs →
                </Link>
                <a
                    href="https://stats.uptimerobot.com/rhi8AeGmhy"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:underline"
                    style={{ color: "var(--accent)" }}
                >
                    Network status →
                </a>
            </section>
        </article>
    );
}

const features = [
    {
        title: "Pipeline-parallel",
        body: "Each peer owns a contiguous layer range. The chain forwards hidden states through every hop until the head produces a token.",
    },
    {
        title: "Kademlia DHT",
        body: "Provider records advertise (model_cid, layer_range). Clients fan out per-range lookups to assemble a chain on demand.",
    },
    {
        title: "Mandatory contribution",
        body: "Every peer hosts a slice or relays DHT routing. No leech mode — the network only works because everyone commits.",
    },
    {
        title: "Two binaries",
        body: "intelnav is the chat client. intelnav-node is the host daemon. Closing chat doesn't drop your slices.",
    },
];
