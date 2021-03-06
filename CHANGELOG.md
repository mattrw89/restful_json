## restful_json 3.4.2 ##

* Removing rescue_from's from DefaultController that would require additional controller methods if default error handling not used.

## restful_json 3.4.1 ##

* Try to require 'active_record/errors' before referring to `ActiveRecord::RecordNotFound` in gem default config.
* Don't add permitters to autoload path if RestfulJson.use_permitters is false in environment or initializer.
* Railtie that adds deprecated acts_as_restful_json support now being required.
* Added activesupport runtime dependency to gemspec.
* Missing i18n key now defaults to error.message.

## restful_json 3.4.0 ##

* Added rescue_class config option to indicate highest level class to rescue for every action. (nil/NilClass indicates to re-raise StandardError.)
* Added rescue_handlers config option as substitute for having to rescue, log, set status and i18n message key for sets of exceptions.
* Added return_error_data config option to also return the exception's class.name, class.message, and class.backtrace (cleaned) in "error_data" in error response.

## restful_json 3.3.4 ##

* If debug config option true, controller/app will now log debug to Rails logger.
* Fixing bug: will return head: ok with no body on destroy for no errors in formats other than HTML, like it did in versions before restful_json v3.3.0.

## restful_json 3.3.3 ##

* Using `.where(id: params[:id].to_s).first` in show/update/destroy, `.where(id: params[:id].to_s).first!` in edit.
* No more deprecated find(id) in show/edit.

## restful_json 3.3.2 ##

* Removed unnecessary debug logging of permitter class, and now only outputs if can't find when debug on.

## restful_json 3.3.1 ##

* Update and destroy use where instead of find and update 404's for missing record.
* Important fixes to recommendations around use of modules in doc.
* Removed unnecessary debug logging of serializer.

## restful_json 3.3.0 ##

* Added avoid_respond_with config option to always use render instead of respond_with.
* Fixing bug in serialize_action.
* Consolidated controller rendering.
* Better isolated controller and model changes, made model changes for Cancan and Strong Parameters something that needs to be done in configuration.
* Tests for Rails 3.1, 3.2, 4.

## restful_json 3.2.2 ##

* Fixing bug in order_by.
* Working on travis-ci config and appraisals/specs for testing Rails 3.1/3.2/4.0.

## restful_json 3.2.1 ##

* Important change to README that should not use acts_as_restful_json in parent/ancestor class shared by multiple controllers, because it is unsafe.
* Fixing bug in delete related to custom serializer when using AMS.

## restful_json 3.2.0 ##

* Made active_model_serializers, strong_parameters, Permitters, Cancan all optional.
* Added support for strong_parameters without Permitters/Cancan, allowing *_params methods in controller.
* Fixing double rendering bug on create in 3.1.0.

## restful_json 3.1.0 ##

* Added ActiveModel Serializer custom serializer per action(s) support.
* Added JBuilder support.
* Fixing gemspec requirements to not include things it shouldn't.

## restful_json 3.0.1 ##

* Updated order_by, comments.

## restful_json 3.0.0 ##

* Controller with declaratively configured RESTful-ish JSON services, filtering, custom queries, actions, etc. using strong parameters, a.m. serializers, and Adam Hawkins (twinturbo) permitters
