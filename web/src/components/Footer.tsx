export function Footer() {
    return (
        <footer
            className="mt-20"
            style={{ borderTop: "1px solid var(--line)" }}
        >
            <div
                className="max-w-3xl mx-auto px-6 py-8 flex flex-wrap gap-x-6 gap-y-2 items-center text-sm"
                style={{ color: "var(--faint)" }}
            >
                <span>Apache-2.0</span>
                <span>·</span>
                <a
                    href="https://github.com/IntelNav/intelnav"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:underline"
                >
                    github.com/IntelNav
                </a>
                <span>·</span>
                <a
                    href="https://stats.uptimerobot.com/rhi8AeGmhy"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:underline"
                >
                    network status
                </a>
                <div className="flex-1" />
                <span style={{ color: "var(--faint)" }}>
                    decentralized · pipeline · p2p
                </span>
            </div>
        </footer>
    );
}
