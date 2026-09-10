import { useState, type InputHTMLAttributes } from 'react'
import { Eye, EyeOff } from 'lucide-react'

// Bare password input + show/hide toggle, matching LoginScreen's own inline
// pattern -- extracted here because the credentials/reset-password/
// change-password forms below need the exact same thing three more times.
export function PasswordField(props: InputHTMLAttributes<HTMLInputElement>) {
  const [show, setShow] = useState(false)
  return (
    <span className="password-field">
      <input {...props} type={show ? 'text' : 'password'} />
      <button type="button" aria-label={show ? 'Nascondi password' : 'Mostra password'} onClick={() => setShow((value) => !value)}>
        {show ? <EyeOff size={17} /> : <Eye size={17} />}
      </button>
    </span>
  )
}
