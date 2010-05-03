# Methods for figuring out path to BL plugin, and then locate various files
# either in the app itself or defaults in the plugin -- whether you are running
# from the plugin itself or from an actual app using te plugin.
# In a seperate module so it can be used by both Blacklight class, and
# by rake tasks without loading the whole Rails environment. 
module BlacklightPathFinders
  # returns the full path the the blacklight plugin installation
  def root
    @root ||= File.expand_path File.join(__FILE__, '..', '..')
  end
  
  # Searches Rails.root then Blacklight.root for a valid path
  # returns a full path if a valid path is found
  # returns nil if nothing is found.
  # First looks in Rails.root, then Blacklight.root
  #
  # Example:
  # full_path_to_solr_marc_jar = Blacklight.locate_path 'solr_marc', 'SolrMarc.jar'
  
  def locate_path(*subpath_fragments)
    subpath = subpath_fragments.join('/')
    base_match = [Rails.root, self.root].find do |base|
      File.exists? File.join(base, subpath)
    end
    File.join(base_match.to_s, subpath) if base_match
  end
end
