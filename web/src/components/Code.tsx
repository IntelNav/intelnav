import { ReactNode } from "react";

/** Code block container. We render shell sessions a lot, so the
 * `prompt` prop adds a leading `$` glyph in muted color. For copy-
 * pasteable single-liners pass `dim={false}` to keep all chars
 * full-strength. */
export function Code({
    children,
    prompt = false,
}: {
    children: ReactNode;
    prompt?: boolean;
}) {
    return (
        <pre
            className="text-[13px] leading-relaxed rounded-md overflow-x-auto px-4 py-3 my-4 font-mono"
            style={{
                background: "var(--panel)",
                border: "1px solid var(--line)",
                color: "var(--fg)",
            }}
        >
            {prompt ? <PromptedShell>{children}</PromptedShell> : children}
        </pre>
    );
}

/** Render each line with a faint `$` prompt prefix. Children must be
 * a string for this branch — multi-element shell snippets should be
 * passed line-by-line as plain text. */
function PromptedShell({ children }: { children: ReactNode }) {
    if (typeof children !== "string") return <>{children}</>;
    return (
        <>
            {children
                .split("\n")
                .filter((line, i, arr) => !(i === arr.length - 1 && line === ""))
                .map((line, i) => (
                    <span key={i} className="block">
                        <span style={{ color: "var(--faint)" }} className="select-none">
                            ${" "}
                        </span>
                        {line}
                    </span>
                ))}
        </>
    );
}
