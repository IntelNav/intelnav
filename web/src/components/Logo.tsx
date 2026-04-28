"use client";

import { motion } from "framer-motion";

/** The IntelNav mark. Renders /public/logo.svg directly via <img>
 * — the static-export build doesn't ship next/image's optimization
 * endpoint, so there's nothing gained by routing through it. */
export function Logo({
    size = 32,
    animated = false,
    className,
}: {
    size?: number;
    animated?: boolean;
    /** Reserved for future fetchpriority preload — current Next + img
     * tag don't accept fetchpriority cleanly across types. */
    priority?: boolean;
    className?: string;
}) {
    if (animated) {
        return (
            <motion.img
                src="/logo.svg"
                alt="IntelNav"
                width={size}
                height={size}
                className={className}
                draggable={false}
                initial={{ opacity: 0, scale: 0.94, rotate: -6 }}
                animate={{ opacity: 1, scale: 1, rotate: 0 }}
                transition={{ duration: 0.9, ease: [0.16, 1, 0.3, 1] }}
            />
        );
    }
    // eslint-disable-next-line @next/next/no-img-element
    return (
        <img
            src="/logo.svg"
            alt="IntelNav"
            width={size}
            height={size}
            className={className}
            draggable={false}
        />
    );
}
