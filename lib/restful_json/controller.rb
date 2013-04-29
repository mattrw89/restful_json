# The restful_json controller module. This module (RestfulJson::Controller) is included on ActionController
# and then each individual controller should call acts_as_restful_json.
#
# Only use acts_as_restful_json in each individual service controller rather than a parent or
# ancestor class of the service controller. class_attribute's are supposed to work when you subclass,
# if you use setters (=, =+ to add to array instead of <<, etc.) but we have seen strange errors
# about missing columns, etc. related to the model_class, etc. being wrong if you share a 
# parent/ancestor class that acts_as_restful_json and then switch back and forth between controllers.
# Why? The controller class overrides the shared class_attribute's when the controller class loads,
# which other than re-loading via Rails autoload, only happens once; so you hit one controller, then the
# the other, it starts overwriting/adding to attributes, and then when you hit the first one again, no
# class method calling on class instantiation is being called, so it is using the wrong model. That is
# bad, so don't do that.
#
module RestfulJson
  module Controller
    extend ::ActiveSupport::Concern

    NILS = ['NULL'.freeze,'null'.freeze,'nil'.freeze]
    SINGLE_VALUE_ACTIONS = ['create'.freeze,'update'.freeze,'destroy'.freeze,'new'.freeze]

    included do
      # this can be overriden in the controller via defining respond_to
      formats = RestfulJson.formats || ::Mime::EXTENSION_LOOKUP.keys.collect{|m|m.to_sym}
      respond_to *formats

      # create class attributes for each controller option and set the value to the value in the app configuration
      class_attribute :model_class, instance_writer: true
      class_attribute :model_singular_name, instance_writer: true
      class_attribute :model_plural_name, instance_writer: true
      class_attribute :param_to_attr_and_arel_predicate, instance_writer: true
      class_attribute :supported_functions, instance_writer: true
      class_attribute :ordered_by, instance_writer: true
      class_attribute :action_to_query, instance_writer: true
      class_attribute :param_to_query, instance_writer: true
      class_attribute :param_to_through, instance_writer: true
      class_attribute :action_to_serializer, instance_writer: true
      class_attribute :action_to_serializer_for, instance_writer: true

      # use values from config
      RestfulJson::CONTROLLER_OPTIONS.each do |key|
        class_attribute key, instance_writer: true
        self.send("#{key}=".to_sym, RestfulJson.send(key))
      end

      self.param_to_attr_and_arel_predicate ||= {}
      self.supported_functions ||= []
      self.ordered_by ||= []
      self.action_to_query ||= {}
      self.param_to_query ||= {}
      self.param_to_through ||= {}
      self.action_to_serializer ||= {}
      self.action_to_serializer_for ||= {}
    end

    module ClassMethods

      # A whitelist of filters and definition of filter options related to request parameters.
      #
      # If no options are provided or the :using option is provided, defines attributes that are queryable through the operation(s) already defined in can_filter_by_default_using, or can specify attributes:
      #   can_filter_by :attr_name_1, :attr_name_2 # implied using: [eq] if RestfulJson.can_filter_by_default_using = [:eq] 
      #   can_filter_by :attr_name_1, :attr_name_2, using: [:eq, :not_eq]
      #
      # When :with_query is specified, it will call a supplied lambda. e.g. t is self.model_class.arel_table, q is self.model_class.scoped, and p is params[:my_param_name]:
      #   can_filter_by :my_param_name, with_query: ->(t,q,p) {...}
      #
      # When :through is specified, it will take the array supplied to through as 0 to many model names following by an attribute name. It will follow through
      # each association until it gets to the attribute to filter by that via ARel joins, e.g. if the model Foobar has an association to :foo, and on the Foo model there is an assocation
      # to :bar, and you want to filter by bar.name (foobar.foo.bar.name):
      #  can_filter_by :my_param_name, through: [:foo, :bar, :name]
      def can_filter_by(*args)
        options = args.extract_options!

        # :using is the default action if no options are present
        if options[:using] || options.size == 0
          predicates = Array.wrap(options[:using] || self.can_filter_by_default_using)
          predicates.each do |predicate|
            predicate_sym = predicate.to_sym
            args.each do |attr|
              attr_sym = attr.to_sym
              self.param_to_attr_and_arel_predicate[attr_sym] = [attr_sym, :eq, options] if predicate_sym == :eq
              self.param_to_attr_and_arel_predicate["#{attr}#{self.predicate_prefix}#{predicate}".to_sym] = [attr_sym, predicate_sym, options]
            end
          end
        end

        if options[:with_query]
          args.each do |with_query_key|
            self.param_to_query[with_query_key.to_sym] = options[:with_query]
          end
        end

        if options[:through]
          args.each do |through_key|
            self.param_to_through[through_key.to_sym] = options[:through]
          end
        end
      end

      # Can specify additional functions in the index, e.g.
      #   supports_functions :skip, :uniq, :take, :count
      def supports_functions(*args)
        args.extract_options! # remove hash from array- we're not using it yet
        self.supported_functions += args
      end
      
      # Specify a custom query. If action specified does not have a method, it will alias_method index to create a new action method with that query.
      #
      # t is self.model_class.arel_table and q is self.model_class.scoped, e.g.
      #   query_for :index, is: -> {|t,q| q.where(:status_code => 'green')}
      def query_for(*args)
        options = args.extract_options!
        # TODO: support custom actions to be automaticaly defined
        args.each do |an_action|
          if options[:is]
            self.action_to_query[an_action.to_s] = options[:is]
          else
            raise "#{self.class.name} must supply an :is option with query_for #{an_action.inspect}"
          end
          unless an_action.to_sym == :index
            alias_method an_action.to_sym, :index
          end
        end
      end

      # Takes an string, symbol, array, hash to indicate order. If not a hash, assumes is ascending. Is cumulative and order defines order of sorting, e.g:
      #   #would order by foo_color attribute ascending
      #   order_by :foo_color
      # or
      #   order_by {:foo_date => :asc}, :foo_color, 'foo_name', {:bar_date => :desc}
      def order_by(args)
        self.ordered_by = (Array.wrap(self.ordered_by) + Array.wrap(args)).flatten.compact.collect {|item|item.is_a?(Hash) ? item : {item.to_sym => :asc}}
      end

      # Associate a non-standard ActiveModel Serializer for one or more actions, e.g.
      #    serialize_action :index, with: FoosSerializer
      # or
      #    serialize_action :index, :some_custom_action, with: FooSerializer
      # The default functionality of each action is to use serialize for show, each, create, update, and destroy and serialize_each for index and
      # any custom actions created with query_for. To override that, specify the :for option with value as :array or :each:
      #    serialize_action :index, :some_custom_action, with: FoosSerializer, for: :array
      def serialize_action(*args)
        options = args.extract_options!
        args.each do |an_action|
          if options[:with]
            self.action_to_serializer[an_action.to_s] = options[:with]
            self.action_to_serializer_for[an_action.to_s] = options[:for] if options[:for]
          else
            raise "#{self.class.name} must supply an :with option with serialize_action #{an_action.inspect}"
          end
        end
      end
    end

    # In initialize we:
    # * guess model name, if unspecified, from controller name
    # * define instance variables containing model name
    # * define the (model_plural_name)_url method, needed if controllers are not in the same module as the models
    # Note: if controller name is not based on model name *and* controller is in different module than model, you'll need to
    # redefine the appropriate method(s) to return urls if needed.
    def initialize
      super

      # if not set, use controller classname
      qualified_controller_name = self.class.name.chomp('Controller')
      @model_class = self.model_class || qualified_controller_name.split('::').last.singularize.constantize

      raise "#{self.class.name} failed to initialize. self.model_class was nil in #{self} which shouldn't happen!" if @model_class.nil?
      raise "#{self.class.name} assumes that #{self.model_class} extends ActiveRecord::Base, but it didn't. Please fix, or remove this constraint." unless @model_class.ancestors.include?(ActiveRecord::Base)

      @model_singular_name = self.model_singular_name || self.model_class.name.underscore
      @model_plural_name = self.model_plural_name || @model_singular_name.pluralize
      @model_at_plural_name_sym = "@#{@model_plural_name}".to_sym
      @model_at_singular_name_sym = "@#{@model_singular_name}".to_sym
      
      # next 3 are for vanilla strong_parameters
      @model_singular_name_params_sym = "#{@model_singular_name}_params".to_sym
      @create_model_singular_name_params_sym = "create_#{@model_singular_name}_params".to_sym
      @update_model_singular_name_params_sym = "update_#{@model_singular_name}_params".to_sym

      underscored_modules_and_underscored_plural_model_name = qualified_controller_name.gsub('::','_').underscore

      # This is a workaround for controllers that are in a different module than the model only works if the controller's base part of the unqualified name in the plural model name.
      # If the model name is different than the controller name, you will need to define methods to return the right urls.
      class_eval "def #{@model_plural_name}_url;#{underscored_modules_and_underscored_plural_model_name}_url;end" unless @model_plural_name == underscored_modules_and_underscored_plural_model_name
      singularized_underscored_modules_and_underscored_plural_model_name = underscored_modules_and_underscored_plural_model_name
      class_eval "def #{@model_singular_name}_url(record);#{singularized_underscored_modules_and_underscored_plural_model_name}_url(record);end" unless @model_singular_name == singularized_underscored_modules_and_underscored_plural_model_name
    end

    def convert_request_param_value_for_filtering(attr_sym, value)
      value && NILS.include?(value) ? nil : value
    end

    # Returns self.return_error_data by default. To only return error_data in dev and test, use this:
    # `def enable_long_error?; Rails.env.development? || Rails.env.test?; end`
    def include_error_data?
      self.return_error_data
    end

    # Searches through self.rescue_handlers for appropriate handler.
    # self.rescue_handlers is an array of hashes where there is key :exception_classes and/or :exception_ancestor_classes
    # along with :i18n_key and :status keys.
    # :exception_classes contains an array of classes to exactly match the exception.
    # :exception_ancestor_classes contains an array of classes that can match an ancestor of the exception.
    # If exception handled, returns hash, hopefully containing keys :i18n_key and :status.
    # Otherwise, returns nil which indicates that this exception should not be handled.
    def exception_handling_data(e)
      self.rescue_handlers.each do |handler|
        return handler if (handler.key?(:exception_classes) && handler[:exception_classes].include?(e.class))
        if handler.key?(:exception_ancestor_classes)
          handler[:exception_ancestor_classes].each do |ancestor|
            return handler if e.class.ancestors.include?(ancestor)
          end
        elsif !handler.key?(:exception_classes) && !handler.key?(:exception_ancestor_classes)
          return handler
        end
      end
      nil
    end

    def handle_or_raise(e)
      raise e if self.rescue_class.nil?
      handling_data = exception_handling_data(e)
      raise e unless handling_data
      # this is something we intended to rescue, so log it
      logger.error(e)
      # render error only if we haven't rendered response yet
      render_error(e, handling_data) unless @performed_render
    end

    # Renders error using handling data options (where options are probably hash from self.rescue_handlers that was matched).
    #
    # If include_error_data? is true, it returns something like the following (with the appropriate HTTP status code via setting appropriate status in respond_do:
    # {"status": "not_found",
    #  "error": "Internationalized error message or e.message",
    #  "error_data": {"type": "ActiveRecord::RecordNotFound", "message": "Couldn't find Bar with id=23423423", "trace": ["backtrace line 1", ...]}
    # }
    #
    # If include_error_data? is false, it returns something like:
    # {"status": "not_found", "error", "Couldn't find Bar with id=23423423"}
    #
    # It handles any format in theory that is supported by respond_to and has a `to_(some format)` method.
    def render_error(e, handling_data)
      i18n_key = handling_data[:i18n_key]
      msg = result = t(i18n_key, default: e.message)
      status = handling_data[:status] || :internal_server_error
      if include_error_data?
        respond_to do |format|
          format.html { render notice: msg }
          format.any { render request.format.to_sym => {status: status, error: msg, error_data: {type: e.class.name, message: e.message, trace: Rails.backtrace_cleaner.clean(e.backtrace)}}, status: status }
        end
      else
        respond_to do |format|
          format.html { render notice: msg }
          format.any { render request.format.to_sym => {status: status, error: msg}, status: status }
        end
      end
      # return exception so we know it was handled
      e
    end

    def render_or_respond(read_only_action, success_code = :ok)
      if self.render_enabled
        # 404/not found is just for update (not destroy, because idempotent destroy = no 404)
        if success_code == :not_found
          respond_to do |format|
            format.html { render file: "#{Rails.root}/public/404.html", status: :not_found }
            format.any  { head :not_found }
          end
        elsif !@value.nil? && ((read_only_action && RestfulJson.return_resource) || RestfulJson.avoid_respond_with)
          respond_with(@value) do |format|
            format.json do
              # define local variables in blocks, not outside of them, to be safe, even though would work in this case              
              custom_action_serializer = self.action_to_serializer[params[:action].to_s]
              custom_action_serializer_for = self.action_to_serializer_for[params[:action].to_s]
              serialization_key = single_value_response? ? (custom_action_serializer_for == :each ? :each_serializer : :serializer) : (custom_action_serializer_for == :array ? :serializer : :each_serializer)
              if !@value.respond_to?(:errors) || @value.errors.empty?
                render custom_action_serializer ? {json: @value, status: success_code, serialization_key => custom_action_serializer} : {json: @value, status: success_code}
              else
                render custom_action_serializer ? {json: {errors: @value.errors}, status: :unprocessable_entity, serialization_key => custom_action_serializer} : {json: {errors: @value.errors}, status: :unprocessable_entity}
              end
            end
          end
        else
          # code duplicated from above because local vars don't always traverse well into block (based on wierd ruby-proc bug experienced)
          custom_action_serializer = self.action_to_serializer[params[:action].to_s]
          custom_action_serializer_for = self.action_to_serializer_for[params[:action].to_s]
          serialization_key = single_value_response? ? (custom_action_serializer_for == :array ? :serializer : :each_serializer) : (custom_action_serializer_for == :each ? :each_serializer : :serializer)
          respond_with @value, custom_action_serializer ? {(self.action_to_serializer_for[params[:action].to_s] == :each ? :each_serializer : :serializer) => custom_action_serializer} : {}
        end
      else
        @value
      end
    end

    def single_value_response?
      SINGLE_VALUE_ACTIONS.include?(params[:action].to_s)
    end

    # The controller's index (list) method to list resources.
    #
    # Note: this method be alias_method'd by query_for, so it is more than just index.
    def index
      # could be index or another action if alias_method'd by query_for
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug
      t = @model_class.arel_table
      value = @model_class.scoped # returns ActiveRecord::Relation equivalent to select with no where clause
      custom_query = self.action_to_query[params[:action].to_s]
      if custom_query
        value = custom_query.call(t, value)
      end

      self.param_to_query.each do |param_name, param_query|
        if params[param_name]
          # to_s as safety measure for vulnerabilities similar to CVE-2013-1854
          value = param_query.call(t, value, params[param_name].to_s)
        end
      end

      self.param_to_through.each do |param_name, through_array|
        if params[param_name]
          # build query
          # e.g. SomeModel.scoped.joins({:assoc_name => {:sub_assoc => {:sub_sub_assoc => :sub_sub_sub_assoc}}).where(sub_sub_sub_assoc_model_table_name: {column_name: value})
          last_model_class = @model_class
          joins = nil # {:assoc_name => {:sub_assoc => {:sub_sub_assoc => :sub_sub_sub_assoc}}
          through_array.each do |association_or_attribute|
            if association_or_attribute == through_array.last
              # must convert param value to string before possibly using with ARel because of CVE-2013-1854, fixed in: 3.2.13 and 3.1.12 
              # https://groups.google.com/forum/?fromgroups=#!msg/rubyonrails-security/jgJ4cjjS8FE/BGbHRxnDRTIJ
              value = value.joins(joins).where(last_model_class.table_name.to_sym => {association_or_attribute => params[param_name].to_s})
            else
              found_classes = last_model_class.reflections.collect {|association_name, reflection| reflection.class_name.constantize if association_name.to_sym == association_or_attribute}.compact
              if found_classes.size > 0
                last_model_class = found_classes[0]
              else
                # bad can_filter_by :through found at runtime
                raise "Association #{association_or_attribute.inspect} not found on #{last_model_class}."
              end

              if joins.nil?
                joins = association_or_attribute
              else
                joins = {association_or_attribute => joins}
              end
            end
          end
        end
      end

      self.param_to_attr_and_arel_predicate.keys.each do |param_name|
        options = param_to_attr_and_arel_predicate[param_name][2]
        # to_s as safety measure for vulnerabilities similar to CVE-2013-1854 
        param = params[param_name].to_s || options[:with_default]

        if param.present? && param_to_attr_and_arel_predicate[param_name]
          attr_sym = param_to_attr_and_arel_predicate[param_name][0]
          predicate_sym = param_to_attr_and_arel_predicate[param_name][1]
          if predicate_sym == :eq
            value = value.where(attr_sym => convert_request_param_value_for_filtering(attr_sym, param).split(','))
          else
            one_or_more_param = param.split(self.filter_split).collect{|v|convert_request_param_value_for_filtering(attr_sym, v)}
            value = value.where(t[attr_sym].try(predicate_sym, one_or_more_param))
          end
        end
      end

      if params[:page] && self.supported_functions.include?(:page)
        page = params[:page].to_i
        page = 1 if page < 1 # to avoid people using this as a way to get all records unpaged, as that probably isn't the intent?
        #TODO: to_s is hack to avoid it becoming an Arel::SelectManager for some reason which not sure what to do with
        value = value.skip((self.number_of_records_in_a_page * (page - 1)).to_s)
        value = value.take((self.number_of_records_in_a_page).to_s)
      end

      if params[:skip] && self.supported_functions.include?(:skip)
        # to_s as safety measure for vulnerabilities similar to CVE-2013-1854
        value = value.skip(params[:skip].to_s)
      end

      if params[:take] && self.supported_functions.include?(:take)
        # to_s as safety measure for vulnerabilities similar to CVE-2013-1854
        value = value.take(params[:take].to_s)
      end

      if params[:uniq] && self.supported_functions.include?(:uniq)
        value = value.uniq
      end

      # these must happen at the end and are independent
      if params[:count] && self.supported_functions.include?(:count)
        value = value.count.to_i
      elsif params[:page_count] && self.supported_functions.include?(:page_count)
        count_value = value.count.to_i # this executes the query so nothing else can be done in AREL
        value = (count_value / self.number_of_records_in_a_page) + (count_value % self.number_of_records_in_a_page ? 1 : 0)
      else
        self.ordered_by.each do |attr_to_direction|
          # this looks nasty, but makes no sense to iterate keys if only single of each
          value = value.order(t[attr_to_direction.keys[0]].send(attr_to_direction.values[0]))
        end
        value = value.to_a
      end

      @value = value
      @value.each {|obj| authorize! :read, obj}

      instance_variable_set(@model_at_plural_name_sym, @value)
      render_or_respond(true)
    rescue self.rescue_class => e
      handle_or_raise(e)
    end

    # The controller's show (get) method to return a resource.
    def show
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug
      # to_s as safety measure for vulnerabilities similar to CVE-2013-1854
      @value = @model_class.where(id: params[:id].to_s).first # don't raise exception if not found
      authorize! :read,@value

      instance_variable_set(@model_at_singular_name_sym, @value)
      render_or_respond(true, @value.nil? ? :not_found : :ok)
    rescue self.rescue_class => e
      handle_or_raise(e)
    end

    # The controller's new method (e.g. used for new record in html format).
    def new
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug
      @value = @model_class.new
      instance_variable_set(@model_at_singular_name_sym, @value)
      render_or_respond(true)
    rescue self.rescue_class => e
      handle_or_raise(e)
    end

    # The controller's edit method (e.g. used for edit record in html format).
    def edit
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug
      # to_s as safety measure for vulnerabilities similar to CVE-2013-1854
      @value = @model_class.where(id: params[:id].to_s).first! # raise exception if not found
      instance_variable_set(@model_at_singular_name_sym, @value)
      @value
    rescue self.rescue_class => e
      handle_or_raise(e)
    end

    # The controller's create (post) method to create a resource.
    def create
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug

     if self.use_permitters
        #authorize! :create, @model_class
        allowed_params = permitted_params
      elsif respond_to? @create_model_singular_name_params_sym
        allowed_params = send(@create_model_singular_name_params_sym)
      elsif respond_to? @model_singular_name_params_sym
        allowed_params = send(@model_singular_name_params_sym)
      else
        allowed_params = params
      end

      @value = @model_class.new(allowed_params)
      authorize! :create, @value
      @value.save
      instance_variable_set(@model_at_singular_name_sym, @value)
      render_or_respond(false, :created)
    rescue self.rescue_class => e
      handle_or_raise(e)
    end

    # The controller's update (put) method to update a resource.
    def update
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug
      if self.use_permitters
#        authorize! :update, @model_class
        allowed_params = permitted_params
      elsif respond_to? @create_model_singular_name_params_sym
        allowed_params = send(@update_model_singular_name_params_sym)
      elsif respond_to? @model_singular_name_params_sym
        allowed_params = send(@model_singular_name_params_sym)
      else
        allowed_params = params

      end
      # to_s as safety measure for vulnerabilities similar to CVE-2013-1854
      @value = @model_class.where(id: params[:id].to_s).first # don't raise exception
      authorize! :update, @value
      @value.update_attributes(allowed_params) unless @value.nil?
      instance_variable_set(@model_at_singular_name_sym, @value)
      render_or_respond(true, @value.nil? ? :not_found : :ok)
    rescue self.rescue_class => e
      handle_or_raise(e)
    end

    # The controller's destroy (delete) method to destroy a resource.
    def destroy
      logger.debug "#{params[:action].to_s} called in #{self.class}: model=#{@model_class}, request.format=#{request.format}, request.content_type=#{request.content_type}, params=#{params.inspect}" if self.debug
      # to_s as safety measure for vulnerabilities similar to CVE-2013-1854


      @value = @model_class.where(id: params[:id].to_s).first # don't raise exception
      #added authorize to destroy!
      authorize! :destroy, @value
      @value.destroy if @value
      instance_variable_set(@model_at_singular_name_sym, @value)
      if !@value.respond_to?(:errors) || @value.errors.empty? || (request.format != 'text/html' && request.content_type != 'text/html')
        # don't require a destroy view for success, because it isn't implements in Rails by default for json
        respond_to do |format|
          format.any  { head :ok }
        end
      else
        render_or_respond(false)
      end
    rescue self.rescue_class => e
      handle_or_raise(e)
    end
  end
end
