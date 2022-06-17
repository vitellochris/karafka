# frozen_string_literal: true

# When using automatic offset management, we should end up with offset committed after the last
# message and we should "be" there upon returning to processing

setup_karafka do |config|
  config.max_messages = 5
  config.license.token = pro_license_token
end

class Consumer < Karafka::Pro::BaseConsumer
  def consume
    DataCollector[0] << messages.last.offset
  end
end

draw_routes do
  consumer_group DataCollector.consumer_group do
    topic DataCollector.topic do
      consumer Consumer
      long_running_job true
    end
  end
end

payloads = Array.new(20) { SecureRandom.uuid }

payloads.each { |payload| produce(DataCollector.topic, payload) }

start_karafka_and_wait_until do
  DataCollector[0].size >= 1
end

# Now when w pick up the work again, it should start from the first message
consumer = setup_rdkafka_consumer

consumer.subscribe(DataCollector.topic)

consumer.each do |message|
  DataCollector[1] << message.offset

  break
end

assert_equal DataCollector[0].last + 1, DataCollector[1].first

consumer.close