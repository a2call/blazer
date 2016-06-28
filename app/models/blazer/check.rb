module Blazer
  class Check < ActiveRecord::Base
    belongs_to :creator, Blazer::BELONGS_TO_OPTIONAL.merge(class_name: Blazer.user_class.to_s) if Blazer.user_class
    belongs_to :query

    validates :query_id, presence: true

    before_validation :set_state

    def set_state
      self.state ||= "new"
    end

    def split_emails
      emails.to_s.downcase.split(",").map(&:strip)
    end

    def update_state(columns, rows, error, data_source)
      check_type =
        if respond_to?(:check_type)
          self.check_type
        elsif respond_to?(:invert)
          invert ? "missing_data" : "bad_data"
        else
          "bad_data"
        end

      message = error

      self.state =
        if error
          if error == Blazer::TIMEOUT_MESSAGE
            "timed out"
          else
            "error"
          end
        elsif check_type == "anomaly"
          anomaly, message = Blazer.detect_anomaly(columns, rows, data_source)
          if anomaly.nil?
            "error"
          elsif anomaly
            "failing"
          else
            "passing"
          end
        elsif rows.any?
          check_type == "missing_data" ? "passing" : "failing"
        else
          check_type == "missing_data" ? "failing" : "passing"
        end

      self.last_run_at = Time.now if respond_to?(:last_run_at=)
      self.message = message if respond_to?(:message=)

      if respond_to?(:timeouts=)
        if state == "timed out"
          self.timeouts += 1
          self.state = "disabled" if timeouts >= 3
        else
          self.timeouts = 0
        end
      end

      # do not notify on creation, except when not passing
      if notify?
        Blazer::CheckMailer.state_change(self, state, state_was, rows.size, message).deliver_later
      end
      save! if changed?
    end

    protected

      def notify?
        send_it = true
        send_it &&= emails.present?

        # Do not notify if the state has not changed
        send_it &&= (state != state_was)

        error_states = ["error", "timed out"]

        # Do not notify on creation, except when not passing
        send_it &&= (state_was || state != "passing")

        if self.respond_to?(:notify_on_error)
          # Do not notify on error when notify_on_error is false
          send_it &&= (!state.in?(error_states) || notify_on_error)

          # Do not send on passing when notify_on_pass is false, or when notify_on_pass is true but
          # the previous state was 'error' and notify_on_error is false.
          send_it &&= (state != "passing" || (notify_on_pass && (!state_was.in?(error_states) || notify_on_error)))
        end

        send_it
      end
  end
end
