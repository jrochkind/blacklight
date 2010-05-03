# Rake tasks for the SolrMarc Java indexer.
# Marc Record defaults to indexing lc_records.utf8.mrc
# config.properties defaults to config/demo_config.properties (in the plugin, not the rails app)


require 'fileutils'

# give us #root and #locate_path
require File.expand_path(__FILE__ + '/../../blacklight_path_finders.rb')
extend BlacklightPathFinders

namespace :solr do
  namespace :marc do
    
    
    desc "Index the supplied test data into Solr; set NOOP to true to view output command."
    task :index_test_data => :environment do
      marc_records_path = locate_path("data", "test_data.utf8.mrc")
      solr_path = locate_path("jetty", "solr")
      solr_war_path = locate_path('jetty', 'webapps', 'solr.war')
      solr_marc_jar_path = locate_path('solr_marc', 'SolrMarc.jar')
      config_path = locate_path('config', 'SolrMarc', 'config.properties')
      indexer_properties_path = locate_path('config', 'SolrMarc', 'index.properties')
      cmd = "java -Xmx512m"
      cmd << " -Dsolr.indexer.properties=#{indexer_properties_path} -Done-jar.class.path=#{solr_war_path} -Dsolr.path=#{solr_path}"
      cmd << " -jar #{solr_marc_jar_path} #{config_path} #{marc_records_path}"
      puts "\ncommand being executed:\n#{cmd}\n\n"
      system cmd unless ENV.keys.any?{|k| k =~ /^noop/i }
    end
    
    desc "Index marc data using SolrMarc. Available environment variables: MARC_RECORDS_PATH, CONFIG_PATH, SOLR_MARC_MEM_ARGS, SOLR_WAR_PATH, SOLR_JAR_PATH"
    task :index => "index:work"

    namespace :index do


      task :work do
        solrmarc_arguments = compute_arguments        

        # If no marc records given, display :info task
        unless solrmarc_arguments[:marc_records_path]                    
          Rake::Task[ "solr:marc:index:info" ].execute
          exit
        end
        
        commandStr = solrmarc_command_line( solrmarc_arguments )
        puts commandStr
        puts
        `#{commandStr}`
        
      end # work
      
      desc "Shows more info about the solr:marc:index task."
      task :info do
        
        solrmarc_arguments = compute_arguments
        puts <<-EOS
  Possible environment variables, with settings as invoked. You can set these
  variables on the command line, eg:
        rake solr:marc:index MARC_FILE=/some/file.mrc
  
  MARC_FILE: #{solrmarc_arguments[:marc_records_path] || "[marc records path needed]"}
  
  CONFIG_PATH: #{solrmarc_arguments[:config_properties_path]}
     Defaults to RAILS_ROOT/config/SolrMarc/config(-RAILS_ENV).properties
     or else RAILS_ROOT/vendor/plugins/blacklight/SolrMarc/config ...

     Note that SolrMarc search path includes directory of config_path,
     so translation_maps and index_scripts dirs will be found there. 
  
  SOLRMARC_JAR_PATH: #{solrmarc_arguments[:solrmarc_jar_path]}
  
  SOLRMARC_MEM_ARGS: #{solrmarc_arguments[:solrmarc_mem_arg]}
  
  SolrMarc command that will be run:
  
  #{solrmarc_command_line(solrmarc_arguments)}
  EOS
      end
    end # index
  end # :marc
end # :solr

# Computes arguments to Solr, returns hash
# Calculate default args based on location of rake file itself,
# which we assume to be in the plugin, or in the Rails executing
# this rake task, at RAILS_ROOT. 
def compute_arguments
  
  arguments  = {}

  require 'ruby-debug'
  debugger
  
  app_site_path = File.expand_path(File.join(RAILS_ROOT, "config", "SolrMarc"))
  plugin_site_path = File.expand_path(File.join(RAILS_ROOT, "vendor", "plugins", "blacklight", "config", "SolrMarc"))


  # Find config in local app or plugin, possibly based on our RAILS_ENV  
  arguments[:config_properties_path] = ENV['CONFIG_PATH']
  unless arguments[:config_properties_path]
    [ File.join(app_site_path, "config-#{RAILS_ENV}.properties"  ),
      File.join( app_site_path, "config.properties"),
      File.join( plugin_site_path, "config-#{RAILS_ENV}.properties"),
      File.join( plugin_site_path, "config.properties"),
    ].each do |file_path|
      if File.exists?(file_path)
        arguments[:config_properties_path] = file_path
        break
      end
    end
  end
  
  #java mem arg is from env, or default

  arguments[:solrmarc_mem_arg] = ENV['SOLRMARC_MEM_ARGS'] || '-Xmx512m'
      
  # SolrMarc is embedded in the plugin, or could be a custom
  # one in local app. 
  arguments[:solrmarc_jar_path] = ENV['SOLRMARC_JAR_PATH'] || locate_path("solr_marc", "SolrMarc.jar") 
  

      

  # Solr URL, find from solr.yml, app or plugin
  solr_yml_path = locate_path("config", "solr.yml")
  if ( File.exists?( solr_yml_path ))
    solr_config = YAML::load(File.open(solr_yml_path))
    arguments[:solr_url] = solr_config[ RAILS_ENV ]['url'] if solr_config[RAILS_ENV]
  end


  return arguments
end

def solrmarc_command_line(arguments)
  cmd = "java #{arguments[:solrmarc_mem_arg]}  -jar #{arguments[:solrmarc_jar_path]} #{arguments[:config_properties_path]} #{arguments[:marc_records_path]}"

  cmd += " -Dsolr.hosturl=#{arguments[:solr_url]}" unless arguments[:solr_url].blank?

  return cmd  
end
