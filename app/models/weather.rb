module Weather
  # The weather provider used app-wide. Swap here (or in tests) to change source.
  mattr_accessor :provider, default: OpenMeteo.new
end
