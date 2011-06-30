# -*- encoding : utf-8 -*-
module Blacklight::Catalog 
  extend ActiveSupport::Concern
  include Blacklight::SolrHelper
  
  SearchHistoryWindow = 12 # how many searches to save in session history

  # The following code is executed when someone includes blacklight::catalog in their
  # own controller.
  included do  
    before_filter :history_session
    
    helper_method :search_context

    # Whenever an action raises SolrHelper::InvalidSolrID, this block gets executed.
    # Hint: the SolrHelper #get_solr_response_for_doc_id method raises this error,
    # which is used in the #show action here.
    rescue_from Blacklight::Exceptions::InvalidSolrID, :with => :invalid_solr_id_error
    # When RSolr::RequestError is raised, the rsolr_request_error method is executed.
    # The index action will more than likely throw this one.
    # Example, when the standard query parser is used, and a user submits a "bad" query.
    rescue_from RSolr::Error::Http, :with => :rsolr_request_error
  end
  

    # get search results from the solr index
    def index
      extra_head_content << view_context.auto_discovery_link_tag(:rss, url_for(params.merge(:format => 'rss')), :title => "RSS for results")
      extra_head_content << view_context.auto_discovery_link_tag(:atom, url_for(params.merge(:format => 'atom')), :title => "Atom for results")
      extra_head_content << view_context.auto_discovery_link_tag(:unapi, unapi_url, {:type => 'application/xml',  :rel => 'unapi-server', :title => 'unAPI' })
      
      (@response, @document_list) = get_search_results
      @filters = params[:f] || []
      
      respond_to do |format|
        format.html { save_current_search_params }
        format.rss  { render :layout => false }
        format.atom { render :layout => false }
      end
    end
    
    # get single document from the solr index
    def show
      extra_head_content << view_context.auto_discovery_link_tag(:unapi, unapi_url, {:type => 'application/xml',  :rel => 'unapi-server', :title => 'unAPI' })
      @response, @document = get_solr_response_for_doc_id    

      respond_to do |format|
        format.html {setup_next_and_previous_documents}

        # Add all dynamically added (such as by document extensions)
        # export formats.
        @document.export_formats.each_key do | format_name |
          # It's important that the argument to send be a symbol;
          # if it's a string, it makes Rails unhappy for unclear reasons. 
          format.send(format_name.to_sym) { render :text => @document.export_as(format_name), :layout => false }
        end
        
      end
    end

    def unapi
      @export_formats = Blacklight.config[:unapi] || {}
      @format = params[:format]
      if params[:id]
        @response, @document = get_solr_response_for_doc_id
        @export_formats = @document.export_formats
      end
  
      unless @format
        render 'unapi.xml.builder', :layout => false and return
      end
  
      respond_to do |format|
        format.all do
          send_data @document.export_as(@format), :type => @document.export_formats[@format][:content_type], :disposition => 'inline' if @document.will_export_as @format
        end
      end
    end
      
    
    # displays values and pagination links for a single facet field
    def facet
      @pagination = get_facet_pagination(params[:id], params)
    end
    
    # method to serve up XML OpenSearch description and JSON autocomplete response
    def opensearch
      respond_to do |format|
        format.xml do
          render :layout => false
        end
        format.json do
          render :json => get_opensearch_response
        end
      end
    end
    
    # citation action
    def citation
      @response, @documents = get_solr_response_for_field_values(SolrDocument.unique_key,params[:id])
    end
    # grabs a bunch of documents to export to endnote
    def endnote
      @response, @documents = get_solr_response_for_field_values(SolrDocument.unique_key,params[:id])
      respond_to do |format|
        format.endnote
      end
    end
    
    # Email Action (this will render the appropriate view on GET requests and process the form and send the email on POST requests)
    def email
      @response, @documents = get_solr_response_for_field_values(SolrDocument.unique_key,params[:id])
      if request.post?
        if params[:to]
          from = request.host # host w/o port for From address (from address cannot have port#)
          url_gen_params = {:host => request.host_with_port, :protocol => request.protocol}
          
          if params[:to].match(/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$/)
            email = RecordMailer.email_record(@documents, {:to => params[:to], :message => params[:message]}, from, url_gen_params)
          else
            flash[:error] = "You must enter a valid email address"
          end
          email.deliver unless flash[:error]
          redirect_to :back
        else
          flash[:error] = "You must enter a recipient in order to send this message"
        end
      end
    end
    
    # SMS action (this will render the appropriate view on GET requests and process the form and send the email on POST requests)
    def sms 
      @response, @documents = get_solr_response_for_field_values(SolrDocument.unique_key,params[:id])
      if request.post?
        from = request.host # host w/o port for From address (from address cannot have port#)
        url_gen_params = {:host => request.host_with_port, :protocol => request.protocol}
        
        if params[:to]
          phone_num = params[:to].gsub(/[^\d]/, '')
          unless params[:carrier].blank?
            if phone_num.length != 10
              flash[:error] = "You must enter a valid 10 digit phone number"
            else
              email = RecordMailer.sms_record(@documents, {:to => phone_num, :carrier => params[:carrier]}, from, url_gen_params)
            end
            email.deliver unless flash[:error]
            redirect_to :back
          else
            flash[:error] = "You must select a carrier"
          end
        else
          flash[:error] = "You must enter a recipient's phone number in order to send this message"
        end
        
      end
    end
    
    # DEPRECATED backwards compatible method that will just redirect to the appropriate action.  It will return a 404 if a bad action is supplied (just in case).
    def send_email_record
      warn "[DEPRECATION] CatalogController#send_email_record is deprecated.  Please use the email or sms controller action instead."
      if ["sms","email"].include?(params[:style])
        redirect_to :action => params[:style] 
      else
        render :file => "#{::Rails.root}/public/404.html", :layout => false, :status => 404
      end
    end

    def librarian_view
      @response, @document = get_solr_response_for_doc_id
    end
    
    
    protected    
    #
    # non-routable methods ->
    #
    
    
    # calls setup_previous_document then setup_next_document.
    # used in the show action for single view pagination.
    def setup_next_and_previous_documents
      if search_context
        search_params = search_context[:search].query_params.merge(:sort => search_context[:sort])
        i = search_context[:i]
                
        if i > 1          
          @previous_document = get_single_doc_via_search(i - 1, search_params)
        end
        @next_document = get_single_doc_via_search(i + 1, search_params)
      end
    end
    
    # returns info on the 'search context', for use on a #show page,
  # for next/prev/return links.
  # returns nil if there is none. 
  def search_context
    @search_context ||= begin
      if params[:sc] && params[:i]
        {:search => Search.find(params[:sc]),
         :i => params[:i].to_i,
         :sort => params[:sort]
        }
      else
        nil
      end
    end
    return @search_context
  end
  
  def set_search_context(hash)
    @search_context = hash
  end
    
    # sets up the session[:history] hash if it doesn't already exist.
    # assigns all Search objects (that match the searches in session[:history]) to a variable @searches.
    def history_session
      session[:history] ||= []
      @searches = searches_from_history # <- in BlacklightController
    end
        
    
    # Saves the current search (if it does not already exist) as a models/search object
    # then adds the id of the serach object to session[:history]
    def save_current_search_params    
      # If it's got anything other than controller, action, total, we
      # consider it an actual search to be saved. Can't predict exactly
      # what the keys for a search will be, due to possible extra plugins.
      return if (params.keys - [:controller, :action, :total, :counter, :commit ]) == []
      # always make a deep copy of params before modifying it, mutating
      # the current request params results in terrible bugs. 
      params_copy = Marshal.load(Marshal.dump(params))
      params_copy.delete(:page)
      
      @current_search_sort = params_copy[:sort]
      if (in_history = @searches.find { |search| search.query_params == params_copy } )
        current_search = in_history        
      else        
        current_search = Search.create(:query_params => params_copy, :total => @response.total)                                
        session[:history].unshift(current_search.id)
        
        # Only keep most recent X searches in history, for performance. 
        # both database (fetching em all), and cookies (session is in cookie)
        session[:history] = session[:history].slice(0, Blacklight::Catalog::SearchHistoryWindow )
      end
      
      set_search_context(:search => current_search, :sort => params_copy[:sort])
      
    end
          

    
    # we need to know if we are viewing the item as part of search results so we know whether to
    # include certain partials or not
    def adjust_for_results_view
      if params[:results_view] == "false"
        session[:search][:results_view] = false
      else
        session[:search][:results_view] = true
      end
    end
    
       
    # when solr (RSolr) throws an error (RSolr::RequestError), this method is executed.
    def rsolr_request_error(exception)
      if Rails.env == "development"
        raise exception # Rails own code will catch and give usual Rails error page with stack trace
      else
        flash_notice = "Sorry, I don't understand your search."
        # Set the notice flag if the flash[:notice] is already set to the error that we are setting.
        # This is intended to stop the redirect loop error
        notice = flash[:notice] if flash[:notice] == flash_notice
        unless notice
          flash[:notice] = flash_notice
          redirect_to root_path, :status => 500
        else
          render :template => "public/500.html", :layout => false, :status => 500
        end
      end
    end
    
    # when a request for /catalog/BAD_SOLR_ID is made, this method is executed...
    def invalid_solr_id_error
      if Rails.env == "development"
        render # will give us the stack trace
      else
        flash[:notice] = "Sorry, you have requested a record that doesn't exist."
        redirect_to root_path, :status => 404
      end
      
    end
  
end
