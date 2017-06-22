require 'mongo'
require 'logstash/inputs/base'

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

lv = LastValueStore.new('/home/artem', 'mex.txt')

lv.save_last_value("blasaldkfj")
puts lv.get_last_value

#mongo = MongoAccessor.new('mongodb://192.168.1.37/eleet-v2-dev', 'system.profile')

#ProfileCollection.new(mongo.get_documents(10)).each do |document|
  #puts document['_id']
#end


