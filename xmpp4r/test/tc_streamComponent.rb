#!/usr/bin/ruby

$:.unshift '../lib'

require 'tempfile'
require 'test/unit'
require 'socket'
require 'xmpp4r/component'
require 'xmpp4r/bytestreams'
require 'xmpp4r'
require 'semaphore'
include Jabber

Thread::abort_on_exception = true

class StreamComponentTest < Test::Unit::TestCase
  @@SOCKET_PORT = 65224

  def setup
    servlisten = TCPServer.new(@@SOCKET_PORT)
    serverwait = Semaphore.new
    Thread.new {
      serversock = servlisten.accept
      servlisten.close
      serversock.sync = true
      @server = Stream.new(true)
      @server.add_xml_callback { |xml|
        if xml.prefix == 'stream' and xml.name == 'stream'
          @server.send('<stream:stream xmlns="jabber:component:accept">')
          true
        else
          false
        end
      }
      @server.start(serversock)
      
      serverwait.run
    }

    @stream = Component::new('test')
    @stream.connect('localhost', @@SOCKET_PORT)

    serverwait.wait
  end

  def teardown
    @stream.close
    @server.close
  end

  def test_process
    stanzas = 0
    message_lock = Semaphore.new
    iq_lock = Semaphore.new
    presence_lock = Semaphore.new

    @stream.add_message_callback { |msg|
      assert_kind_of(Message, msg)
      stanzas += 1
      message_lock.run
    }
    @stream.add_iq_callback { |iq|
      assert_kind_of(Iq, iq)
      stanzas += 1
      iq_lock.run
    } 
    @stream.add_presence_callback { |pres|
      assert_kind_of(Presence, pres)
      stanzas += 1
      presence_lock.run
    }

    @server.send('<message/>')
    @server.send('<iq/>')
    @server.send('<presence/>')

    message_lock.wait
    iq_lock.wait
    presence_lock.wait

    assert_equal(3, stanzas)
  end

  def test_file
    incoming_lock = Semaphore.new

    ft = Jabber::FileTransfer::Helper.new(@stream)
    ft.add_incoming_callback do |iq,file|
      assert_kind_of(Bytestreams::IqSiFile, file)
      incoming_lock.run
    end

    @server.send("
<iq from='test@local' type='set' to='disk' id='1'>
  <si mime-type='application/octet-stream' profile='http://jabber.org/protocol/si/profile/file-transfer' id='11' xmlns='http://jabber.org/protocol/si'>
    <file name='test' size='105' xmlns='http://jabber.org/protocol/si/profile/file-transfer'>
      <desc/>
    </file>
    <feature xmlns='http://jabber.org/protocol/feature-neg'>
      <x type='form' xmlns='jabber:x:data'>
        <field type='list-single' var='stream-method'>
	  <option><value>http://jabber.org/protocol/bytestreams</value></option>
	  <option><value>http://jabber.org/protocol/iqibb</value></option>
	  <option><value>http://jabber.org/protocol/ibb</value></option>
	</field>
      </x>
    </feature>
  </si>
</iq>
")
    incoming_lock.wait
  end

  def test_outgoing
    received_wait = Semaphore.new

    @server.add_message_callback { |msg|
      assert_kind_of(Message, msg)
      received_wait.run
    }

    @stream.send(Message.new)
    received_wait.wait
  end
end
