# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "socket" # for Socket.gethostname
require '../../../lib/mongo/mongo'

# Generate a repeating message.
#
# This plugin is intented only as an example.

class LogStash::Inputs::Mongoprofile < LogStash::Inputs::Base
  config_name "mongoprofile"

  default :codec, "plain"

  config :message, :validate => :string, :default => "Default message"
  config :interval, :validate => :number, :default => 10
  config :url, :validate => :string, :required => true
  config :path, :validate => :string, :required => true
  config :client_host, :validate => :string, :default => '127.0.0.1'

  public
  def register
    @host = Socket.gethostname
    @controller = Controller.new(@host, @url, 'system.profile', 1000, @path, @client_host)
  end # def register

  def run(queue)
    # we can abort the loop if stop? becomes true
    while !stop?

      @controller.get_next_events.each do |event|
        @logger.info("Send event #{event}")

        decorate(event)
        queue << event
      end

      # because the sleep interval can be big, when shutdown happens
      # we want to be able to abort the sleep
      # Stud.stoppable_sleep will frequently evaluate the given block
      # and abort the sleep(@interval) if the return value is true
      Stud.stoppable_sleep(@interval) { stop? }
    end # loop
  end # def run

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end
end # class LogStash::Inputs::Mongoprofile
