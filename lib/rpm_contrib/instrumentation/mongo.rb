# Mongo Instrumentation contributed by Alexey Palazhchenko
DependencyDetection.defer do
  @name = :mongodb
  
  depends_on do
    defined?(::Mongo) and not NewRelic::Control.instance['disable_mongodb']
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing MongoDB instrumentation'
  end  

  executes do
    ::Mongo::Logging.class_eval do
      include NewRelic::Agent::MethodTracer

      def instrument_with_newrelic_trace(name, payload = {}, &blk)
        if payload[:database] == "admin"
          return instrument_without_newrelic_trace(name, payload, &blk)
        end

        collection = payload[:collection]
        if collection == '$cmd'
          f = payload[:selector].first
          name, collection = f if f
        end

        trace_execution_scoped("Database/#{collection}/#{name}") do
          t0 = Time.now
          res = instrument_without_newrelic_trace(name, payload, &blk)
          NewRelic::Agent.instance.transaction_sampler.notice_sql(payload.inspect, nil, (Time.now - t0).to_f)
          res
        end
      end

      alias_method :instrument_without_newrelic_trace, :instrument
      alias_method :instrument, :instrument_with_newrelic_trace
    end
    class Mongo::Collection; include Mongo::Logging; end
    class Mongo::Connection; include Mongo::Logging; end
    class Mongo::Cursor; include Mongo::Logging; end

    ::Mongo::Cursor.class_eval do
      include NewRelic::Agent::MethodTracer
      add_method_tracer :send_get_more, 'Database/#{collection.name}/refresh'
    end
  end

end
