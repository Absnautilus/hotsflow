import { LogoMark } from '@/components/logo'
import { LanguageToggle } from '@/components/language-toggle'
import { TextSizeToggle } from '@/components/text-size-toggle'
import { useLocale } from '@/lib/i18n/locale-context'

export function PublicHeader({ onLogout }: { onLogout?: () => void }) {
  const { t } = useLocale()
  return (
    <div className="mx-auto w-full max-w-xl px-4 pt-6">
      <div className="flex items-center gap-1 rounded-full bg-accent py-1.5 pr-2 pl-3 text-white shadow-md">
        <span className="flex flex-1 items-center gap-2">
          <LogoMark className="h-5 w-5 text-white" mouthColor="var(--accent)" />
          <span className="font-head text-sm font-extrabold">RoomCall</span>
        </span>
        <TextSizeToggle dark align="right" />
        <LanguageToggle dark align="right" />
        {onLogout && (
          <button
            type="button"
            onClick={onLogout}
            aria-label={t('nav.logout')}
            title={t('nav.logout')}
            className="flex h-8 w-8 cursor-pointer items-center justify-center rounded-full text-white/70 hover:bg-white/10 hover:text-white"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4">
              <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
              <path d="M16 17l5-5-5-5" />
              <path d="M21 12H9" />
            </svg>
          </button>
        )}
      </div>
    </div>
  )
}
