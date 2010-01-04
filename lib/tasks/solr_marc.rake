# Rake tasks for the SolrMarc Java indexer.
# Marc Record defaults to indexing lc_records.utf8.mrc
# config.properties defaults to config/demo_config.properties (in the plugin, not the rails app)


require 'fileutils'

namespace :solr do
  namespace :marc do
    desc "Index marc data using SolrMarc. Available environment variables: MARC_RECORDS_PATH, SOLRMARC_MEM_ARGS, SOLRMARC_JAR_PATH, SOLRMARC_SITE_PATH, CONFIG_PATH "
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

  SOLRMARC_SITE_PATH: #{solrmarc_arguments[:solrmarc_site_path]}
    Used as solrmarc.site.path property to Solr, all your local files. 
  
  CONFIG_PATH: #{solrmarc_arguments[:config_properties_path]}
     defaults to SOLRMARC_SITE_PATH/config.properties    
  
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

  app_site_path = File.expand_path(File.join(RAILS_ROOT, "config", "SolrMarc"))
  plugin_site_path = File.expand_path(File.join(RAILS_ROOT, "plugins", "blacklight", "config", "SolrMarc"))
  arguments[:solrmarc_site_path] = ENV['SOLRMARC_SITE_PATH'] || (File.exists?(app_site_path) ? app_site_path : plugin_site_path)


  # Config we assume is in site_path. 
  arguments[:config_properties_path] = ENV['CONFIG_PATH'] || File.expand_path(File.join(arguments[:solrmarc_site_path], "config.properites"))

  #java mem arg is from env, or default

  arguments[:solrmarc_mem_arg] = ENV['SOLRMARC_MEM_ARGS'] || '-Xmx512m'
      
  # SolrMarc is embedded in the plugin. We might be running the
  # rake task from the plugin dir, or from the RAILS dir.
  solr_marc_from_plugin = File.expand_path(File.join(RAILS_ROOT,"solr_marc","SolrMarc.jar"))
  solr_marc_from_app = File.expand_path(File.join(RAILS_ROOT, "plugins", "blacklight" "solr_marc", "SolrMarc.jar" ))
  arguments[:solrmarc_jar_path] = ENV['SOLRMARC_JAR_PATH'] || (File.exists?(solr_marc_from_app) ? solr_marc_from_app : solr_marc_from_plugin)  
  

      
  arguments[:marc_records_path] = ENV['MARC_FILE']
  arguments[:marc_records_path] = File.expand_path(arguments[:marc_records_path]) if arguments[:marc_records_path]

  return arguments
end

def solrmarc_command_line(arguments)
  "java #{arguments[:solrmarc_mem_arg]}  -jar #{arguments[:solrmarc_jar_path]} #{arguments[:solr_marc_config_path]} -Dsolrmarc.site.path=#{arguments[:solrmarc_site_path]}#{arguments[:marc_records_path]}"
end