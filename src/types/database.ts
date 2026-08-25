// Hand-maintained to mirror supabase/migrations/0001-0007 exactly (verified
// against a local Postgres 16 instance with the full migration chain
// applied). This sandbox has no Docker available, which is what
// `supabase gen types typescript` needs to introspect a project — so this
// file was written by hand instead of generated.
//
// Once this repo is connected to a real Supabase project, regenerate it for
// real and this file becomes disposable:
//   npx supabase gen types typescript --project-id <ref> > src/types/database.ts
// (or --db-url <connection-string> against any reachable Postgres, local or
// hosted — no Docker needed once a real project/db exists to point at).
//
// Nothing outside src/types should import this file directly — see
// src/types/domain.ts and each module's own file for the mapped, stable
// shapes the rest of the SDK actually exposes.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export interface Database {
  public: {
    Tables: {
      organizations: {
        Row: {
          id: string
          name: string
          slug: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          slug: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      properties: {
        Row: {
          id: string
          organization_id: string
          name: string
          slug: string
          timezone: string
          status: string
          settings: Json
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          organization_id: string
          name: string
          slug: string
          timezone?: string
          status?: string
          settings?: Json
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          organization_id?: string
          name?: string
          slug?: string
          timezone?: string
          status?: string
          settings?: Json
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'properties_organization_id_fkey'
            columns: ['organization_id']
            isOneToOne: false
            referencedRelation: 'organizations'
            referencedColumns: ['id']
          },
        ]
      }
      modules: {
        Row: {
          id: string
          slug: string
          display_name: string
          status: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          slug: string
          display_name: string
          status?: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          slug?: string
          display_name?: string
          status?: string
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      property_modules: {
        Row: {
          id: string
          property_id: string
          module_id: string
          enabled: boolean
          plan: string | null
          settings: Json
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          property_id: string
          module_id: string
          enabled?: boolean
          plan?: string | null
          settings?: Json
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          property_id?: string
          module_id?: string
          enabled?: boolean
          plan?: string | null
          settings?: Json
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'property_modules_property_id_fkey'
            columns: ['property_id']
            isOneToOne: false
            referencedRelation: 'properties'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'property_modules_module_id_fkey'
            columns: ['module_id']
            isOneToOne: false
            referencedRelation: 'modules'
            referencedColumns: ['id']
          },
        ]
      }
      roles: {
        Row: {
          id: string
          slug: string
          display_name: string
          scope: string
          is_system: boolean
          created_at: string
        }
        Insert: {
          id?: string
          slug: string
          display_name: string
          scope: string
          is_system?: boolean
          created_at?: string
        }
        Update: {
          id?: string
          slug?: string
          display_name?: string
          scope?: string
          is_system?: boolean
          created_at?: string
        }
        Relationships: []
      }
      permissions: {
        Row: {
          id: string
          slug: string
          module_id: string | null
          created_at: string
        }
        Insert: {
          id?: string
          slug: string
          module_id?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          slug?: string
          module_id?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'permissions_module_id_fkey'
            columns: ['module_id']
            isOneToOne: false
            referencedRelation: 'modules'
            referencedColumns: ['id']
          },
        ]
      }
      role_permissions: {
        Row: {
          role_id: string
          permission_id: string
        }
        Insert: {
          role_id: string
          permission_id: string
        }
        Update: {
          role_id?: string
          permission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'role_permissions_role_id_fkey'
            columns: ['role_id']
            isOneToOne: false
            referencedRelation: 'roles'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'role_permissions_permission_id_fkey'
            columns: ['permission_id']
            isOneToOne: false
            referencedRelation: 'permissions'
            referencedColumns: ['id']
          },
        ]
      }
      profiles: {
        Row: {
          id: string
          full_name: string
          avatar_url: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          full_name: string
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          full_name?: string
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      memberships: {
        Row: {
          id: string
          profile_id: string
          property_id: string | null
          organization_id: string | null
          role_id: string
          status: string
          invited_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          profile_id: string
          property_id?: string | null
          organization_id?: string | null
          role_id: string
          status?: string
          invited_by?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          profile_id?: string
          property_id?: string | null
          organization_id?: string | null
          role_id?: string
          status?: string
          invited_by?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'memberships_profile_id_fkey'
            columns: ['profile_id']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'memberships_property_id_fkey'
            columns: ['property_id']
            isOneToOne: false
            referencedRelation: 'properties'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'memberships_organization_id_fkey'
            columns: ['organization_id']
            isOneToOne: false
            referencedRelation: 'organizations'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'memberships_role_id_fkey'
            columns: ['role_id']
            isOneToOne: false
            referencedRelation: 'roles'
            referencedColumns: ['id']
          },
        ]
      }
      guest_sessions: {
        Row: {
          id: string
          property_id: string
          reservation_id: string | null
          room_id: string | null
          guest_id: string | null
          verification_method: string
          verification_level: number
          token_hash: string
          issued_by_module_id: string | null
          expires_at: string
          revoked_at: string | null
          last_seen_at: string | null
          metadata: Json
          created_at: string
        }
        Insert: {
          id?: string
          property_id: string
          reservation_id?: string | null
          room_id?: string | null
          guest_id?: string | null
          verification_method: string
          verification_level: number
          token_hash: string
          issued_by_module_id?: string | null
          expires_at: string
          revoked_at?: string | null
          last_seen_at?: string | null
          metadata?: Json
          created_at?: string
        }
        Update: {
          id?: string
          property_id?: string
          reservation_id?: string | null
          room_id?: string | null
          guest_id?: string | null
          verification_method?: string
          verification_level?: number
          token_hash?: string
          issued_by_module_id?: string | null
          expires_at?: string
          revoked_at?: string | null
          last_seen_at?: string | null
          metadata?: Json
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'guest_sessions_property_id_fkey'
            columns: ['property_id']
            isOneToOne: false
            referencedRelation: 'properties'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'guest_sessions_issued_by_module_id_fkey'
            columns: ['issued_by_module_id']
            isOneToOne: false
            referencedRelation: 'modules'
            referencedColumns: ['id']
          },
        ]
      }
    }
    Views: Record<string, never>
    Functions: {
      has_property_access: {
        Args: { p_property_id: string }
        Returns: boolean
      }
      has_organization_access: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      has_permission: {
        Args: { p_property_id: string; p_permission_slug: string }
        Returns: boolean
      }
      has_organization_permission: {
        Args: { p_organization_id: string; p_permission_slug: string }
        Returns: boolean
      }
      has_module: {
        Args: { p_property_id: string; p_module_slug: string }
        Returns: boolean
      }
      guest_session_is_valid: {
        Args: { p_session_id: string; p_property_id: string; p_min_level: number }
        Returns: boolean
      }
    }
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
