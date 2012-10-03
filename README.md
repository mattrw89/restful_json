restful_json v3 for Rails 3.1+
=====

A restful_json (maybe we'll rename it because it isn't json-specific at the moment) controller is a configurable generic Rails 3.1+ controller that does the index, show, create, and update for you and has stuff for paging, filtering etc. that is mostly declarative to try to help you avoid unintentional crazy or insecure queries on your DB.

It is both Rails 3.1+ and Rails 4 friendly-ish, too.

Uses Adam Hawkin's [permitter][permitter] code which uses [strong_parameters][strong_parameters] and encourages use of [active_model_serializers][active_model_serializers].

### In alpha

So, it's subject to change and may be broken.

### Configuration

In your Rails 3.2.8+, < 4.0 app:

in `Gemfile`:

    gem 'restful_json', '>= 3.0.0.alpha.2', :git => 'git://github.com/garysweaver/restful_json.git'

This is *not recommended* for rails 3.2.x apps. Since using strong_parameters, we'll probably wrongly assume you are using it which may mean in `config/application.rb` that you might have:

    config.active_record.whitelist_attributes = false

in `config/application.rb` you can set config items one at a time like:

    RestfulJson.debug = true

or in bulk like:

    RestfulJson.configure do
      self.debug = true
      self.can_filter_by_default_using = [:eq]
      self.predicate_prefix = '!'
      self.filter_split = ','
    end

#### Controller: Advanced Configuration

In the controller for advanced configuration you can set a variety of class attributes with `self.something = ...` in the body of your controller to set model class, variable names, messages, etc. Take a look at the class_attribute definitions in `lib/restful_json/controller.rb`.

### What happens in your models

Nothing you need to do other than normal stuff, and strong_parameters means no more mass assignment security stuff like attr_accessible or attr_protected.

It does this in a railtie:

    # ActiveRecord::Base gets new behavior
    include RestfulJson::Model

Which in turn just does this for now for strong_parameters:

    include ::ActiveModel::ForbiddenAttributesProtection

### What a restful_json controller looks like and what it does

A restful_json (ok, it is really neither RESTful, nor is it just JSON- discuss!) controller is a configurable generic Rails 3.1+ controller that does the index, show, create, and update for you.

Everything is (fairly) well-declared:

    class FoobarsController < ApplicationController  
      acts_as_restful_json
      can_filter_by :foo_id # implied support for ARel eq
      can_filter_by :foo_date, :bar_date, using: [:lt, :eq, :gt]
      supports_functions :count
      # respond_to :json, :html # specify if you want more than :json and it should work, in-theory. uses respond_with.
    end

`can_filter_by` means you can send in that request param (via routing or directly, just like normal in Rails) and it will use that in the ARel query (safe from SQL injection and only letting you do what you tell it). `:using` means you can use those ARel predicates for filtering. For a full list of available ones do:

    rails c
    Arel::Predications.public_instance_methods.sort

at time of writing these were:

    [:does_not_match, :does_not_match_all, :does_not_match_any, :eq, :eq_all, :eq_any, :gt, :gt_all, :gt_any, :gteq, :gteq_all, :gteq_any, :in, :in_all, :in_any, :lt, :lt_all, :lt_any, :lteq, :lteq_all, :lteq_any, :matches, :matches_all, :matches_any, :not_eq, :not_eq_all, :not_eq_any, :not_in, :not_in_all, :not_in_any]

`supports_functions` lets you do other ARel functions. `:uniq`, `:skip`, `:take`, and `:count`.

### Examples

#### Attribute value filter

First, declare in the controller:

    can_filter_by :foo_id

Get Foobars with a foo_id of '1':

    http://localhost:3000/foobars?foo_id=1

#### Attribute value filter

First, declare in the controller:

    can_filter_by :seen_on, using: [:gteq, :eq_any]

Get Foobars with seen_on of 2012-08-08 or later using the ARel gteq predicate splitting the request param on `predicate_prefix` (configurable), you'd use:

    http://localhost:3000/foobars?seen_on!gteq=2012-08-08

Multiple values are separated by `filter_split` (configurable):

    http://localhost:3000/foobars?seen_on!eq_any=2012-08-08,2012-09-09

#### Count

First, declare in the controller:

    supports_functions :uniq

To return a simple unique view of a model, combine use of an active_model_serializer that returns just the attribute you want along with the uniq param, e.g. to return unique/distinct colors of foobars you'd have a serializer to just return the color and then use:

    http://localhost:3000/foobars?uniq=

#### Count

First, declare in the controller:

    supports_functions :count

This is another filter that can be used with the others, but instead of returning the json objects, it returns their count, which is useful for paging to determine how many results you can page through:

    http://localhost:3000/foobars?count=

##### Paging

In controller make sure these are included:

    supports_functions :skip, :take

To skip rows returned, use 'skip'. It is called take, because skip is the AREL equivalent of SQL OFFSET:

    http://localhost:3000/foobars?skip=5

To limit the number of rows returned, use 'take'. It is called take, because take is the AREL equivalent of SQL LIMIT:

    http://localhost:3000/foobars.json?take=5

Combine skip and take for manual completely customized paging.

Get the first page of 15 results:

    http://localhost:3000/foobars?take=15

Second page of 15 results:

    http://localhost:3000/foobars?skip=15&take=15

Third page of 15 results:

    http://localhost:3000/foobars?skip=30&take=15

First page of 30 results:

    http://localhost:3000/foobars?take=30

Second page of 30 results:

    http://localhost:3000/foobars?skip=30&take=30

Third page of 30 results:

    http://localhost:3000/foobars?skip=60&take=30

### License

Copyright (c) 2012 Gary S. Weaver, released under the [MIT license][lic].

[permitter]: http://broadcastingadam.com/2012/07/parameter_authorization_in_rails_apis/
[strong_parameters]: https://github.com/rails/strong_parameters
[active_model_serializers]: https://github.com/josevalim/active_model_serializers
[strong_parameters]: 
[lic]: http://github.com/garysweaver/restful_json/blob/master/LICENSE
