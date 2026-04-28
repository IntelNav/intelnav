"use client";

import { useState, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";

/** A shell-snippet code block with a copy-to-clipboard button on the
 * right. Click → writes `text` to the clipboard, swaps the icon for a
 * "Copied" check that fades back to the icon after 1.5 s. Modeled on
 * the `npm i -g …` block on claude.ai's lp.
 *
 * Pass the user-visible string in `text`; the prompt `$` is rendered
 * separately (as a faint marker) and is NOT copied — the same way
 * Claude's, GitHub's, etc. handle it. */
export function CopyableShell({
    text,
    label,
    className,
}: {
    text: string;
    /** Optional aria-label override; defaults to the text itself. */
    label?: string;
    className?: string;
}) {
    const [copied, setCopied] = useState(false);

    const onCopy = useCallback(async () => {
        try {
            await navigator.clipboard.writeText(text);
            setCopied(true);
            window.setTimeout(() => setCopied(false), 1500);
        } catch {
            // Fallback for older browsers / non-secure contexts.
            const ta = document.createElement("textarea");
            ta.value = text;
            ta.style.position = "fixed";
            ta.style.opacity = "0";
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand("copy"); setCopied(true); window.setTimeout(() => setCopied(false), 1500); } catch {}
            document.body.removeChild(ta);
        }
    }, [text]);

    return (
        <div
            className={`group relative inline-flex items-center gap-3 px-4 py-3 rounded-xl font-mono text-[14px] transition-colors ${className ?? ""}`}
            style={{
                background: "var(--panel)",
                border: "1px solid var(--line)",
                color: "var(--fg)",
                maxWidth: "100%",
            }}
        >
            <span style={{ color: "var(--faint)" }} className="select-none shrink-0">$</span>
            <code
                className="overflow-x-auto whitespace-nowrap select-all"
                style={{ color: "var(--strong)" }}
            >
                {text}
            </code>
            <button
                type="button"
                onClick={onCopy}
                aria-label={copied ? "Copied" : `Copy: ${label ?? text}`}
                className="shrink-0 ml-1 -mr-1 w-8 h-8 rounded-lg flex items-center justify-center transition-all hover:scale-105 active:scale-95"
                style={{
                    background: copied ? "var(--accent)" : "var(--panel-2)",
                    color:      copied ? "#ffffff"      : "var(--muted)",
                    border:    "1px solid var(--line)",
                }}
            >
                <AnimatePresence mode="wait" initial={false}>
                    {copied ? (
                        <motion.svg
                            key="check"
                            initial={{ scale: 0, opacity: 0 }}
                            animate={{ scale: 1, opacity: 1 }}
                            exit={{ scale: 0, opacity: 0 }}
                            transition={{ duration: 0.2 }}
                            width="14" height="14" viewBox="0 0 16 16" fill="none"
                            stroke="currentColor" strokeWidth="2.5"
                            strokeLinecap="round" strokeLinejoin="round"
                        >
                            <path d="M3 8.5L6.5 12L13 4.5" />
                        </motion.svg>
                    ) : (
                        <motion.svg
                            key="copy"
                            initial={{ scale: 0, opacity: 0 }}
                            animate={{ scale: 1, opacity: 1 }}
                            exit={{ scale: 0, opacity: 0 }}
                            transition={{ duration: 0.15 }}
                            width="14" height="14" viewBox="0 0 16 16" fill="none"
                            stroke="currentColor" strokeWidth="1.5"
                        >
                            <rect x="5"  y="5"  width="9"  height="9"  rx="1.5" />
                            <path d="M3 11V3.5A1.5 1.5 0 0 1 4.5 2H11" />
                        </motion.svg>
                    )}
                </AnimatePresence>
            </button>
            <AnimatePresence>
                {copied && (
                    <motion.span
                        initial={{ opacity: 0, y: 4 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0, y: -4 }}
                        transition={{ duration: 0.18 }}
                        className="absolute -top-7 right-2 text-[11px] font-mono tracking-wide px-2 py-1 rounded-md"
                        style={{
                            background: "var(--accent)",
                            color: "#ffffff",
                        }}
                    >
                        Copied
                    </motion.span>
                )}
            </AnimatePresence>
        </div>
    );
}
