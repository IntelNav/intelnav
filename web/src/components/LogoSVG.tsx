"use client";

import { useEffect, useRef, useState } from "react";
import { gsap } from "gsap";

/** Hero-sized inlined logo with a GSAP path-trace reveal.
 *
 * Why inlined (rather than `<img src="/logo.svg">`): we need direct
 * access to every <path> to animate `strokeDashoffset`, `fillOpacity`
 * etc. An <img> is opaque to JS.
 *
 * The reveal is a three-phase GSAP timeline:
 *   1. trace — each path's outline draws itself in as an indigo
 *      stroke (stagger 0.025 s/path × 65 paths ≈ 1.6 s tail).
 *   2. fill — the indigo body blooms in (fillOpacity 0 → 1).
 *   3. settle — the stroke fades, leaving the filled mark.
 *
 * After the reveal the mark sits still. No float, no breath, no spin
 * — it's already done its work.
 */
export function LogoSVG({
    size = 360,
    className,
    /** Skip the reveal animation (useful for thumbnails / og previews). */
    instant = false,
}: {
    size?: number;
    className?: string;
    instant?: boolean;
}) {
    const containerRef = useRef<HTMLDivElement>(null);
    const [svgText, setSvgText] = useState<string | null>(null);

    // Phase 1 — load the SVG. We could inline it as JSX but the file
    // is 41 KB / 65 paths; the build-time inline turns the home page
    // chunk into a beast for no benefit. Fetch is cheap; same origin.
    useEffect(() => {
        let cancelled = false;
        fetch("/logo.svg")
            .then((r) => r.text())
            .then((text) => { if (!cancelled) setSvgText(text); })
            .catch(() => { /* SVG just won't render — better than throwing */ });
        return () => { cancelled = true; };
    }, []);

    // Phase 2 — once injected, prepare each path and run the GSAP
    // timeline. Skipped on `instant` (renders the final state).
    useEffect(() => {
        if (!svgText || !containerRef.current) return;
        const svg = containerRef.current.querySelector("svg");
        if (!svg) return;

        // Make the SVG fill its container (it ships with width="1024mm").
        svg.setAttribute("width", "100%");
        svg.setAttribute("height", "100%");

        const paths = Array.from(svg.querySelectorAll<SVGPathElement>("path"));

        // Pre-set every path: full dasharray = path length, offset =
        // length (invisible), fill transparent. Stroke uses
        // currentColor so the parent's `color` controls the indigo.
        paths.forEach((p) => {
            let len = 0;
            try {
                len = p.getTotalLength();
            } catch {
                // Pathologically broken paths don't expose a length;
                // skip the animation for those — they'll just appear
                // when their fillOpacity hits 1 below.
            }
            gsap.set(p, {
                strokeDasharray:  len,
                strokeDashoffset: len,
                fillOpacity:      0,
                stroke:           "currentColor",
                strokeWidth:      1.5,
                strokeOpacity:    instant ? 0 : 1,
            });
            if (instant) {
                gsap.set(p, { fillOpacity: 1, strokeDashoffset: 0 });
            }
        });

        if (instant) return;

        // Halo gets a brief intensity flare timed with the fill phase
        // — like the mark "lights up" the moment the strokes commit
        // to color. We grab the .logo-glow ancestor (set by Hero).
        const halo =
            containerRef.current.closest<HTMLElement>(".logo-glow") ?? null;

        // Slight final pose: settle scale down by 1 % so the mark
        // visibly "lands" at rest (rather than pose-locking on the
        // overshoot that the eased trace can leave).
        const tl = gsap.timeline({ delay: 0.4 });

        // Phase 1 — trace each path's outline. `each: 0.022` keeps
        // the trail tight (≈1.4 s end-to-end across 65 paths). Ease
        // chosen to feel like a brushstroke: slow start, fast tail.
        tl.to(paths, {
            strokeDashoffset: 0,
            duration: 1.5,
            ease: "power3.out",
            stagger: { each: 0.022, from: "start" },
        });

        // Phase 2 — fill blooms in behind the strokes, halo flares.
        tl.to(paths, {
            fillOpacity: 1,
            duration: 0.5,
            ease: "power1.in",
            stagger: { each: 0.014, from: "start" },
        }, "-=0.6");

        if (halo) {
            tl.fromTo(halo,
                { "--glow-boost": 0 } as gsap.TweenVars,
                {
                    "--glow-boost": 1,
                    duration: 0.55,
                    ease: "power2.out",
                    onComplete: () => {
                        gsap.to(halo, {
                            "--glow-boost": 0,
                            duration: 1.2,
                            ease: "power2.inOut",
                        } as gsap.TweenVars);
                    },
                } as gsap.TweenVars,
            "-=0.3");
        }

        // Phase 3 — strokes recede, mark settles into its final pose.
        tl.to(paths, {
            strokeOpacity: 0,
            duration: 0.6,
            ease: "power2.out",
        }, "-=0.2");

        return () => { tl.kill(); };
    }, [svgText, instant]);

    return (
        <div
            ref={containerRef}
            className={className}
            style={{
                width: size,
                height: size,
                color: "var(--accent)", // drives `currentColor` on each path's stroke
            }}
            // SSR-safe: empty until svgText loads, then dangerouslySet
            // wires up the inline tree. We could also pre-fetch in a
            // server component; not worth the orchestration today.
            dangerouslySetInnerHTML={svgText ? { __html: svgText } : undefined}
        />
    );
}
