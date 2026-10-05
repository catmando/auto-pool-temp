# Pool party mode: warmer water for a time window. Each party is its own
# block on the dashboard; "Plan the party" creates or updates it.
class PoolPartiesController < ApplicationController
  def create
    save(current_pool.pool_parties.build)
  end

  def update
    save(current_pool.pool_parties.find(params[:id]))
  end

  def destroy
    current_pool.pool_parties.find(params[:id]).destroy
    redirect_to root_path(anchor: "party"), notice: "Pool party removed."
  end

  private

  def save(party)
    party.assign_from_form(**params.permit(:start_date, :start_time, :end_date, :end_time, :boost).to_h.symbolize_keys
                                .then { |p| p.merge(boost: p[:boost].to_i) })
    if party.errors.none? && party.save
      redirect_to root_path(anchor: "party"), notice: "Pool party planned for #{party.label}."
    else
      redirect_to root_path(anchor: "party"), alert: "Couldn't plan the party: #{party.errors.full_messages.to_sentence}"
    end
  end
end
