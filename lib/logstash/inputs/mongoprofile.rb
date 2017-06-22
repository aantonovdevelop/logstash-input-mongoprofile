# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "socket" # for Socket.gethostname
require "mongo"

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
  end

  # def register

  def run(queue)
    # we can abort the loop if stop? becomes true
    while !stop?
      begin

        @controller.get_next_events.each do |event|
          @logger.info("Send event #{event}")

          decorate(event)
          queue << event
        end

        # because the sleep interval can be big, when shutdown happens
        # we want to be able to abort the sleep
        # Stud.stoppable_sleep will frequently evaluate the given block
        # and abort the sleep(@interval) if the return value is true
        Stud.stoppable_sleep(@interval) {stop?}
      rescue => e
        @logger.warn('MongoProfile input threw an exception, restarting', :exception => e)
        @logger.warn(e.backtrace.inspect)
      end
    end # loop
  end

  # def run

  def stop
    # nothing to do in this case so it is not necessary to define stop
    # examples of common "stop" tasks:
    #  * close sockets (unblocking blocking reads/accepts)
    #  * cleanup temporary files
    #  * terminate spawned threads
  end
end # class LogStash::Inputs::Mongoprofile

class MongoAccessor
  def initialize(url, collection, client_host)
    connection = Mongo::Client.new(url)

    @mongodb = connection.database
    @collection = @mongodb.collection(collection)
    @client_host = client_host
  end

  def get_documents_by_ts(date, limit)
    @collection.find({:ts => {:$gt => date}, :client => {:$ne => @client_host}}).limit(limit)
  end

  def get_documents(limit)
    @collection.find({:client => {:$ne => @client_host}}).limit(limit)
  end
end

class ProfileCollection
  def initialize(documents, parser)
    @documents = documents
    @parser = parser
  end

  def each
    @documents.each do |document|
      document['_id'] = generate_id
      yield @parser.parse(document)
    end
  end

  def get_last_document_date
    @documents[-1]['ts']
  end

  private
  def generate_id
    # noinspection RubyArgCount
    BSON::ObjectId.new
  end
end

class DocumentParser
  def initialize(host)
    @host = host
  end

  def parse(document)
    event = LogStash::Event.new('host' => @host)

    document.each do |key, value|
      event.set(key, value)
    end

    event
  end
end

class LastValueStore
  def initialize(path, name)
    @file_full_name = "#{path}/#{name}"
  end

  def save_last_value(value)
    file = File.open(@file_full_name, 'a+')

    file.truncate(0)
    file.puts(value)

    file.close
  end

  def get_last_value
    File.read(@file_full_name)
  end
end

class Controller
  def initialize(event, url, collection, limit, path, client_host)
    @mongo_accessor = MongoAccessor.new(url, collection, client_host)
    @last_value_store = LastValueStore.new(path, collection)
    @document_parser = DocumentParser.new(event)
    @limit = limit
  end

  def get_next_events
    last_date_value = @last_value_store.get_last_value

    if last_date_value == ''
      documents = @mongo_accessor.get_documents(@limit)
    else
      documents = @mongo_accessor.get_documents_by_ts(last_date_value, @limit)
    end

    profile_collection = ProfileCollection.new(documents, @document_parser)

    @last_value_store.save_last_value(profile_collection.get_last_document_date)

    profile_collection
  end
end