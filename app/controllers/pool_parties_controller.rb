# Pool party mode: warmer water for a time window.
class PoolPartiesController < ApplicationController
  def create
    party = PoolParty.build_for(current_pool, date: params[:date], start_time: params[:start_time],
                                              end_time: params[:end_time], boost: params[:boost].to_i)
    if party.errors.none? && party.save
      redirect_to root_path(anchor: "party"), notice: "Pool party set for #{party.label}."
    else
      redirect_to root_path(anchor: "party"), alert: "Couldn't set the party: #{party.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    current_pool.pool_parties.find(params[:id]).destroy
    redirect_to root_path(anchor: "party"), notice: "Pool party removed."
  end
end
