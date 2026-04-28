import Link from "next/link";

const links = [
    { href: "/how-it-works/", label: "How it works" },
    { href: "/install/",      label: "Install" },
    { href: "/docs/",         label: "Docs" },
    { href: "/community/",    label: "Community" },
];

export function Nav() {
    return (
        <header
            className="sticky top-0 z-10 backdrop-blur"
            style={{
                background: "color-mix(in srgb, var(--bg) 85%, transparent)",
                borderBottom: "1px solid var(--line)",
            }}
        >
            <nav className="max-w-3xl mx-auto px-6 h-14 flex items-center gap-6">
                <Link
                    href="/"
                    className="font-semibold tracking-tight hover:opacity-80 transition-opacity"
                    style={{ color: "var(--strong)" }}
                >
                    IntelNav
                </Link>
                <ul className="flex gap-5 text-sm" style={{ color: "var(--muted)" }}>
                    {links.map((l) => (
                        <li key={l.href}>
                            <Link
                                href={l.href}
                                className="hover:underline underline-offset-4"
                            >
                                {l.label}
                            </Link>
                        </li>
                    ))}
                </ul>
                <div className="flex-1" />
                <a
                    href="https://github.com/IntelNav/intelnav"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm hover:underline underline-offset-4"
                    style={{ color: "var(--accent)" }}
                >
                    GitHub →
                </a>
            </nav>
        </header>
    );
}
