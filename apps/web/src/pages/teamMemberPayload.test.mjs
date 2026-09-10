import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { buildTeamMemberUpdateInput } from './teamMemberPayload.ts'

const member = {
  profile: { id: 'profile-1', fullName: 'Ada', avatarUrl: null },
  membership: {
    id: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
    organizationId: null, roleId: 'role-1', status: 'active',
  },
  role: { id: 'role-1', slug: 'manager', displayName: 'Manager', scope: 'property', rank: 20 },
  jobTitle: null,
  employmentStatus: 'active',
}

function values(entries) {
  return { get: (name) => entries[name] ?? null }
}

describe('buildTeamMemberUpdateInput', () => {
  it('omits role and access status when editing yourself but keeps operational metadata', () => {
    assert.deepEqual(buildTeamMemberUpdateInput(member, 'property-1', 'profile-1', values({
      job: 'job-2', employmentStatus: 'inactive',
    })), {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      jobTitleId: 'job-2', employmentStatus: 'inactive',
    })
  })

  it('omits property-level membership edits for an organization-wide member', () => {
    const orgMember = {
      ...member,
      membership: { ...member.membership, propertyId: null, organizationId: 'org-1' },
    }
    assert.deepEqual(buildTeamMemberUpdateInput(orgMember, 'property-1', 'another-profile', values({
      job: '', employmentStatus: 'active',
    })), {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      jobTitleId: null, employmentStatus: 'active',
    })
  })

  it('includes the role when editing another direct member (access status is toggled separately, not via this form)', () => {
    assert.deepEqual(buildTeamMemberUpdateInput(member, 'property-1', 'admin-profile', values({
      role: 'role-2', job: '', employmentStatus: 'active',
    })), {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      roleId: 'role-2', jobTitleId: null, employmentStatus: 'active',
    })
  })

  it('omits the role when resubmitted unchanged, even for another direct member', () => {
    // assign_membership_role requires the new role's rank to be strictly
    // lower than the assigner's own -- resubmitting a same-rank member's
    // current role unchanged (e.g. saving after only editing job/status)
    // must not be sent as a "reassignment", or the whole save is rejected.
    assert.deepEqual(buildTeamMemberUpdateInput(member, 'property-1', 'admin-profile', values({
      role: 'role-1', job: '', employmentStatus: 'active',
    })), {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      jobTitleId: null, employmentStatus: 'active',
    })
  })

  it('never serializes missing controls as the strings null or undefined', () => {
    const payload = buildTeamMemberUpdateInput(member, 'property-1', 'profile-1', values({
      job: '', employmentStatus: 'active',
    }))
    assert.doesNotMatch(JSON.stringify(payload), /"(?:null|undefined)"/)
  })
})
