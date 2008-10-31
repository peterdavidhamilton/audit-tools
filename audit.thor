# module: audit2
require '~/work/tools/towelie/lib/array'
require '~/work/tools/towelie/lib/towelie'
 
class Audit < Thor
  include Towelie

  desc "all", "Run all audit tasks"
  def all
    %w(architecture database stats tests coverage flog roodi filesize duplicated_code queries).each do |task|
      log "\n*** reviewing #{task}", true
      log `thor audit:#{task}`, true
    end
  end

  desc "queries", "Audit the SQL queries run during this Rails app's test."
  method_options :units => :boolean, :v => :boolean
  def queries
    File.unlink('log/test.log') if File.exist?('log/test.log')
    
    test_cmd = options['units'] ? "rake test:units" : "rake test"
    test_cmd += " 1> /dev/null 2>&1" unless options['v']
    
    if system(test_cmd)
      %w(SELECT INSERT UPDATE DELETE).each do |sql|
        puts "#{sql} statements: " + %x[grep #{sql} log/test.log | wc -l]
      end
    else
      puts "Error. Probably not in a Rails app. Try -v for details."
    end
  end
  
  desc "architecture", "Inspect and report on architectural decisions made for a given Rails application."
  def architecture
    log "\nRAILS", true
    if File.exists?("vendor/rails/railties/CHANGELOG")
      # TODO: determine revision of frozen Rails
      log "  Frozen v"
    else
      gem_rails = `gem list --local | grep "^rails ("`.scan(/\((.+)\)/).flatten
      log "  Gem v#{gem_rails}"
    end

    log "\nJAVASCRIPT", true
    log "  Prototype" if File.exists?("public/javascripts/prototype.js")
    # TODO: get prototype version from first line
    log "  jQuery" if File.exists?("public/javascripts/jquery.js")
    # TODO: get jquery version from second line
    
    log "\nTESTING FRAMEWORK", true
    log "  Test::Unit" if true
    log "  RSpec" if false
    
    log "\nPLUGINS", true
    plugins = Dir.glob('vendor/plugins/*')
    log "  none" if plugins.empty?
    plugins.each do |plugin|
      log "  #{plugin.sub('vendor/plugins/', '')}"
    end
    
    log "\nGEMS", true
    gems = `rake gems`.split(/\n/).select {|line| line =~ /^\[/}
    log "  none" if gems.empty?
    gems.each do |gem|
      status = gem =~ /\[F\]/ ? 'frozen' : ''
      log "  #{gem.gsub(/\[.\] /, '')} #{status}"
    end
  end
  
  desc "database", "Attempt to load database from scratch via migrations"
  # TODO: suppress errors in migrations
  def database
    created = `rake db:create:all`.chomp
    if created.split(/\n/).size == 1 
      log "\nDATABASE MIGRATION", true
      migrated = `rake db:migrate`
      log migrated.gsub(/\n/, "\n  ")
    else
      log "\nDATABASE CREATION FAILED"
    end
  end

  desc "stats", "Run rake stats for the application"
  def stats
    log `rake stats`
  end
  
  desc "tests", "Run tests for the application"
  def tests
    log `rake`
  end
  
  desc "coverage", "Run rcov for the application"
  def coverage
    log `rcov --rails -T --no-html --only-uncovered --sort coverage test/*/*_test.rb test/**/*_test.rb`
  end
  
  desc "flog", "Run flog on controllers and models"
  def flog
    controller_results = `find app/controllers -name \*.rb | xargs flagellate | grep ": ("`.select {|r| r.gsub(/.+\(/, '').sub(/\)/, '').to_i > 40.0}
    model_results      = `find app/models -name \*.rb | xargs flagellate | grep ": ("`.select {|r| r.gsub(/.+\(/, '').sub(/\)/, '').to_i > 40.0}
    helper_results     = `find app/helpers -name \*.rb | xargs flagellate | grep ": ("`.select {|r| r.gsub(/.+\(/, '').sub(/\)/, '').to_i > 40.0}
    lib_results        = `find lib -name \*.rb | xargs flagellate | grep ": ("`.select {|r| r.gsub(/.+\(/, '').sub(/\)/, '').to_i > 40.0}
    
    unless controller_results.empty?
      log "\nCONTROLLERS", true
      log '  ' + controller_results.join.chomp
    end

    unless helper_results.empty?
      log "\nHELPERS", true
      log '  ' + helper_results.join.chomp
    end

    unless model_results.empty?
      log "\nMODELS", true
      log '  ' + model_results.join.chomp
    end
    
    unless lib_results.empty?
      log "\nLIBRARIES", true
      log '  ' + lib_results.join.chomp
    end
  end
  
  desc "roodi", "Run roodi for the application"
  def roodi
    log "\nAPPLICATION CODE", true
    log `roodi "./app/**/*.rb"`

    log "\nLIBRARY CODE", true
    log `roodi "./lib/**/*.rb"`
  end
  
  desc "filesize", "Check for abnormally large or small files"
  def filesize
    controllers = `find app/controllers -name *.rb | xargs wc -l`
    small_controllers = controllers.select {|m| m =~ / 2 app/}
    unless small_controllers.empty?
      log "\nUNMODIFIED CONTROLLERS", true
      log '  ' + small_controllers.map {|h| h.sub(/.+ app\/controllers\//, '')}.join.chomp
    end

    helpers = `find app/helpers -name *.rb | xargs wc -l`
    small_helpers = helpers.select {|m| m =~ / 2 app/}
    unless small_helpers.empty?
      log "\nUNMODIFIED HELPERS", true
      log '  ' + small_helpers.map {|h| h.sub(/.+ app\/helpers\//, '')}.join.chomp
    end
    
    models = `find app/models -name *.rb | xargs wc -l`
    small_models = models.select {|m| m =~ / 2 app/}
    unless small_models.empty?
      log "\nUNMODIFIED MODELS", true
      log '  ' + small_models.map {|h| h.sub(/.+ app\/models\//, '')}.join.chomp
    end
    
    large_controllers = controllers.select {|m| m.scan(/ (\d+) app/).flatten.first.to_i > 100}
    unless large_controllers.empty?
      log "\nLARGE CONTROLLERS", true
      log '  ' + large_controllers.map {|h| h.sub(/.+ app\/controllers\//, '')}.join.chomp
    end

    large_helpers = helpers.select {|m| m.scan(/ (\d+) app/).flatten.first.to_i > 100}
    unless large_helpers.empty?
      log "\nLARGE HELPERS", true
      log '  ' + large_helpers.map {|h| h.sub(/.+ app\/helpers\//, '')}.join.chomp
    end

    large_models = models.select {|m| m.scan(/ (\d+) app/).flatten.first.to_i > 100}
    unless large_models.empty?
      log "\nLARGE MODELS", true
      log '  ' + large_models.map {|h| h.sub(/.+ app\/models\//, '')}.join.chomp
    end

    libraries = `find lib -name *.rb | xargs wc -l`
    large_libraries = libraries.select {|m| m =~ / 2 lib/}
    large_libraries = large_libraries.select {|m| m.scan(/ (\d+) lib/).flatten.first.to_i > 50}
    unless large_libraries.empty?
      log "\nLARGE LIBRARIES", true
      log '  ' + large_libraries.map {|h| h.sub(/.+ lib\//, '')}.join.chomp
    end

  end
  
  desc "duplicated_code", "Check for duplicated methods"
  def duplicated_code
    log "\nDUPLICATED METHODS - CONTROLLERS", true
    log duplicated('./app/controllers')

    log "\nDUPLICATED METHODS - MODELS", true
    log duplicated('./app/models')

    log "\nDUPLICATED METHODS - LIBRARIES", true
    log duplicated('./lib')
  end
  
  
  private
  def log(message, header = false)
    message = message.gsub(/\n/, "\n  ") unless header
    puts message
    
    # logfile = 'audit.txt'
    # 
    # @log ||= File.new(File.expand_path(logfile), 'w')
    # @log.puts message
  end
end