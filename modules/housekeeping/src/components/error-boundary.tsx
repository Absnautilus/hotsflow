import { Component, type ReactNode } from 'react'

export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  override state: { error: Error | null } = { error: null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  override componentDidCatch(error: Error, info: { componentStack: string }) {
    console.error('Unhandled error in the tree:', error, info.componentStack)
  }

  override render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <div className="w-full max-w-sm rounded-lg border border-line bg-surface p-8 text-center shadow-md">
          <div className="mx-auto mb-4 flex h-13 w-13 items-center justify-center rounded-full bg-bad-bg text-bad-ink">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 7h16" />
              <path d="M10.3 3.9 2 18a2 2 0 0 0 1.7 3h16.6a2 2 0 0 0 1.7-3L14 3.9a2 2 0 0 0-3.4 0Z" />
              <path d="M12 9v4M12 17h.01" />
            </svg>
          </div>
          <p className="font-head text-[0.96875rem] font-extrabold text-foreground">Qualcosa non ha funzionato</p>
          <p className="mt-2 text-xs leading-relaxed text-muted">
            {this.state.error.message || 'Errore imprevisto.'} Ricarica la pagina; se continua, segnalalo così com'è.
          </p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-5 w-full cursor-pointer rounded-sm bg-accent px-4 py-2.5 text-sm font-bold text-accent-ink hover:brightness-[1.06]"
          >
            Ricarica
          </button>
        </div>
      </div>
    )
  }
}
