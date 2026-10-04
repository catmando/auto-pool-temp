namespace :snapshots do
  desc "Save the forecast behind a past check as test data: snapshots:from_recommendation[ID,NAME]"
  task :from_recommendation, %i[id name] => :environment do |_, args|
    recommendation = Recommendation.find(args[:id])
    snapshot = ForecastSnapshot.from_recommendation!(recommendation, name: args[:name])
    puts "Saved snapshot #{snapshot.id}: #{snapshot.label}"
  end
end
