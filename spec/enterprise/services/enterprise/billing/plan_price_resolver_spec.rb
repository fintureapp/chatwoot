require 'rails_helper'

describe Enterprise::Billing::PlanPriceResolver do
  subject(:resolver) { described_class.new(subscription: subscription, target_currency: 'brl') }

  let(:subscription) do
    Stripe::Subscription.construct_from(plan: { id: current_price_id, product: 'prod_business' })
  end

  before do
    create(:installation_config, name: 'CHATWOOT_CLOUD_PLANS', value: [
             { 'name' => 'Business', 'product_id' => ['prod_business'],
               'price_ids' => { 'usd' => %w[price_monthly_usd price_annual_usd], 'brl' => %w[price_monthly_brl price_annual_brl] } }
           ])
  end

  describe '#target_price_id' do
    context 'when the current price is the first (monthly) in its currency' do
      let(:current_price_id) { 'price_monthly_usd' }

      it 'maps to the same cadence in the target currency' do
        expect(resolver.target_price_id).to eq('price_monthly_brl')
      end
    end

    context 'when the current price is the second (annual) in its currency' do
      let(:current_price_id) { 'price_annual_usd' }

      it 'maps to the matching cadence rather than the first target price' do
        expect(resolver.target_price_id).to eq('price_annual_brl')
      end
    end

    context 'when the target currency is not configured for the plan' do
      let(:current_price_id) { 'price_monthly_usd' }

      before do
        InstallationConfig.find_by(name: 'CHATWOOT_CLOUD_PLANS').update!(value: [
                                                                           { 'name' => 'Business', 'product_id' => ['prod_business'],
                                                                             'price_ids' => { 'usd' => ['price_monthly_usd'] } }
                                                                         ])
      end

      it 'raises' do
        expect { resolver.target_price_id }.to raise_error(described_class::Error, I18n.t('errors.billing.currency_not_available_for_plan'))
      end
    end
  end

  describe '#plan' do
    let(:current_price_id) { 'price_monthly_usd' }

    it 'resolves the plan that owns the current price' do
      expect(resolver.plan['name']).to eq('Business')
    end
  end
end
