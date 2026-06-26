require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) { create(:installation_config, { name: 'FB_APP_ID', value: 'TESTVALUE' }) }

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end
    end
  end

  describe 'POST /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:notice]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:success]).to be_blank

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'asks admins to restart web and worker processes for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_ENDPOINT: 'https://api.openai.com' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:success]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to be_blank
      end

      it 'allows Captain provider credentials to be configured' do
        sign_in(super_admin, scope: :super_admin)

        post '/super_admin/app_config?config=captain',
             params: {
               app_config: {
                 CAPTAIN_LLM_PROVIDER: 'openrouter',
                 CAPTAIN_ANTHROPIC_API_KEY: 'anthropic-key',
                 CAPTAIN_GEMINI_API_KEY: 'gemini-key',
                 CAPTAIN_LLM_OPENROUTER_API_KEY: 'openrouter-key'
               }
             }

        expect(response).to have_http_status(:found)
        expect(GlobalConfig.get('CAPTAIN_LLM_PROVIDER')['CAPTAIN_LLM_PROVIDER']).to eq('openrouter')
        expect(GlobalConfig.get('CAPTAIN_ANTHROPIC_API_KEY')['CAPTAIN_ANTHROPIC_API_KEY']).to eq('anthropic-key')
        expect(GlobalConfig.get('CAPTAIN_GEMINI_API_KEY')['CAPTAIN_GEMINI_API_KEY']).to eq('gemini-key')
        expect(GlobalConfig.get('CAPTAIN_LLM_OPENROUTER_API_KEY')['CAPTAIN_LLM_OPENROUTER_API_KEY']).to eq('openrouter-key')
      end

      it 'renders provider selection and RubyLLM provider fields for Captain settings' do
        sign_in(super_admin, scope: :super_admin)

        get '/super_admin/app_config?config=captain'

        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)

        expect(document.at_css('select[name="app_config[CAPTAIN_LLM_PROVIDER]"] option[value="openrouter"]')).to be_present
        expect(document.at_css('input[name="app_config[CAPTAIN_LLM_OPENROUTER_API_KEY]"]')).to be_present
      end
    end
  end
end
