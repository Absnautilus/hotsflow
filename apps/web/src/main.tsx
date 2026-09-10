import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { App } from './app/App'
import { ModuleRuntimeProvider } from './core/ModuleRuntimeContext'
import './styles.css'
import './shell-effects.css'
import './shell-completion.css'

document.documentElement.setAttribute('data-theme', 'light')

const root = document.getElementById('root')
if (!root) throw new Error('Root element not found')

createRoot(root).render(
  <StrictMode>
    <BrowserRouter>
      <ModuleRuntimeProvider>
        <App />
      </ModuleRuntimeProvider>
    </BrowserRouter>
  </StrictMode>,
)
