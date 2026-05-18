/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

/**
 * API client for BeClinic Roles management.
 * BeClinic uses Chatwoot Teams as the underlying data model for roles.
 * Each team has beclinic_role (dono/gerente/especialista) and permissions (JSONB).
 */
class BeClinicRolesAPI extends ApiClient {
  constructor() {
    super('teams', { accountScoped: true });
  }

  // GET /api/v1/accounts/:account_id/teams — list all roles/teams
  getAll() {
    return axios.get(this.url);
  }

  // POST /api/v1/accounts/:account_id/teams — create a new role/team
  create(data) {
    return axios.post(this.url, data);
  }

  // PATCH /api/v1/accounts/:account_id/teams/:id — update a role/team
  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  // DELETE /api/v1/accounts/:account_id/teams/:id — delete a role/team
  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // GET /api/v1/accounts/:account_id/teams/:id/team_members — list members of a team
  getMembers(teamId) {
    return axios.get(`${this.url}/${teamId}/team_members`);
  }

  // POST /api/v1/accounts/:account_id/teams/:id/team_members — add member to team
  addMember(teamId, userId) {
    return axios.post(`${this.url}/${teamId}/team_members`, {
      user_ids: [userId],
    });
  }

  // DELETE /api/v1/accounts/:account_id/teams/:id/team_members — remove member from team
  removeMember(teamId, userId) {
    return axios.delete(`${this.url}/${teamId}/team_members`, {
      data: { user_ids: [userId] },
    });
  }
}

export default new BeClinicRolesAPI();
