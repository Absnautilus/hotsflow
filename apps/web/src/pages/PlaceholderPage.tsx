type PlaceholderPageProps = { title: string }

export function PlaceholderPage({ title }: PlaceholderPageProps) {
  return (
    <div className="page-stack">
      <section className="page-heading">
        <p className="eyebrow">Hotsflow</p>
        <h1>{title}</h1>
        <p className="page-subtitle">Questo spazio accoglierà le funzioni del modulo quando saranno disponibili per la struttura.</p>
      </section>
      <section className="empty-state"><span>Non ancora disponibile</span></section>
    </div>
  )
}
