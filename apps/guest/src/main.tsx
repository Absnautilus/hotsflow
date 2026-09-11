import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { App } from './App'
import { ErrorBoundary } from '@/components/error-boundary'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <div className="hk-root hk-root--standalone">
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
    </div>
  </StrictMode>,
)
