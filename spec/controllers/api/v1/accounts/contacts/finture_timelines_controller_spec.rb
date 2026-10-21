require 'rails_helper'

# Linha do tempo do contato (modal do Histórico do Kanban SDR e triagem IA).
RSpec.describe 'Contact Finture timeline API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'resumo_atendimentos' => 'Cliente recorrente.' }) }
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/finture_timeline" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'returns every conversation of the contact with opening, closing and summary' do
    won_at = 2.days.ago.to_i
    won = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 5.days.ago,
                                custom_attributes: { 'sdr_outcome' => 'won', 'sdr_outcome_at' => won_at })
    resolved = create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved,
                                     created_at: 3.days.ago, custom_attributes: { 'sdr_resumo' => 'Pediu 2ª via.' })
    resolved_at = 1.day.ago.change(usec: 0)
    create(:reporting_event, account: account, inbox: inbox, conversation: resolved,
                             name: 'conversation_resolved', created_at: resolved_at)
    open = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.hour.ago)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['contact']['resumo_atendimentos']).to eq('Cliente recorrente.')
    entries = body['payload'].index_by { |entry| entry['id'] }
    expect(body['payload'].pluck('id')).to eq([open.display_id, resolved.display_id, won.display_id])
    expect(entries[won.display_id]).to include('outcome' => 'won', 'closed_at' => won_at, 'kanban_type' => 'comercial')
    expect(entries[resolved.display_id]).to include('resumo' => 'Pediu 2ª via.', 'closed_at' => resolved_at.to_i)
    expect(entries[open.display_id]['closed_at']).to be_nil
  end

  it 'returns the contact card fields and the agents who handled the contact' do
    contact.update!(additional_attributes: { 'company_name' => 'Embracon', 'city' => 'Nova Iguaçu', 'country' => 'Brasil' })
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent, created_at: 3.days.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent, created_at: 2.days.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: admin, created_at: 1.day.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact)

    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['contact']).to include('company_name' => 'Embracon', 'city' => 'Nova Iguaçu', 'country' => 'Brasil')
    expect(body['contact']['created_at']).to eq(contact.created_at.to_i)
    agents = body['agents'].index_by { |entry| entry['id'] }
    expect(agents.keys).to contain_exactly(agent.id, admin.id)
    expect(agents[agent.id]).to include('name' => agent.name, 'count' => 2)
    expect(agents[admin.id]).to include('count' => 1)
    expect(body['payload'].pluck('assignee_id')).to eq([nil, admin.id, agent.id, agent.id])
  end

  it 'hides conversations from inboxes the agent cannot access' do
    visible = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:conversation, account: account, inbox: other_inbox, contact: contact)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].pluck('id')).to eq([visible.display_id])
  end

  it 'returns 404 for a contact from another account' do
    foreign = create(:contact)

    get "/api/v1/accounts/#{account.id}/contacts/#{foreign.id}/finture_timeline",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
