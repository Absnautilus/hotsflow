import type { ButtonHTMLAttributes } from 'react'
import { cn } from '@/lib/cn'

type Variant = 'primary' | 'secondary' | 'success' | 'warning' | 'danger' | 'ghost' | 'outline'
type Size = 'sm' | 'md'

const variants: Record<Variant, string> = {
  primary: 'border border-transparent bg-accent text-accent-ink hover:brightness-[1.06] active:brightness-[.92] disabled:opacity-45',
  // Canonical secondary is neutral. Purple communicates the primary action,
  // not simply "another clickable thing".
  secondary: 'border border-line-strong bg-surface text-foreground/75 hover:bg-surface-2 active:bg-line disabled:opacity-45',
  success: 'border border-line-strong bg-surface text-foreground/75 hover:bg-surface-2 disabled:opacity-45',
  warning: 'border border-line-strong bg-surface text-foreground/75 hover:bg-surface-2 disabled:opacity-45',
  danger: 'border border-bad-ink/25 bg-bad-bg text-bad-ink hover:bg-bad-ink/15 disabled:opacity-45',
  ghost: 'border border-transparent bg-transparent text-foreground/70 hover:bg-surface-2 active:bg-line disabled:opacity-45',
  outline: 'border border-line-strong bg-surface text-foreground/70 hover:bg-surface-2 active:bg-line disabled:opacity-45',
}

const sizes: Record<Size, string> = {
  sm: 'h-8 px-3 text-xs',
  md: 'h-11 px-[18px] text-[13.5px]',
}

const base =
  'inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-sm font-bold transition-[filter,background-color,border-color,box-shadow] disabled:cursor-not-allowed cursor-pointer'

export function Button({ variant = 'primary', size = 'md', className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: Size }) {
  return <button className={cn(base, variants[variant], sizes[size], className)} {...props} />
}
