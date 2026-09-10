import { Navigate, Route, Routes } from 'react-router-dom'
import { ShellLayout } from '../components/ShellLayout'
import { HomePage } from '../pages/HomePage'
import { PlaceholderPage } from '../pages/PlaceholderPage'
import { TeamPage } from '../pages/TeamPage'
import { SettingsPage } from '../pages/SettingsPage'
import { ResetPasswordPage } from '../pages/ResetPasswordPage'
import { HousekeepingModuleGate } from '../modules/housekeeping/HousekeepingModuleGate'

export function App() {
  return (
    <Routes>
      {/* Outside ShellLayout on purpose: this page handles its own transient
          recovery session and must render before ModuleRuntimeContext's
          signed-in/profile/property checks ever get a say. */}
      <Route path="reimposta-password" element={<ResetPasswordPage />} />
      <Route element={<ShellLayout />}>
        <Route index element={<HomePage />} />
        <Route path="housekeeping/*" element={<HousekeepingModuleGate />} />
        <Route path="turni" element={<PlaceholderPage title="Turni" />} />
        <Route path="transfer" element={<PlaceholderPage title="Transfer" />} />
        <Route path="modules" element={<PlaceholderPage title="Moduli" />} />
        <Route path="team" element={<TeamPage />} />
        <Route path="settings" element={<SettingsPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
