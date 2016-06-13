module Blazer
  class Check < ActiveRecord::Base
    belongs_to :query

    validates :query_id, presence: true

    before_validation :set_state

    def set_state
      self.state ||= "new"
    end

    def split_emails
      emails.to_s.downcase.split(",").map(&:strip)
    end

    def update_state(rows, error)
      invert = respond_to?(:invert) && self.invert
      self.state =
        if error
          if error == Blazer::TIMEOUT_MESSAGE
            "timed out"
          else
            "error"
          end
        elsif rows.any?
          invert ? "passing" : "failing"
        else
          invert ? "failing" : "passing"
        end

      self.last_run_at = Time.now if respond_to?(:last_run_at=)

      if respond_to?(:timeouts=)
        if state == "timed out"
          self.timeouts += 1
          self.state = "disabled" if timeouts >= 3
        else
          self.timeouts = 0
        end
      end

      if notify?
        Blazer::CheckMailer.state_change(self, state, state_was, rows.size, error).deliver_later
      end
      save! if changed?
    end

    protected

      def notify?
        send_it = true
        send_it &&= emails.present?

        # Do not notify if the state has not changed
        send_it &&= (state != state_was)

        # Do not notify on creation, except when not passing
        send_it &&= (state_was || state != "passing")

        if self.respond_to?(:notify_on_error)
          # Do not notify on error when notify_on_error is false
          send_it &&= (state != "error" || notify_on_error)

          # Do not send on passing when notify_on_pass is false, or when notify_on_pass is true but
          # the previous state was 'error' and notify_on_error is false.
          send_it &&= (state != "passing" || (notify_on_pass && (state_was != "error" || notify_on_error)))
        end

        send_it
      end
  end
end
