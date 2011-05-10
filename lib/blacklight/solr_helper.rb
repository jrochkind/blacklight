# SolrHelper is a controller layer mixin. It is in the controller scope: request params, session etc.
# 
# NOTE: Be careful when creating variables here as they may be overriding something that already exists.
# The ActionController docs: http://api.rubyonrails.org/classes/ActionController/Base.html
#
# Override these methods in your own controller for customizations:
# 
#   class CatalogController < ActionController::Base
#   
#     include Blacklight::Catalog
#   
#     def solr_search_params
#       super.merge :per_page=>10
#     end
#   end
#
# Or by including in local extensions:
#   module LocalSolrHelperExtension
#     [ local overrides ]
#   end
#
#   class CatalogController < ActionController::Base
#   
#     include Blacklight::Catalog
#     include LocalSolrHelperExtension
#   
#     def solr_search_params
#       super.merge :per_page=>10
#     end
#   end
#
# Or by using ActiveSupport::Concern:
#
#   module LocalSolrHelperExtension
#     extend ActiveSupport::Concern
#     include Blacklight::SolrHelper
#
#     [ local overrides ]
#   end
#
#   class CatalogController < ApplicationController
#     include LocalSolrHelperExtension
#     include Blacklight::Catalog
#   end  

module Blacklight::SolrHelper
  extend ActiveSupport::Concern

  MaxPerPage = 100

  included do
    if self.respond_to?(:helper_method)
      helper_method(:facet_limit_hash)
      helper_method(:facet_limit_for)
    end

    # We want to install a class-level place to keep 
    # solr_search_params_logic method names. Compare to before_filter,
    # similar design. Since we're a module, we have to add it in here.
    # There are too many different semantic choices in ruby 'class variables',
    # we choose this one for now, supplied by Rails. 
    class_inheritable_accessor :solr_search_params_logic

    # Set defaults. Each symbol identifies a _method_ that must be in
    # this class, taking two parameters (solr_parameters, user_parameters)
    # Can be changed in local apps or by plugins, eg:
    # CatalogController.include ModuleDefiningNewMethod
    # CatalogController.solr_search_params_logic << :new_method
    # CatalogController.solr_search_params_logic.delete(:we_dont_want)
    self.solr_search_params_logic = [:default_solr_parameters , :add_query_to_solr, :add_facet_fq_to_solr, :add_facetting_to_solr, :add_sorting_paging_to_solr ]
  end
  
  # A helper method used for generating solr LocalParams, put quotes
  # around the term unless it's a bare-word. Escape internal quotes
  # if needed. 
  def solr_param_quote(val, options = {})
    options[:quote] ||= '"'
    unless val =~ /^[a-zA-Z$_\-\^]+$/
      val = options[:quote] +
        # Yes, we need crazy escaping here, to deal with regexp esc too!
        val.gsub("'", "\\\\\'").gsub('"', "\\\\\"") + 
        options[:quote]
    end
    return val
  end
    

 # returns a params hash for searching solr.
  # The CatalogController #index action uses this.
  # Solr parameters can come from a number of places. From lowest
  # precedence to highest:
  #  1. General defaults in blacklight config (are trumped by)
  #  2. defaults for the particular search field identified by  params[:search_field] (are trumped by) 
  #  3. certain parameters directly on input HTTP query params 
  #     * not just any parameter is grabbed willy nilly, only certain ones are allowed by HTTP input)
  #     * for legacy reasons, qt in http query does not over-ride qt in search field definition default. 
  #  4.  extra parameters passed in as argument.
  #
  # spellcheck.q will be supplied with the [:q] value unless specifically
  # specified otherwise. 
  #
  # Incoming parameter :f is mapped to :fq solr parameter.
  def solr_search_params(user_params = params || {})
    solr_parameters = {}
    solr_search_params_logic.each do |method_name|
      send(method_name, solr_parameters, user_params)
    end

    return solr_parameters
  end
    
  
    ####
    # Start with general defaults from BL config. Need to use custom
    # merge to dup values, to avoid later mutating the original by mistake.
    def default_solr_parameters(solr_parameters, user_params)
      if Blacklight.config[:default_solr_params]
        Blacklight.config[:default_solr_params].each_pair do |key, value|
          solr_parameters[key] = value.dup rescue value
        end
      end
    end
    
    ###
    # copy paging and sorting params from BL app over to solr, with
    # fairly little transformation. 
    def add_sorting_paging_to_solr(solr_parameters, user_params)
      # Omit empty strings and nil values.             
      # Apparently RSolr takes :per_page and converts it to Solr :rows,
      # so we let it. 
      [:page, :sort, :per_page].each do |key|
        solr_parameters[key] = user_params[key] unless user_params[key].blank?      
      end
      
      # limit to MaxPerPage (100). Tests want this to be a string not an integer,
      # not sure why.     
      solr_parameters[:per_page] = solr_parameters[:per_page].to_i > self.max_per_page ? self.max_per_page.to_s : solr_parameters[:per_page]      
    end

    ##
    # Take the user-entered query, and put it in the solr params, 
    # including config's "search field" params for current search field. 
    # also include setting spellcheck.q. 
    def add_query_to_solr(solr_parameters, user_parameters)
      ###
      # Merge in search field configured values, if present, over-writing general
      # defaults
      ###
      # legacy behavior of user param :qt is passed through, but over-ridden
      # by actual search field config if present. We might want to remove
      # this legacy behavior at some point. It does not seem to be currently
      # rspec'd. 
      solr_parameters[:qt] = user_parameters[:qt] if user_parameters[:qt]
      
      search_field_def = Blacklight.search_field_def_for_key(user_parameters[:search_field])
      if (search_field_def)     
        solr_parameters[:qt] = search_field_def[:qt] if search_field_def[:qt]      
        solr_parameters.merge!( search_field_def[:solr_parameters]) if search_field_def[:solr_parameters]
      end
      
      ##
      # Create Solr 'q' including the user-entered q, prefixed by any
      # solr LocalParams in config, using solr LocalParams syntax. 
      # http://wiki.apache.org/solr/LocalParams
      ##         
      if (search_field_def && hash = search_field_def[:solr_local_parameters])
        local_params = hash.collect do |key, val|
          key.to_s + "=" + solr_param_quote(val, :quote => "'")
        end.join(" ")
        solr_parameters[:q] = "{!#{local_params}}#{user_parameters[:q]}"
      else
        solr_parameters[:q] = user_parameters[:q] if user_parameters[:q]
      end
            

      ##
      # Set Solr spellcheck.q to be original user-entered query, without
      # our local params, otherwise it'll try and spellcheck the local
      # params! Unless spellcheck.q has already been set by someone,
      # respect that.
      #
      # TODO: Change calling code to expect this as a symbol instead of
      # a string, for consistency? :'spellcheck.q' is a symbol. Right now
      # rspec tests for a string, and can't tell if other code may
      # insist on a string. 
      solr_parameters["spellcheck.q"] = user_parameters[:q] unless solr_parameters["spellcheck.q"]
    end

    ##
    # Add any existing facet limits, stored in app-level HTTP query
    # as :f, to solr as appropriate :fq query. 
    def add_facet_fq_to_solr(solr_parameters, user_params)      
      # :fq, map from :f. 
      if ( user_params[:f])
        f_request_params = user_params[:f] 
        
        solr_parameters[:fq] ||= []
        f_request_params.each_pair do |facet_field, value_list|
          value_list.each do |value|
            solr_parameters[:fq] << "{!raw f=#{facet_field}}#{value}"
          end              
        end      
      end
    end
    
    ##
    # Add appropriate Solr facetting directives in, including
    # taking account of our facet paging/'more'.  This is not
    # about solr 'fq', this is about solr facet.* params. 
    def add_facetting_to_solr(solr_parameters, user_params)
      # While not used by BL core behavior, legacy behavior seemed to be
      # to accept incoming params as "facet.field" or "facets", and add them
      # on to any existing facet.field sent to Solr. Legacy behavior seemed
      # to be accepting these incoming params as arrays (in Rails URL with []
      # on end), or single values. At least one of these is used by
      # Stanford for "faux hieararchial facets". 
      if user_params.has_key?("facet.field") || user_params.has_key?("facets")
        solr_parameters[:"facet.field"] ||= []
        solr_parameters[:"facet.field"].concat( [user_params["facet.field"], user_params["facets"]].flatten.compact ).uniq!
      end                
  
      # Support facet paging and 'more'
      # links, by sending a facet.limit one more than what we
      # want to page at, according to configured facet limits.       
      facet_limit_hash.each_key do |field_name|
        next if field_name.nil? # skip the 'default' key
        next unless (limit = facet_limit_for(field_name))
  
        solr_parameters[:"f.#{field_name}.facet.limit"] = (limit + 1)
      end
    end


  
  # a solr query method
  # given a user query, return a solr response containing both result docs and facets
  # - mixes in the Blacklight::Solr::SpellingSuggestions module
  #   - the response will have a spelling_suggestions method
  # Returns a two-element array (aka duple) with first the solr response object,
  # and second an array of SolrDocuments representing the response.docs
  def get_search_results(user_params = params || {}, extra_controller_params = {})

    # In later versions of Rails, the #benchmark method can do timing
    # better for us. 
    bench_start = Time.now
    
      solr_response = Blacklight.solr.find(  self.solr_search_params(user_params).merge(extra_controller_params))
  
      document_list = solr_response.docs.collect {|doc| SolrDocument.new(doc, solr_response)}  

      Rails.logger.debug("Solr fetch: #{self.class}#get_search_results (#{'%.1f' % ((Time.now.to_f - bench_start.to_f)*1000)}ms)")
    
    return [solr_response, document_list]
  end
  
  # returns a params hash for finding a single solr document (CatalogController #show action)
  # If the id arg is nil, then the value is fetched from params[:id]
  # This method is primary called by the get_solr_response_for_doc_id method.
  def solr_doc_params(id=nil)
    id ||= params[:id]
    # just to be consistent with the other solr param methods:
    {
      :qt => :document,
      :id => id
    }
  end
  
  # a solr query method
  # retrieve a solr document, given the doc id
  # TODO: shouldn't hardcode id field;  should be setable to unique_key field in schema.xml
  def get_solr_response_for_doc_id(id=nil, extra_controller_params={})
    solr_response = Blacklight.solr.find solr_doc_params(id).merge(extra_controller_params)
    raise Blacklight::Exceptions::InvalidSolrID.new if solr_response.docs.empty?
    document = SolrDocument.new(solr_response.docs.first, solr_response)
    [solr_response, document]
  end
  
  # given a field name and array of values, get the matching SOLR documents
  def get_solr_response_for_field_values(field, values, extra_solr_params = {})
    value_str = "(\"" + values.to_a.join("\" OR \"") + "\")"
    solr_params = {
      :defType => "lucene",   # need boolean for OR
      :q => "#{field}:#{value_str}",
      # not sure why fl * is neccesary, why isn't default solr_search_params
      # sufficient, like it is for any other search results solr request? 
      # But tests fail without this. I think because some functionality requires
      # this to actually get solr_doc_params, not solr_search_params. Confused
      # semantics again. 
      :fl => "*",  
      :facet => 'false',
      :spellcheck => 'false'
    }.merge(extra_solr_params)
    
    solr_response = Blacklight.solr.find( self.solr_search_params().merge(solr_params) )
    document_list = solr_response.docs.collect{|doc| SolrDocument.new(doc, solr_response) }
    [solr_response,document_list]
  end
  
  # returns a params hash for a single facet field solr query.
  # used primary by the get_facet_pagination method.
  # Looks up Facet Paginator request params from current request
  # params to figure out sort and offset.
  # Default limit for facet list can be specified by defining a controller
  # method facet_list_limit, otherwise 20. 
  def solr_facet_params(facet_field, user_params=params || {}, extra_controller_params={})
    input = user_params.deep_merge(extra_controller_params)

    # First start with a standard solr search params calculations,
    # for any search context in our request params. 
    solr_params = solr_search_params(user_params).merge(extra_controller_params)
    
    # Now override with our specific things for fetching facet values
    solr_params[:"facet.field"] = facet_field

    # Need to set as f.facet_field.facet.limit to make sure we
    # override any field-specific default in the solr request handler. 
    solr_params[:"f.#{facet_field}.facet.limit"] = 
      if solr_params["facet.limit"] 
        solr_params["facet.limit"].to_i + 1
      elsif respond_to?(:facet_list_limit)
        facet_list_limit.to_s.to_i + 1
      else
        20 + 1
      end
    solr_params['facet.offset'] = input[  Blacklight::Solr::FacetPaginator.request_keys[:offset]  ].to_i # will default to 0 if nil
    solr_params['facet.sort'] = input[  Blacklight::Solr::FacetPaginator.request_keys[:sort] ]     
    solr_params[:rows] = 0

    return solr_params
  end
  
  # a solr query method
  # used to paginate through a single facet field's values
  # /catalog/facet/language_facet
  def get_facet_pagination(facet_field, extra_controller_params={})
    
    solr_params = solr_facet_params(facet_field, params, extra_controller_params)
    
    # Make the solr call
    response = Blacklight.solr.find(solr_params)

    limit =       
      if respond_to?(:facet_list_limit)
        facet_list_limit.to_s.to_i
      elsif solr_params[:"f.#{facet_field}.facet.limit"]
        solr_params[:"f.#{facet_field}.facet.limit"] - 1
      else
        nil
      end

    
    # Actually create the paginator!
    # NOTE: The sniffing of the proper sort from the solr response is not
    # currently tested for, tricky to figure out how to test, since the
    # default setup we test against doesn't use this feature. 
    return     Blacklight::Solr::FacetPaginator.new(response.facets.first.items, 
      :offset => solr_params['facet.offset'], 
      :limit => limit,
      :sort => response["responseHeader"]["params"]["f.#{facet_field}.facet.sort"] || response["responseHeader"]["params"]["facet.sort"]
    )
  end
  
  # a solr query method
  # this is used when selecting a search result: we have a query and a 
  # position in the search results and possibly some facets
  # Pass in an index where 1 is the first document in the list, and
  # the Blacklight app-level request params that define the search. 
  def get_single_doc_via_search(index, request_params)
    solr_params = solr_search_params(request_params)
    solr_params[:start] = index - 1 # start at 0 to get 1st doc, 1 to get 2nd. 
    solr_params[:per_page] = 1
    solr_params[:rows] = 1
    solr_params[:fl] = '*'
    Blacklight.solr.find(solr_params).docs.first
  end
    
  # returns a solr params hash
  # if field is nil, the value is fetched from Blacklight.config[:index][:show_link]
  # the :fl (solr param) is set to the "field" value.
  # per_page is set to 10
  def solr_opensearch_params(field=nil)
    solr_params = solr_search_params
    solr_params[:per_page] = 10
    solr_params[:fl] = Blacklight.config[:index][:show_link]
    solr_params
  end
  
  # a solr query method
  # does a standard search but returns a simplified object.
  # an array is returned, the first item is the query string,
  # the second item is an other array. This second array contains
  # all of the field values for each of the documents...
  # where the field is the "field" argument passed in.
  def get_opensearch_response(field=nil, extra_controller_params={})
    solr_params = solr_opensearch_params().merge(extra_controller_params)
    response = Blacklight.solr.find(solr_params)
    a = [solr_params[:q]]
    a << response.docs.map {|doc| doc[solr_params[:fl]].to_s }
  end
  
  
  
  # Look up facet limit for given facet_field. Will look at config, and
  # if config is 'true' will look up from Solr @response if available. If
  # no limit is avaialble, returns nil. Used from #solr_search_params
  # to supply f.fieldname.facet.limit values in solr request (no @response
  # available), and used in display (with @response available) to create
  # a facet paginator with the right limit. 
  def facet_limit_for(facet_field)
    limits_hash = facet_limit_hash
    return nil if limits_hash.blank?
        
    limit = limits_hash[facet_field]

    if ( limit == true && @response && 
         @response["responseHeader"] && 
         @response["responseHeader"]["params"])
     limit =
       @response["responseHeader"]["params"]["f.#{facet_field}.facet.limit"] || 
       @response["responseHeader"]["params"]["facet.limit"]
       limit = (limit.to_i() -1) if limit
       limit = nil if limit == -2 # -1-1==-2, unlimited. 
    elsif limit == true
      limit = nil
    end

    return limit
  end

  # Returns complete hash of key=facet_field, value=limit.
  # Used by SolrHelper#solr_search_params to add limits to solr
  # request for all configured facet limits.
  def facet_limit_hash
    Blacklight.config[:facet][:limits] || {}
  end

  def max_per_page
    MaxPerPage
  end
  
  
end
