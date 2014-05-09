require 'date'
require_relative 'tabs/applications_tab'
require_relative 'tabs/routes_tab'
require_relative 'tabs/service_instances_tab'

module AdminUI
  class Tabs
    def initialize(config, logger, cc, varz)
      @cc     = cc
      @config = config
      @logger = logger
      @varz   = varz

      @caches = {}
      # These keys need to conform to their respective discover_x methods.
      # For instance applications conforms to discover_applications
      [:applications, :routes, :service_instances].each do |key|
        hash = { :semaphore => Mutex.new, :condition => ConditionVariable.new, :result => nil }
        @caches[key] = hash

        Thread.new do
          loop do
            schedule_discovery(key, hash)
          end
        end
      end
    end

    def invalidate_applications
      invalidate_cache(:applications)
    end

    def invalidate_routes
      invalidate_cache(:routes)
    end

    def applications
      result_cache(:applications)
    end

    def routes
      result_cache(:routes)
    end

    def service_instances
      result_cache(:service_instances)
    end

    private

    def invalidate_cache(key)
      hash = @caches[key]
      hash[:semaphore].synchronize do
        hash[:result] = nil
        hash[:condition].broadcast
      end
    end

    def schedule_discovery(key, hash)
      key_string = key.to_s

      @logger.debug("[#{ @config.cloud_controller_discovery_interval } second interval] Starting Tabs #{ key_string } discovery...")

      result_cache = send("discover_#{ key_string }".to_sym)

      hash[:semaphore].synchronize do
        @logger.debug("Caching Tabs #{ key_string } data...")
        hash[:result] = result_cache
        hash[:condition].broadcast
        hash[:condition].wait(hash[:semaphore], @config.cloud_controller_discovery_interval)
      end
    end

    def result_cache(key)
      hash = @caches[key]
      hash[:semaphore].synchronize do
        hash[:condition].wait(hash[:semaphore]) while hash[:result].nil?
        hash[:result]
      end
    end

    def discover_applications
      AdminUI::ApplicationsTab.new(@logger, @cc, @varz).items
    end

    def discover_routes
      AdminUI::RoutesTab.new(@logger, @cc, @varz).items
    end

    def discover_service_instances
      AdminUI::ServiceInstancesTab.new(@logger, @cc, @varz).items
    end
  end
end