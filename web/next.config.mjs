/** @type {import('next').NextConfig} */
const nextConfig = {
    // Static export. `next build` produces `out/` of plain HTML/JS that
    // drops onto any static host — in our case seed1's nginx at
    // /var/www/intelnav. No node runtime needed in production.
    output: 'export',

    // Append a trailing slash so nginx serves /install/ → /install/index.html
    // without a redirect dance.
    trailingSlash: true,

    // The static-export build doesn't ship the Next.js Image
    // optimization endpoint. Pre-resize anything we ship in /public.
    images: { unoptimized: true },
};

export default nextConfig;
