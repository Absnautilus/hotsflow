// The shared vocabulary a module uses to declare itself — a type only, not a
// runtime plugin system. Modules stay real, independently deployed
// applications in Phase 1 (see the Architecture Proposal, section H); this
// just gives them a common shape to describe themselves in, so a future
// registration step (or just documentation) has something typed to point
// at. The actual "is this module known to the platform" answer always comes
// from a row in the `modules` table, not from anything here.
export type { ModuleDescriptor } from './types/domain'
