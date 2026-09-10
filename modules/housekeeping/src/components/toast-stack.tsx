import type { Toast } from '@/hooks/use-toasts'
import { IconCheck, IconX } from '@/components/ui/action-icons'
import { IconButton } from '@/components/ui/icon-button'
import { useLocale } from '@/lib/i18n/locale-context'

export function ToastStack({ toasts, onDismiss }: { toasts: Toast[]; onDismiss: (id: string) => void }) {
  const { t } = useLocale()
  if (toasts.length === 0) return null
  return (
    <div className="fixed bottom-4 right-4 z-50 flex w-80 max-w-[calc(100vw-2rem)] flex-col gap-2">
      {toasts.map((toast) =>
        toast.card ? (
          <div key={toast.id} role="status" className="rounded-xl border border-line bg-surface p-3 text-sm text-foreground shadow-md">
            <p className="pr-1 font-semibold text-foreground">{toast.card.title}</p>
            <div className="mt-2 flex justify-end gap-2">
              <IconButton
                tone="hintCaution"
                icon={IconX}
                label={t('staff.row.reject')}
                onClick={() => {
                  toast.card?.onReject()
                  onDismiss(toast.id)
                }}
              />
              <IconButton
                tone="hintPositive"
                icon={IconCheck}
                label={t('staff.row.claim')}
                onClick={() => {
                  toast.card?.onAccept()
                  onDismiss(toast.id)
                }}
              />
            </div>
          </div>
        ) : (
          <div
            key={toast.id}
            role="status"
            className="flex items-start gap-2.5 rounded-xl border border-line bg-surface py-2.5 pl-3.5 pr-2 text-sm text-foreground shadow-sm"
          >
            {toast.tone === 'warning' ? (
              <svg className="mt-0.5 h-4 w-4 shrink-0 text-wait-ink" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 9v4M12 17h.01" />
                <path d="M10.3 3.9 2 18a2 2 0 0 0 1.7 3h16.6a2 2 0 0 0 1.7-3L14 3.9a2 2 0 0 0-3.4 0Z" />
              </svg>
            ) : (
              <svg className="mt-0.5 h-4 w-4 shrink-0 text-prog-ink" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round">
                <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" />
                <path d="M13.7 21a2 2 0 0 1-3.4 0" />
              </svg>
            )}
            <span className="flex-1 py-0.5">{toast.message}</span>
            <button
              type="button"
              onClick={() => onDismiss(toast.id)}
              className="shrink-0 cursor-pointer rounded-full p-1.5 text-muted hover:bg-surface-2 hover:text-foreground"
            >
              <IconX className="h-3.5 w-3.5" />
            </button>
          </div>
        ),
      )}
    </div>
  )
}
