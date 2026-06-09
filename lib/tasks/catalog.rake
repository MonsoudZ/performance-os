namespace :catalog do
  desc "Import the canonical exercise catalog"
  task import: :environment do
    count = ExerciseCatalogImporter.new.call
    puts "Imported #{count} exercises"
  end
end
