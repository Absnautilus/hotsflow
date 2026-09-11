import type { SVGProps } from 'react'

const paths: Record<string, string> = {
  bed: 'M3 18v-7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v7M3 18v2M21 18v2M3 14h18M7 11V9a2 2 0 0 1 2-2h1a2 2 0 0 1 2 2v2',
  shower: 'M6 3h9a3 3 0 0 1 3 3v1M4 9h16M8 13v1M12 13v1M16 13v1M8 17v1M12 17v1M16 17v1',
  sparkles: 'M12 3v4M12 17v4M4 12h4M16 12h4M6.5 6.5l2 2M15.5 15.5l2 2M17.5 6.5l-2 2M8.5 15.5l-2 2',
  wrench: 'M14.7 6.3a4 4 0 0 0-5.4 5.4L4 17v3h3l5.3-5.3a4 4 0 0 0 5.4-5.4l-2.83 2.83-2.12-2.12L14.7 6.3Z',
  briefcase: 'M4 8h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1ZM8 8V6a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 13h18',
  dots: 'M6 12h.01M12 12h.01M18 12h.01',
}

export function CategoryIcon({ icon, ...props }: { icon: string | null } & SVGProps<SVGSVGElement>) {
  const d = paths[icon ?? 'dots'] ?? paths.dots
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d={d} />
    </svg>
  )
}
