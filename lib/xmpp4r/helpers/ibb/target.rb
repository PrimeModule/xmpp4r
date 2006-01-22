module Jabber
  module Helpers
    ##
    # Implementation of IBB at the target side
    class IBBTarget < IBB
      def initialize(stream, session_id, initiator_jid, target_jid)
        # Target and Initiator are swapped here, because we're the target
        super(stream, session_id, target_jid, initiator_jid)
      end

      ##
      # Wait for the initiator side to start
      # the stream.
      def accept
        connect_lock = Mutex.new
        connect_lock.lock

        @stream.add_iq_callback(200, "#{callback_ref} open") { |iq|
          open = iq.first_element('open')
          if iq.type == :set and iq.from == @peer_jid and iq.to == @my_jid and open and open.attributes['sid'] == @session_id
            @stream.delete_iq_callback("#{callback_ref} open")
            activate
            @block_size = (open.attributes['block-size'] || 4096).to_i

            reply = iq.answer(false)
            reply.type = :result
            @stream.send(reply)
              
            connect_lock.unlock
            true
          else
            false
          end
        }

        connect_lock.lock
        connect_lock.unlock
        true
      end
    end
  end
end

