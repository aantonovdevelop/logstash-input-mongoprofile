# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/mongoprofile"

describe LogStash::Inputs::Mongoprofile do

  it_behaves_like "an interruptible input plugin" do
    let(:config) { { "interval" => 100, "url" => "mongodb://192.168.1.37/eleet-v2-dev", "path" => "/home/artem"} }
  end

end
