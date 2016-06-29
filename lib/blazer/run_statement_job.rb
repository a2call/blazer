require "sucker_punch"

module Blazer
  class RunStatementJob
    include SuckerPunch::Job
    workers 4

    def perform(result, data_source, statement, options, queued_at)
      run_id = options[:run_id]
      started_at = Time.now
      queue_time = started_at - queued_at
      Rails.logger.info "[blazer queue time] #{run_id} #{(queue_time.to_f * 1000).round}ms"
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          data_source.connection_model.connection_pool.with_connection do
            pool_time = Time.now - started_at
            Rails.logger.info "[blazer pool time] #{(pool_time.to_f * 1000).round}ms"
            result << data_source.run_main_statement(statement, options)
          end
        end
        Rails.logger.info "[blazer job done] #{run_id}"
      rescue Exception => e
        Rails.logger.info "[blazer async error] #{e.class.name} #{e.message}"
        result.clear
        result.concat([[], [], "Unknown error", nil])
        Blazer.cache.write(data_source.run_cache_key(options[:run_id]), Marshal.dump(result), expires_in: 30.seconds)
        raise e
      end
    end
  end
end
