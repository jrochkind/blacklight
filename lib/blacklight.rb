module Blacklight
  extend BlacklightPathFinders
  
  autoload :CoreExt, 'blacklight/core_ext.rb'
  # load up the CoreExt by referencing it:
  CoreExt
  
  autoload :Configurable, 'blacklight/configurable'
  autoload :SearchFields, 'blacklight/search_fields'

  autoload :Solr, 'blacklight/solr.rb'
  autoload :Marc, 'blacklight/marc.rb'
  
  autoload :SolrHelper, 'blacklight/solr_helper'
  
  autoload :Routes, 'blacklight/routes'
  
  extend Configurable
  extend SearchFields
  
  class << self
    attr_accessor :solr, :solr_config
  end
  
  # The configuration hash that gets used by RSolr.connect
  @solr_config ||= {}
  
  # Just returning a string for the Blacklight version number.
  # I've just put master here now, should it say when it's running under master?  (Master?)
  # We need to find a better way of increasing this number automatically during releases, but this is a good way for now.
  def self.version
    "master"
  end
  
  def self.init
    
    solr_config = YAML::load(File.open("#{RAILS_ROOT}/config/solr.yml"))
    raise "The #{RAILS_ENV} environment settings were not found in the solr.yml config" unless solr_config[RAILS_ENV]
    
    Blacklight.solr_config[:url] = solr_config[RAILS_ENV]['url']
    
    if Gem.available? 'curb'
      require 'curb'
      Blacklight.solr = RSolr::Ext.connect(Blacklight.solr_config.merge(:adapter=>:curb))
    else
      Blacklight.solr = RSolr::Ext.connect(Blacklight.solr_config)
    end
    
    # set the SolrDocument.connection to Blacklight.solr
    SolrDocument.connection = Blacklight.solr
    logger.info("BLACKLIGHT: running version #{Blacklight.version}")
    logger.info("BLACKLIGHT: initialized with Blacklight.solr_config: #{Blacklight.solr_config.inspect}")
    logger.info("BLACKLIGHT: initialized with Blacklight.solr: #{Blacklight.solr.inspect}")
    logger.info("BLACKLIGHT: initialized with Blacklight.config: #{Blacklight.config.inspect}")
    
  end

  def self.logger
    RAILS_DEFAULT_LOGGER
  end
  
  
end