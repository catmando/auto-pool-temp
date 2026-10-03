# Recommenders turn a forecast plus a pool's settings into "set the heater to
# X°F now". Each strategy is a subclass of Recommenders::Base registered below;
# a pool picks one by key (pool.strategy). Add a new algorithm by writing a
# class with the same interface and adding it to REGISTRY — nothing else in the
# app needs to change.
module Recommenders
  def self.registry
    {
      "lookahead" => Lookahead,
      "linear" => Linear
    }
  end

  def self.keys = registry.keys

  def self.for(key)
    registry.fetch(key.to_s) { raise ArgumentError, "unknown strategy #{key.inspect}" }
  end
end
